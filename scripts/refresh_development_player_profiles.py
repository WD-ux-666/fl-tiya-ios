#!/usr/bin/env python3
"""Exact-five development portrait refresh. Credentials never leave memory.

render preserves old snapshots and emits guarded apply/restore SQL for review.
upload uses each verified owner's session and immutable paths; staged objects
remain unreadable until profile attachment under existing Storage RLS.
verify reads the live profile/community/feed/comment/avatar paths as Alpha.
SQL execution is a separate administrative action; no schema changes are made.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
import uuid

from import_development_clips import ROOT
from transfer_development_clip_publishers import Client, FIXTURE_ACCESS, close_session, request, require, rpc

PROJECT = 'gpstwmffctwqlcakmvgw'
PLAN = ROOT / '.planning/2026-11-03-supabase-backend'
MANIFEST = ROOT / 'supabase/content/development-player-profiles-2026-11-06.json'
ASSETS = ROOT / 'docs/assets/test-profiles'
STAGING = PLAN / 'test-profile-refresh-staged-2026-11-06.json'
IDENTITIES = [
    ('Development Alpha', 'Ethan Cole', 'ethan_cole',
     'Mostly here for good game clips and relaxed co-op. Always up for one more round.', None),
    ('Development Beta', 'Maya Reed', 'maya_reed',
     'Co-op nights, cozy builds and a playlist that never ends. Send me your favorite game clip.', 'maya-reed'),
    ('Development TEST Ember', 'Jade Park', 'jade_park',
     'Exploring New Eridu between coffee breaks. Here for character builds, good clips and chill teammates.', 'jade-park'),
    ('Development TEST Harbor', 'Leo Brooks', 'leo_brooks',
     'One more match usually means three. PUBG MOBILE, co-op games and keeping the squad laughing.', 'leo-brooks'),
    ('Development TEST Summit', 'Nina Vega', 'nina_vega',
     'Love a clever build and a hard boss fight. Trading game tips, sharing highlights and learning as I go.', 'nina-vega'),
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def render():
    require(not MANIFEST.exists(), 'Current overlay already exists; refuse to rerandomize avatar paths')
    baseline = json.loads((PLAN / 'test-profile-refresh-before-2026-11-06.json').read_text())
    require(baseline['handle_collisions'] is None, 'New handle collision')
    profiles = {p['reservation_label']: p for p in baseline['profiles']}
    require(set(profiles) == {p[0] for p in IDENTITIES}, 'Reserved identity scope changed')
    entries = []
    for label, name, handle, bio, slug in IDENTITIES:
        old = dict(profiles[label])
        del old['reservation_label']
        source = ASSETS / ('avatar-' + slug + '.png') if slug else ROOT / 'docs/assets/profile-male-portrait-20261106.png'
        data = source.read_bytes()
        require(data[:8] == b'\x89PNG\r\n\x1a\n', 'Expected original PNG')
        width, height = struct.unpack('>II', data[16:24])
        require(0 < len(data) <= 5 * 1024 * 1024 and 0 < width == height <= 4096, 'Avatar decode/storage bounds exceeded')
        current = dict(old, display_name=name, handle=handle, bio=bio,
                       avatar_path=old['avatar_path'] if slug is None else old['id'] + '/' + str(uuid.uuid4()) + '.png')
        entries.append(dict(id=old['id'], reservation_label=label, original=old, current=current,
                            upload_required=slug is not None, source=str(source.relative_to(ROOT)),
                            dimensions=[width, height], bytes=len(data), sha256=digest(data), mime='image/png'))
    manifest = dict(project_ref=PROJECT, date='2026-11-06', fictional=True, cohort='development',
                    description='Current profile overlay. Historical initialization, publisher and comment manifests remain immutable.',
                    portrait_provenance='docs/assets/test-profiles/portrait-provenance-2026-11-06.json',
                    profiles=entries, original_game_cards=baseline['game_cards'])
    write_json(MANIFEST, manifest)
    for restore in (False, True):
        generate_sql(manifest, restore)
    print(json.dumps({'rendered_profiles': len(entries), 'new_portraits': 4, 'game_card_aliases': len(baseline['game_cards'])}))


def generate_sql(m, restore):
    source, target = ('current', 'original') if restore else ('original', 'current')
    profiles = [dict(id=p['id'], label=p['reservation_label'], before=p[source], after=p[target],
                     bytes=p['bytes'], mime=p['mime']) for p in m['profiles']]
    by_id = {p['id']: p for p in m['profiles']}
    cards = []
    for original in m['original_game_cards']:
        current = dict(original, player_name=by_id[original['user_id']]['current']['display_name'])
        cards.append(dict(before=current if restore else original, after=original if restore else current))
    payload = json.dumps(dict(profiles=profiles, cards=cards), separators=(',', ':'))
    require('$refresh$' not in payload, 'SQL delimiter in data')
    sql = "begin;\nset local lock_timeout='5s';\nset local statement_timeout='20s';\n"
    sql += 'create temporary table expected_payload on commit drop as select $refresh$' + payload + '$refresh$::jsonb as value;\n'
    sql += """create temporary table expected_profiles on commit drop as
 select * from jsonb_to_recordset((select value->'profiles' from expected_payload))
 as e(id uuid,label text,before jsonb,after jsonb,bytes integer,mime text);
