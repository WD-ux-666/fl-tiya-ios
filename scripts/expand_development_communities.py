#!/usr/bin/env python3
"""Provision exact, disjoint development rosters using genuine owner sessions.

No schema/RLS changes or service credentials. Reservation SQL stays private.
Historical fixture/account IDs and preexisting social/content state are retained.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import secrets
import struct

from import_development_clips import ROOT, PRIVATE
from transfer_development_clip_publishers import Client, FIXTURE_ACCESS, close_session, request, require, rpc

PROJECT = 'gpstwmffctwqlcakmvgw'
PLAN = ROOT / '.planning/2026-11-03-supabase-backend'
MANIFEST = ROOT / 'supabase/content/development-community-rosters-2026-11-06.json'
COMMENTS = ROOT / 'supabase/content/development-community-comments-2026-11-06.json'
ACCESS = PRIVATE / 'community-expanded-access-2026-11-06.json'
RESERVATIONS = PRIVATE / 'community-expanded-reservations-2026-11-06.sql'
JOURNAL = PLAN / 'community-expansion-uploads-2026-11-06.json'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, data, private=False):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700 if private else 0o755)
    path.write_text(json.dumps(data, indent=2) + '\n')
    if private:
        path.chmod(0o600)


def load():
    m = json.loads(MANIFEST.read_text())
    require(m['project_ref'] == PROJECT and m['cohort'] == 'development' and m['fictional'], 'Wrong fixture project/cohort')
    p = m['players']
    require(len(p) == 36 and len({x['id'] for x in p}) == 36 and len({x['handle'] for x in p}) == 36, 'Unexpected identity scope')
    require(Counter(Counter(x['game_id'] for x in p).values()) == Counter({3: 12}), 'Communities must be disjoint triples')
    require(sum(x['existing'] for x in p) == 3, 'Existing identity count changed')
    return m


@contextmanager
def owner(m, p):
    c = Client(m, p['reservation_label'], account_file=FIXTURE_ACCESS if p['existing'] else ACCESS)
    try:
        require(c.user_id == p['id'], 'Fixture owner mismatch')
        yield c
    finally:
        close_session(c)


def require_historical_write_scope():
    require(not (ROOT / 'supabase/content/development-community-selfies-2026-11-06.json').exists(),
            'Historical community writes superseded by replace_community_selfie_avatars.py')


def prepare(m):
    require_historical_write_scope()
    new = [p for p in m['players'] if not p['existing']]
    if ACCESS.exists():
        a = json.loads(ACCESS.read_text())
        require(a['project_ref'] == PROJECT and a['fixture_set'] == m['fixture_set'], 'Private credential scope changed')
        require({(x['label'], x['user_id']) for x in a['accounts']} == {(p['reservation_label'], p['id']) for p in new}, 'Private identity scope changed')
    else:
        a = dict(project_ref=PROJECT, fixture_set=m['fixture_set'], cohort='development', expires_at=m['expires_at'],
                 accounts=[dict(label=p['reservation_label'], user_id=p['id'], access_code='FLD_' + secrets.token_urlsafe(32)) for p in new])
        write_json(ACCESS, a, private=True)
    sql = ["begin;", "set local lock_timeout='5s';"]
    for x in a['accounts']:
        uid, label = x['user_id'], x['label']
        require("'" not in label, 'Invalid label')
        email = 'development.' + uid + '@example.invalid'
        digest = sha(x['access_code'].encode())
        sql.append(f"""do $reserve$ begin
 if exists(select 1 from private.development_accounts where user_id='{uid}'::uuid) then
  if not exists(select 1 from private.development_accounts where user_id='{uid}'::uuid
    and email='{email}' and label='{label}' and code_hash='{digest}'
    and enabled and expires_at='{m['expires_at']}'::timestamptz) then raise exception 'reservation_collision';end if;
 elsif exists(select 1 from auth.users where id='{uid}'::uuid or lower(email)='{email}') then
  raise exception 'identity_collision';
 else
  insert into private.development_accounts(user_id,email,label,code_hash,enabled,expires_at)
   values('{uid}'::uuid,'{email}','{label}','{digest}',true,'{m['expires_at']}'::timestamptz);
 end if;
