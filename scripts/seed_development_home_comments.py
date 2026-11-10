#!/usr/bin/env python3
"""Exact twenty fictional TEST comments, normal fixture JWT submissions only.

render is local and inert. submit requires --reviewed after manifest review.
Approval/cleanup SQL execution is a separate trusted administrative action.
No new accounts, privileged tokens, policy changes or native app work.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import uuid

from transfer_development_clip_publishers import (
    Client, FIXTURE_ACCESS, ROOT, close_session, require, rpc,
)

MANIFEST = ROOT / 'supabase/content/development-home-fixture-comments-2026-11-06.json'
PLAN = ROOT / '.planning/2026-11-03-supabase-backend'
PROJECT = 'gpstwmffctwqlcakmvgw'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest():
    require(not (ROOT / 'supabase/content/development-community-comments-2026-11-06.json').exists(),
            'Historical twenty-comment utility superseded by expand_development_communities.py')
    m = json.loads(MANIFEST.read_text())
    require(m['project_ref'] == PROJECT and m['cohort'] == 'development', 'Wrong project/cohort')
    transfer_path = ROOT / m['transfer_manifest']
    require(sha(transfer_path) == m['transfer_manifest_sha256'], 'Reviewed publisher manifest changed')
    transfer = json.loads(transfer_path.read_text())
    require(len(m['expected_posts']) == 10 and len(m['comments']) == 20, 'Wrong exact scope')
    fixtures = {f['id']: f for f in m['fixtures']}
    require(len(fixtures) == 3 and all(f['display_name'].startswith('[TEST] ') for f in fixtures.values()),
            'Authors must remain clearly labeled fictional TEST fixtures')
    expected_posts = []
    for p in transfer['posts']:
        expected_posts.append(dict(p['original'], owner_id=p['target_owner_id'],
                                   video_path=p['target_video_path'], thumbnail_path=p['target_thumbnail_path']))
    require(m['expected_posts'] == expected_posts, 'Expected ten post snapshots changed')
    posts = {p['id']: p for p in expected_posts}
    require(len(posts) == 10 and len({c['id'] for c in m['comments']}) == 20, 'Duplicate IDs')
    grouped = defaultdict(list)
    for c in m['comments']:
        require(c['clip_id'] in posts and c['author_id'] in fixtures, 'Unknown target/author')
        require(c['publisher_id'] == posts[c['clip_id']]['owner_id'] != c['author_id'], 'Self/false publisher comment')
        require(c['author_label'] == fixtures[c['author_id']]['label'] and
                c['author_display_name'] == fixtures[c['author_id']]['display_name'], 'False author label')
        require(c['body'] == c['body'].strip() and 1 <= len(c['body']) <= 1000, 'Invalid comment text')
        computed = uuid.uuid5(uuid.UUID(m['comment_id_namespace']),
                              'fl-tiya:home-comment:2026-11-06:' + c['clip_id'] + ':' + c['author_id'])
        require(str(computed) == c['id'], 'Comment UUID drift')
        grouped[c['clip_id']].append(c)
    require(set(grouped) == set(posts), 'Missing clip comments')
    for clip, comments in grouped.items():
        require(len(comments) == 2 and {c['author_id'] for c in comments} == set(fixtures) - {posts[clip]['owner_id']},
                'Each clip needs exactly two OTHER fixture authors')
    return m


def protected_sql():
    # Keep full records inside this administrative transaction; never print
    # private comments or Auth/session data into client logs/evidence.
    return """select jsonb_build_object(
 'posts',(select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]'::jsonb) from public.video_posts v),
 'other_comments',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]'::jsonb) from private.clip_comments c where c.id not in(select id from expected_comments)),
 'likes',(select coalesce(jsonb_agg(to_jsonb(l) order by clip_id,user_id),'[]'::jsonb) from private.clip_likes l),
 'follows',(select coalesce(jsonb_agg(to_jsonb(f) order by follower_id,followed_id),'[]'::jsonb) from private.player_follows f),
 'friend_requests',(select coalesce(jsonb_agg(to_jsonb(r) order by id),'[]'::jsonb) from public.friend_requests r),
 'friendships',(select coalesce(jsonb_agg(to_jsonb(f) order by user_low,user_high),'[]'::jsonb) from public.friendships f)
)"""


def render(m):
    comments = [{k: c[k] for k in ('id', 'clip_id', 'author_id', 'body')} for c in m['comments']]
    compact = lambda value: json.dumps(value, ensure_ascii=False, separators=(',', ':'))
    payload, posts, fixtures = compact(comments), compact(m['expected_posts']), compact(m['fixtures'])
    require(all('$fixture$' not in s for s in (payload, posts, fixtures)), 'Unsafe SQL delimiter')
    common = "-- Prepared exact-scope SQL; review manifest before execution. No schema/policy changes.\nbegin;\nset local lock_timeout='5s';\nset local statement_timeout='20s';\n"
    common += 'create temporary table expected_comments on commit drop as select * from jsonb_to_recordset($fixture$' + payload + '$fixture$::jsonb) as e(id uuid,clip_id uuid,author_id uuid,body text);\n'
    common += 'create temporary table expected_posts on commit drop as select value as snapshot from jsonb_array_elements($fixture$' + posts + '$fixture$::jsonb);\n'
    common += 'create temporary table expected_fixtures on commit drop as select * from jsonb_to_recordset($fixture$' + fixtures + '$fixture$::jsonb) as f(id uuid,label text,display_name text);\n'
    common += "select v.id from public.video_posts v join expected_posts e on v.id=(e.snapshot->>'id')::uuid order by v.id for share of v;\n"
    common += "select p.id from public.profiles p join expected_fixtures f on f.id=p.id order by p.id for share of p;\n"
    common += "select c.id from private.clip_comments c join expected_comments e on e.id=c.id order by c.id for update of c;\n"
    common += """do $guard$ begin
 if (select count(*) from expected_comments)<>20 or (select count(distinct id) from expected_comments)<>20
  or (select count(*) from expected_posts)<>10 or (select count(*) from expected_fixtures)<>3 then raise exception 'Wrong reviewed scope';end if;
 if (select count(*) from public.video_posts where status='approved')<>10
  or (select count(*) from public.video_posts v join expected_posts e on to_jsonb(v)=e.snapshot)<>10 then raise exception 'Home post snapshot changed';end if;
 if (select count(*) from public.profiles p join expected_fixtures f on p.id=f.id and p.display_name=f.display_name
   join private.development_accounts d on d.user_id=p.id and d.label=f.label
   join private.accounts a on a.user_id=p.id where a.cohort='development' and a.state='active' and private.account_is_eligible(p.id))<>3 then raise exception 'TEST author scope or eligibility changed';end if;
 if exists(select 1 from private.clip_comments c join expected_comments e on c.id=e.id
  where c.clip_id<>e.clip_id or c.author_id<>e.author_id or c.body<>e.body or c.status not in ('pending','approved')
   or (c.status='pending' and c.approved_at is not null) or (c.status='approved' and c.approved_at is null)) then raise exception 'Comment UUID/body/author/clip/status conflict';end if;