create temporary table expected_cards on commit drop as
 select * from jsonb_to_recordset((select value->'cards' from expected_payload)) as e(before jsonb,after jsonb);
select p.id from public.profiles p join expected_profiles e using(id) for update of p;
select g.user_id from public.game_cards g join expected_profiles e on e.id=g.user_id for update of g;
do $guard$ begin
 if (select count(*) from expected_profiles)<>5 or (select count(distinct id) from expected_profiles)<>5
 or (select count(*) from expected_cards)<>36 then raise exception 'Exact refresh scope changed';end if;
 if (select count(*) from public.profiles p join expected_profiles e on p.id=e.id
   and to_jsonb(p)=to_jsonb(jsonb_populate_record(null::public.profiles,e.before))
   join private.development_accounts d on d.user_id=p.id and d.label=e.label
   join private.accounts a on a.user_id=p.id where a.cohort='development' and a.state='active'
   and private.account_is_eligible(p.id))<>5 then raise exception 'Profile snapshot or development reservation changed';end if;
 if (select count(*) from public.game_cards g join expected_profiles e on e.id=g.user_id)<>36
 or (select count(*) from public.game_cards g join expected_cards e
   on to_jsonb(g)=to_jsonb(jsonb_populate_record(null::public.game_cards,e.before)))<>36
 then raise exception 'Game card snapshot changed';end if;
 if exists(select 1 from public.profiles p join expected_profiles e on p.handle=e.after->>'handle' and p.id<>e.id)
 then raise exception 'Handle collision';end if;
end $guard$;
"""
    if not restore:
        sql += """do $storage$ begin
 if (select count(*) from expected_profiles e join storage.objects o
   on o.bucket_id='avatars' and o.name=e.after->>'avatar_path' and o.owner_id=e.id::text
   and (o.metadata->>'size')::bigint=e.bytes and o.metadata->>'mimetype'=e.mime)<>5
 then raise exception 'Avatar object ownership or metadata mismatch';end if;
end $storage$;
"""
    sql += """update public.profiles p set display_name=e.after->>'display_name',handle=e.after->>'handle',
 bio=e.after->>'bio',avatar_path=e.after->>'avatar_path' from expected_profiles e where p.id=e.id;
update public.game_cards g set player_name=e.after->>'player_name' from expected_cards e
 where g.user_id=(e.before->>'user_id')::uuid and g.game_id=e.before->>'game_id';