end $reserve$;""")
    sql += ['commit;', "select count(*) as new_reservations from private.development_accounts where user_id in (" + ','.join("'"+p['id']+"'::uuid" for p in new) + ');']
    RESERVATIONS.write_text('\n'.join(sql) + '\n'); RESERVATIONS.chmod(0o600)
    print(json.dumps(dict(private_access_file=str(ACCESS), private_reservation_file=str(RESERVATIONS), accounts=33)))


def profile(c):
    status, data = c.call('/rest/v1/profiles?select=*&id=eq.' + c.user_id)
    rows = json.loads(data) if status == 200 else []
    require(len(rows) == 1, 'Owner profile read failed: HTTP ' + str(status))
    return rows[0]


def portrait(p):
    path = ROOT / p['avatar_source']
    data = path.read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n', 'Expected original PNG')
    width, height = struct.unpack('>II', data[16:24])
    require(0 < len(data) <= 5242880 and 0 < width == height <= 4096, 'Avatar bounds exceeded')
    return data, dict(source=p['avatar_source'], bytes=len(data), sha256=sha(data), dimensions=[width,height], mime='image/png', avatar_path=p['avatar_path'])


def avatar(c, path, *, data=None, anonymous=False, public=False):
    prefix = '' if data is not None else ('public/' if public else 'authenticated/')
    headers = {'apikey': c.key}
    if not anonymous:
        headers['Authorization'] = 'Bearer ' + c.token
    if data is not None:
        headers.update({'Content-Type':'image/png','x-upsert':'false','Cache-Control':'max-age=0'})
    return request(c.base + '/storage/v1/object/' + prefix + 'avatars/' + path, headers=headers,
                   data=data, method='POST' if data is not None else 'GET', limit=5242880)


def provision(m):
    require_historical_write_scope()
    # Validate all image inputs before creating any account.
    assets = {p['id']: portrait(p) for p in m['players'] if not p['existing']}
    digest = sha(MANIFEST.read_bytes())
    journal = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else dict(manifest_sha256=digest, objects={})
    require(journal['manifest_sha256'] == digest, 'Roster changed after upload staging')
    completed = []
    for p in m['players']:
        if p['existing']:
            continue
        data, asset = assets[p['id']]
        with owner(m,p) as c:
            original = profile(c)
            desired = {k:p[k] for k in ('handle','display_name','bio','avatar_path')}
            default = original['handle'] == 'player_' + p['id'].replace('-','') and original['display_name'] == p['reservation_label'] and not original['bio'] and original['avatar_path'] is None
            require(default or all(original[k] == v for k,v in desired.items()), 'New fixture profile changed independently')
            staged = journal['objects'].get(p['id'])
            if staged:
                require(staged == asset, 'Staged portrait changed')
            elif original['avatar_path'] == p['avatar_path']:
                status, received = avatar(c,p['avatar_path'])
                require(status == 200 and sha(received) == asset['sha256'], 'Existing linked avatar changed')
                journal['objects'][p['id']] = asset; write_json(JOURNAL,journal)
            else:
                status,_ = avatar(c,p['avatar_path'],data=data)
                require(status == 200, 'Immutable avatar upload failed for ' + p['display_name'] + ': HTTP ' + str(status))
                journal['objects'][p['id']] = asset; write_json(JOURNAL,journal)
            if default:
                status,_ = c.call('/rest/v1/profiles?id=eq.' + c.user_id,method='PATCH',data=json.dumps(desired).encode())
                require(status in (200,204), 'Owner profile update failed: HTTP ' + str(status))
            actual = profile(c)
            require(all(actual[k] == v for k,v in desired.items()), 'Owner profile readback mismatch')
            # Unlinked objects are intentionally unreadable under existing Storage RLS.
            # Only verify bytes after the owner has attached the avatar to the profile.
            status, received = avatar(c,p['avatar_path'])
            require(status == 200 and sha(received) == asset['sha256'], 'Attached owner avatar readback failed')
            status, payload = c.call('/rest/v1/game_cards?select=*&user_id=eq.' + c.user_id)
            require(status == 200, 'Owner membership read failed')
            expected = dict(user_id=p['id'],game_id=p['game_id'],player_name=p['display_name'],days_played=None,progress='')
            cards = json.loads(payload)
            require(cards in ([],[expected]), 'New fixture game card changed independently')
            if not cards:
                status,_ = c.call('/rest/v1/game_cards',method='POST',data=json.dumps(expected).encode())
                require(status in (200,201,204), 'Owner membership insertion failed')
            status,payload = c.call('/rest/v1/game_cards?select=*&user_id=eq.' + c.user_id)
            require(status == 200 and json.loads(payload) == [expected], 'Owner membership readback mismatch')
            completed.append(p['id'])
            print(json.dumps(dict(player=p['display_name'], game=p['game_id'], owner_avatar_verified=True)),flush=True)
    write_json(PLAN / 'community-expansion-provision-2026-11-06.json',dict(status='passed',new_profiles=len(completed),owner_avatar_hashes_verified=len(completed),ids=completed))


def submit(m):
    require_historical_write_scope()
    comments = json.loads(COMMENTS.read_text())
    by_id = {p['id']:p for p in m['players']}
    group = {}
    for x in comments['comments']:
        group.setdefault(x['author_id'],[]).append(x)
    submitted = []
    for uid, entries in group.items():
        with owner(m,by_id[uid]) as c:
            for e in entries:
                actual = rpc(c,'add_clip_comment',dict(target_clip_id=e['clip_id'],comment_id=e['id'],comment_body=e['body']))
                require(actual['id'] == e['id'] and actual['body'] == e['body'] and actual['author']['id'] == uid
                        and actual['status'] in ('pending','approved'), 'Comment submission mismatch')
                submitted.append(e['id'])
        print(json.dumps(dict(comment_author=by_id[uid]['display_name'], submitted=len(entries))),flush=True)
    write_json(PLAN / 'community-expansion-comments-submit-2026-11-06.json',dict(status='passed',normal_jwt_comments=len(submitted),unique_authors=len(group)))


def verify(m):
    # The immutable Phase25 manifest/journal describe its historical PNGs.
    # Use the current complete avatar overlay instead of reviving stale paths.
    if (ROOT / 'supabase/content/development-lifestyle-avatars-2026-11-09.json').exists():
        from replace_development_lifestyle_avatars import load, verify as verify_current
        return verify_current(*load())
    if (ROOT / 'supabase/content/development-community-selfies-2026-11-06.json').exists():
        from replace_community_selfie_avatars import load, verify as verify_current
        return verify_current(*load())
    c = Client(m,'Development Alpha')
    result = dict(status='passed', communities=[],avatars=[],clips=[])
    try:
        found = set()
        for game in sorted({p['game_id'] for p in m['players']}):
            expected = {p['id']:p for p in m['players'] if p['game_id'] == game}
            rows = rpc(c,'discover_community_players',dict(target_game_id=game,search_query=''))
            ids = {r['id'] for r in rows}
            require(set(expected) <= ids and not (set(expected) & found), 'Community missing or shared fixture')
            all_fixtures = {p['id'] for p in m['players']}
            require(ids & all_fixtures == set(expected), 'Cross-community fixture leakage')
            for r in rows:
                if r['id'] in expected:
                    require(all(r[k] == expected[r['id']][k] for k in ('handle','display_name','bio','avatar_path')), 'Community profile mismatch')
            found |= set(expected)
            result['communities'].append(dict(game_id=game,fixture_members=sorted(expected),visible_total=len(rows)))
        require(len(found) == 36, 'Wrong total distinct members')
        old = json.loads((ROOT / 'supabase/content/development-player-profiles-2026-11-06.json').read_text())
        old_hashes = {p['id']:p['sha256'] for p in old['profiles']}
        assets = json.loads(JOURNAL.read_text())['objects']
        def check(p):
            status,data = avatar(c,p['avatar_path'])
            expected_hash = old_hashes[p['id']] if p['existing'] else assets[p['id']]['sha256']
            require(status == 200 and sha(data) == expected_hash, 'Peer avatar hash mismatch')
            anonymous,_ = avatar(c,p['avatar_path'],anonymous=True)
            public,_ = avatar(c,p['avatar_path'],anonymous=True,public=True)
            require(anonymous in (400,401,403,404) and public in (400,401,403,404), 'Avatar became public')
            return dict(id=p['id'],sha256=expected_hash,peer_http=status,anonymous_http=anonymous,public_http=public)
        with ThreadPoolExecutor(max_workers=4) as pool:
            result['avatars'] = list(pool.map(check,m['players']))
        cm = json.loads(COMMENTS.read_text())
        expected_old = cm['original_comments']
        for p in cm['expected_posts']:
            rows = rpc(c,'clip_comments',dict(target_clip_id=p['id']))
            by_id = {x['id']:x for x in rows}
            expected = [x for x in cm['comments'] + expected_old if x['clip_id'] == p['id']]
            require(len(expected) == 6 and len({x['author_id'] for x in expected}) == 6, 'Expected six distinct commenters')
            for e in expected:
                actual = by_id.get(e['id'])
                require(actual and actual['status'] == 'approved' and actual['body'] == e['body'] and actual['author']['id'] == e['author_id'], 'Approved comment readback mismatch')
                person = next(x for x in m['players'] if x['id'] == e['author_id'])
                require(all(actual['author'][k] == person[k] for k in ('display_name','handle','avatar_path')), 'Comment author profile mismatch')
            social = rpc(c,'clip_social_state',dict(target_clip_id=p['id']))
            require(social['comment_count'] >= 6 and social['uploader']['id'] == p['owner_id'], 'Clip count or publisher changed')
            result['clips'].append(dict(id=p['id'],fixture_comments_checked=6,visible_count=social['comment_count'],publisher_id=social['uploader']['id']))
        status,body = c.call('/rest/v1/video_posts?select=*&status=eq.approved')
        require(status == 200 and sorted(json.loads(body),key=lambda p:p['id']) == sorted(cm['expected_posts'],key=lambda p:p['id']), 'Home media/order metadata changed')
    finally:
        close_session(c)
    result.update(distinct_members=36,new_profiles=33,comments_checked=60,native_build_or_run_performed=False)
    write_json(PLAN / 'community-expansion-http-verify-2026-11-06.json',result)
    print(json.dumps(dict(status='passed',communities=12,unique_members=36,private_avatars=36,fixture_comments=60,clips=10)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','provision','submit-comments','verify'])
    args = parser.parse_args()
    manifest = load()
    {'prepare':prepare,'provision':provision,'submit-comments':submit,'verify':verify}[args.action](manifest)