end $guard$;
"""
    common += 'create temporary table protected_before on commit drop as ' + protected_sql() + ' as snapshot;\n'
    unchanged = "do $preserve$ begin if (select snapshot from protected_before) is distinct from (" + protected_sql() + ") then raise exception 'Protected existing data changed';end if;end $preserve$;\n"
    approval = common + """do $ready$ begin if (select count(*) from private.clip_comments c join expected_comments e on c.id=e.id)<>20 then raise exception 'Twenty real JWT submissions required before approval';end if;end $ready$;
update private.clip_comments c set status='approved',approved_at=statement_timestamp()
 from expected_comments e where c.id=e.id and c.status='pending';
do $approved$ begin if (select count(*) from private.clip_comments c join expected_comments e on c.id=e.id
 where c.clip_id=e.clip_id and c.author_id=e.author_id and c.body=e.body and c.status='approved' and c.approved_at is not null)<>20 then raise exception 'Expected twenty exact approved comments';end if;end $approved$;
""" + unchanged + "commit;\n"
    cleanup = common + """delete from private.clip_comments c using expected_comments e
 where c.id=e.id and c.clip_id=e.clip_id and c.author_id=e.author_id and c.body=e.body and c.status in ('pending','approved');
do $clean$ begin if exists(select 1 from private.clip_comments c join expected_comments e on c.id=e.id) then raise exception 'Exact cleanup incomplete';end if;end $clean$;
""" + unchanged + "commit;\n"
    prefix = MANIFEST.with_suffix('')
    for suffix, sql in [('approve', approval), ('approve-rollback', approval.replace('commit;\n', 'rollback;\n')),
                        ('cleanup', cleanup), ('cleanup-rollback', cleanup.replace('commit;\n', 'rollback;\n'))]:
        Path(str(prefix) + '-' + suffix + '.sql').write_text(sql)
    write_evidence('prepared', {'status': 'prepared_for_root_review', 'committed_comment_submissions': 0,
                                'comments': 20, 'clips': 10, 'schema_or_policy_changes': False})


def check_comment(actual, expected, statuses):
    require(actual['id'] == expected['id'] and actual['clip_id'] == expected['clip_id'] and
            actual['author']['id'] == expected['author_id'] and actual['body'] == expected['body'] and
            actual['status'] in statuses, 'Comment response differs from reviewed exact scope')
    require(actual['author']['display_name'] == expected['author_display_name'], 'Author TEST label changed')


def verify_posts(client, m):
    status, payload = client.call('/rest/v1/video_posts?select=*&status=eq.approved&order=created_at.desc,id.desc')
    require(status == 200, 'Home metadata HTTP ' + str(status))
    actual = json.loads(payload)
    expected = sorted(m['expected_posts'], key=lambda p: (p['created_at'], p['id']), reverse=True)
    require(actual == expected, 'Home ownership/order/content changed')


def submit(m):
    clients = {}
    returned = []
    try:
        for c in m['comments']:
            if c['author_id'] not in clients:
                client = Client(m, c['author_label'], account_file=FIXTURE_ACCESS)
                clients[c['author_id']] = client
                require(client.user_id == c['author_id'], 'Wrong fixture session')
                verify_posts(client, m)
            actual = rpc(clients[c['author_id']], 'add_clip_comment',
                         {'target_clip_id': c['clip_id'], 'comment_id': c['id'], 'comment_body': c['body']})
            check_comment(actual, c, {'pending', 'approved'})
            returned.append(actual['status'])
            print(json.dumps({'comment_id': c['id'], 'clip_id': c['clip_id'],
                              'author': c['author_display_name'], 'status': actual['status']}), flush=True)
    finally:
        for client in clients.values():
            close_session(client)
    write_evidence('submit', {'status': 'passed', 'normal_jwt_rpc_submissions': len(returned),
                              'response_statuses': dict(Counter(returned)), 'deterministic_uuid_retries_safe': True})


def verify(m, approved):
    clients = {}
    try:
        if not approved:
            for c in m['comments']:
                if c['author_id'] not in clients:
                    client = Client(m, c['author_label'], account_file=FIXTURE_ACCESS)
                    clients[c['author_id']] = client
                    require(client.user_id == c['author_id'], 'Wrong fixture session')
                rows = rpc(clients[c['author_id']], 'clip_comments', {'target_clip_id': c['clip_id']})
                found = next((r for r in rows if r['id'] == c['id']), None)
                require(found is not None, 'Own pending comment missing')
                check_comment(found, c, {'pending'})
        alpha = Client(m, 'Development Alpha')
        clients['alpha'] = alpha
        verify_posts(alpha, m)
        expected_ids = {c['id'] for c in m['comments']}
        for p in m['expected_posts']:
            rows = rpc(alpha, 'clip_comments', {'target_clip_id': p['id']})
            by_id = {r['id']: r for r in rows}
            expected = [c for c in m['comments'] if c['clip_id'] == p['id']]
            if approved:
                for c in expected:
                    require(c['id'] in by_id, 'Approved comment not visible to Alpha')
                    check_comment(by_id[c['id']], c, {'approved'})
                state = rpc(alpha, 'clip_social_state', {'target_clip_id': p['id']})
                require(state['comment_count'] >= 2, 'Approved count does not reflect actual comments')
            else:
                require(not set(by_id) & expected_ids, 'Pending fixture comment exposed to Alpha')
    finally:
        for client in clients.values():
            close_session(client)
    write_evidence('verify-approved' if approved else 'verify-pending',
                   {'status': 'passed', 'comments_checked': 20, 'clips_checked': 10,
                    'alpha_visibility': 'all twenty approved comments visible' if approved else 'pending comments hidden',
                    'business_data_mutated': False})


def write_evidence(action, result):
    payload = dict(result, action=action, recorded_at_utc=datetime.now(timezone.utc).isoformat(timespec='seconds'),
                   project_ref=PROJECT, manifest=str(MANIFEST.relative_to(ROOT)), manifest_sha256=sha(MANIFEST),
                   script_sha256=sha(Path(__file__)), native_build_or_launch_performed=False)
    (PLAN / ('home-fixture-comments-' + action + '-2026-11-06.json')).write_text(json.dumps(payload, indent=2) + '\n')
    print(json.dumps(payload), flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['render', 'submit', 'verify-pending', 'verify-approved'])
    parser.add_argument('--reviewed', action='store_true', help='Manifest has received the requested root review')
    args = parser.parse_args()
    try:
        manifest = load_manifest()
        require(args.action != 'submit' or args.reviewed, 'Review the manifest before committed submissions')
        if args.action == 'render':
            render(manifest)
        elif args.action == 'submit':
            submit(manifest)
        else:
            verify(manifest, args.action == 'verify-approved')
    except Exception as error:
        print(json.dumps({'status': 'failed', 'action': args.action, 'error_type': type(error).__name__,
                          'detail': str(error) if isinstance(error, RuntimeError) else 'Transport or local data failure'}), flush=True)
        raise SystemExit(1)