do $verify$ begin
 if (select count(*) from public.profiles p join expected_profiles e on p.id=e.id
  and to_jsonb(p)=to_jsonb(jsonb_populate_record(null::public.profiles,e.after)))<>5
 or (select count(*) from public.game_cards g join expected_cards e
  on to_jsonb(g)=to_jsonb(jsonb_populate_record(null::public.game_cards,e.after)))<>36
 then raise exception 'Exact refresh readback failed';end if;
end $verify$;
commit;
select jsonb_build_object('profiles',5,'game_card_aliases',36,'operation','""" + ('restore' if restore else 'refresh') + "');\n"
    MANIFEST.with_name(MANIFEST.stem + ('-restore.sql' if restore else '-apply.sql')).write_text(sql)


def load_manifest():
    require(not (ROOT / 'supabase/content/development-community-rosters-2026-11-06.json').exists(),
            'Historical five-profile utility superseded by expand_development_communities.py')
    m = json.loads(MANIFEST.read_text())
    require(m['project_ref'] == PROJECT and m['cohort'] == 'development' and m['fictional'], 'Wrong project/cohort')
    require(len(m['profiles']) == 5 and len({p['id'] for p in m['profiles']}) == 5, 'Wrong profile scope')
    return m


def avatar(client, p, *, upload=False, anonymous=False, public=False):
    prefix = 'public/' if public else ('' if upload else 'authenticated/')
    headers = {'apikey': client.key}
    if not anonymous:
        headers['Authorization'] = 'Bearer ' + client.token
    if upload:
        data = (ROOT / p['source']).read_bytes()
        require(len(data) == p['bytes'] and digest(data) == p['sha256'], 'Local portrait changed')
        headers.update({'Content-Type': p['mime'], 'x-upsert': 'false', 'Cache-Control': 'max-age=0'})
    else:
        data = None
    return request(client.base + '/storage/v1/object/' + prefix + 'avatars/' + p['current']['avatar_path'],
                   headers=headers, data=data, method='POST' if upload else 'GET', limit=5 * 1024 * 1024)


def upload(m):
    staging = json.loads(STAGING.read_text())
    require(staging['manifest_sha256'] == digest(MANIFEST.read_bytes()), 'Staging manifest changed')
    objects = {o['name']: o for o in staging['objects']}
    for p in m['profiles']:
        if not p['upload_required']:
            continue
        account_file = FIXTURE_ACCESS if p['reservation_label'].startswith('Development TEST ') else None
        client = Client(m, p['reservation_label'], account_file=account_file)
        try:
            require(client.user_id == p['id'], 'Wrong owner session')
            path = p['current']['avatar_path']
            if path in objects:
                obj = objects[path]
                require(obj['owner_id'] == p['id'] and int(obj['bytes']) == p['bytes'] and obj['mime'] == p['mime'],
                        'Staged avatar metadata differs')
            else:
                upload_status, _ = avatar(client, p, upload=True)
                require(upload_status == 200, 'Avatar upload HTTP ' + str(upload_status))
                obj = dict(name=path, owner_id=p['id'], bytes=p['bytes'], mime=p['mime'], upload_http=upload_status)
                objects[path] = obj
                staging['objects'] = list(objects.values())
                write_json(STAGING, staging)
        finally:
            close_session(client)
        print(json.dumps({'staged': p['current']['display_name'], 'byte_readback': 'pending_profile_attachment'}), flush=True)
    evidence('upload', dict(objects=staging['objects'], profiles_mutated=False,
                           byte_readback='pending_profile_attachment', status='staged'))


def check_profile(row, p):
    require(all(row.get(k) == p['current'][k] for k in ('id', 'display_name', 'handle', 'bio', 'avatar_path')),
            'Profile reader differs from current overlay')


def verify(m):
    client = Client(m, 'Development Alpha')
    by_id = {p['id']: p for p in m['profiles']}
    fixture_ids = {p['id'] for p in m['profiles'] if p['reservation_label'].startswith('Development TEST ')}
    avatar_results = []
    try:
        status, data = client.call('/rest/v1/profiles?select=*&id=in.(' + ','.join(by_id) + ')')
        require(status == 200 and len(json.loads(data)) == 5, 'Profile HTTP read failed')
        for row in json.loads(data):
            check_profile(row, by_id[row['id']])
        status, data = client.call('/rest/v1/game_cards?select=*&user_id=in.(' + ','.join(fixture_ids) + ')')
        expected_cards = [dict(g, player_name=by_id[g['user_id']]['current']['display_name']) for g in m['original_game_cards']]
        card_key = lambda g: (g['user_id'], g['game_id'])
        require(status == 200 and sorted(json.loads(data), key=card_key) == sorted(expected_cards, key=card_key),
                'Live card aliases/progress differ')
        for game in sorted({g['game_id'] for g in m['original_game_cards']}):
            rows = rpc(client, 'discover_community_players', {'target_game_id': game, 'search_query': ''})
            require(fixture_ids <= {r['id'] for r in rows}, 'Community fixture missing')
            for row in rows:
                if row['id'] in by_id:
                    check_profile(row, by_id[row['id']])
        status, data = client.call('/rest/v1/video_posts?select=id,owner_id&status=eq.approved')
        posts = json.loads(data) if status == 200 else []
        require(len(posts) == 10 and all(p['owner_id'] in fixture_ids for p in posts), 'Home publishers changed')
        comment_count = 0
        for post in posts:
            state = rpc(client, 'clip_social_state', {'target_clip_id': post['id']})
            check_profile(state['uploader'], by_id[post['owner_id']])
            rows = rpc(client, 'clip_comments', {'target_clip_id': post['id']})
            require(len(rows) == 2, 'Comment count changed')
            for row in rows:
                check_profile(row['author'], by_id[row['author']['id']])
                comment_count += 1
        for p in m['profiles']:
            status, data = avatar(client, p)
            require(status == 200 and digest(data) == p['sha256'], 'Peer avatar readback failed')
            anonymous, _ = avatar(client, p, anonymous=True)
            public, _ = avatar(client, p, anonymous=True, public=True)
            require(anonymous in (400, 401, 403, 404) and public in (400, 401, 403, 404), 'Avatar exposed anonymously')
            avatar_results.append(dict(id=p['id'], peer_readback_http=status, sha256_verified=True,
                                       anonymous_denied=anonymous, public_url_denied=public))
    finally:
        close_session(client)
    owner_results = []
    for p in m['profiles']:
        if not p['upload_required']:
            continue
        account_file = FIXTURE_ACCESS if p['reservation_label'].startswith('Development TEST ') else None
        owner = Client(m, p['reservation_label'], account_file=account_file)
        try:
            require(owner.user_id == p['id'], 'Wrong avatar owner verification session')
            status, data = avatar(owner, p)
            require(status == 200 and len(data) == p['bytes'] and digest(data) == p['sha256'],
                    'Owner avatar byte readback failed')
            owner_results.append(dict(id=p['id'], owner_readback_http=status, sha256_verified=True))
        finally:
            close_session(owner)
    evidence('verify', dict(profiles_checked=5, game_communities_checked=12, home_publishers_checked=10,
                            game_cards_checked=36, comments_checked=comment_count, avatars=avatar_results,
                            new_avatar_owner_readbacks=owner_results, business_data_mutated=False))


def evidence(action, result):
    result.setdefault('status', 'passed')
    result.update(action=action, project_ref=PROJECT,
                  recorded_at_utc=datetime.now(timezone.utc).isoformat(timespec='seconds'),
                  manifest_sha256=digest(MANIFEST.read_bytes()), native_build_or_run_performed=False)
    write_json(PLAN / ('test-profile-refresh-' + action + '-2026-11-06.json'), result)
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['render', 'upload', 'verify'])
    args = parser.parse_args()
    if args.action == 'render':
        render()
    elif args.action == 'upload':
        upload(load_manifest())
    else:
        verify(load_manifest())
