#!/usr/bin/env python3
"""Stage and verify the current development avatar batch using normal sessions."""

import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import contextmanager
import json
from pathlib import Path
from threading import Lock

from expand_development_communities import ACCESS, PLAN, profile
from replace_community_selfie_avatars import (
    DENIED, MAX_BYTES, PROJECT, SelfieFailure, atomic_json, avatar, avatar_path,
    check, comment_manifest, current_profile, jpeg_dimensions, sha,
)
from transfer_development_clip_publishers import (
    Client, FIXTURE_ACCESS, ROOT, close_session, rpc,
)

CONTENT = ROOT / 'supabase/content'
LIFESTYLE = CONTENT / 'development-lifestyle-avatars-2026-11-09.json'
SCENIC = CONTENT / 'development-scenic-avatars-2026-11-09.json'
MANIFEST = SCENIC if SCENIC.is_file() else LIFESTYLE
BATCH = 'scenic' if MANIFEST == SCENIC else 'lifestyle'
JOURNAL = PLAN / f'development-{BATCH}-avatar-uploads-2026-11-09.json'
EVIDENCE = PLAN / f'development-{BATCH}-avatar-http-2026-11-09.json'


def read_json(path):
    return json.loads(path.read_bytes())


def load():
    m = read_json(MANIFEST)
    check(m['project_ref'] == PROJECT and m['cohort'] == 'development' and m['fictional'] is True,
          'Invalid project/cohort')
    members = read_json(CONTENT / 'development-community-rosters-2026-11-06.json')['players']
    known = {p['id']: (p['reservation_label'], 'community-original' if p['existing']
                      else 'community-expanded') for p in members}
    baseline = read_json(CONTENT / 'development-player-profiles-2026-11-06.json')['profiles']
    known.update({p['id']: (p['reservation_label'], 'alpha-beta') for p in baseline
                  if p['reservation_label'] in ('Development Alpha', 'Development Beta')})
    people = {p['id']: p for p in m['profiles']}
    check(len(people) == len(m['profiles']) == 38 and set(people) == set(known), 'Invalid account scope')
    previous = {p['id']: p for p in read_json(LIFESTYLE)['profiles']} if MANIFEST == SCENIC else {}
    changed = {uid for uid, p in people.items() if p['original'] != p['current']}
    if previous:
        check(len(changed) == 30 and all(known[uid][1] != 'alpha-beta' for uid in changed),
              'Scenic batch must change exactly 30 community avatars')
    else:
        check(len(changed) == 38, 'Lifestyle batch must change all 38 avatars')
    assets = {}
    for uid, p in people.items():
        check(known[uid] == (p['label'], p['account']), 'Fixture reservation differs')
        before, after = p['original'], p['current']
        check(before['id'] == uid and {**before, 'avatar_path': after['avatar_path']} == after,
              'Non-avatar profile change')
        if previous:
            old = previous[uid]
            check(before == old['current'], 'Unexpected scenic batch baseline')
            if uid not in changed:
                check(all(p[key] == old[key] for key in ('source', 'sha256', 'bytes', 'mime', 'dimensions')),
                      'Retained portrait differs')
        avatar_path(after['avatar_path'], uid)
        source = (ROOT / p['source']).resolve(strict=True)
        folder = BATCH if uid in changed else 'lifestyle'
        check(source.parent == ROOT / f'docs/assets/development-{folder}-avatars', 'Invalid source path')
        data = source.read_bytes()
        check(0 < len(data) == p['bytes'] <= MAX_BYTES and p['mime'] == 'image/jpeg'
              and sha(data) == p['sha256'] and jpeg_dimensions(data) == p['dimensions'] == [256, 256],
              'Invalid avatar image')
        assets[uid] = data
    check(len({sha(d) for d in assets.values()}) == 38, 'Duplicate avatar')
    return m, people, members, assets


@contextmanager
def owner(m, p):
    access = {'community-original': FIXTURE_ACCESS, 'community-expanded': ACCESS, 'alpha-beta': None}
    c = Client(m, p['label'], account_file=access[p['account']])
    try:
        check(c.user_id == p['id'], 'Wrong fixture session')
        yield c
    finally:
        close_session(c)


def upload(m, people, members, assets):
    people = {uid: p for uid, p in people.items() if p['original'] != p['current']}
    digest = sha(MANIFEST.read_bytes())
    journal = read_json(JOURNAL) if JOURNAL.exists() else {'manifest_sha256': digest, 'objects': {}}
    check(journal['manifest_sha256'] == digest and set(journal['objects']) <= set(people),
          'Unrelated upload journal')
    for uid, record in journal['objects'].items():
        check(record == {'state': 'uploaded', 'path': people[uid]['current']['avatar_path']},
              'Unconfirmed upload for ' + people[uid]['name'] + '; reconcile Storage before retrying')
    lock = Lock()

    def save(uid, path, state):
        with lock:
            journal['objects'][uid] = {'state': state, 'path': path}
            atomic_json(JOURNAL, journal)

    def stage(p):
        uid = p['id']
        if uid in journal['objects']:
            return
        with owner(m, p) as c:
            check(profile(c) == p['original'], 'Profile snapshot changed')
            path = p['current']['avatar_path']
            save(uid, path, 'attempting')
            status, _ = avatar(c, p, data=assets[uid])
            check(status == 200, 'Avatar upload HTTP ' + str(status))
            save(uid, path, 'uploaded')

    with ThreadPoolExecutor(max_workers=4) as pool:
        tasks = {pool.submit(stage, p): p['name'] for p in people.values()}
        failures = 0
        for task in as_completed(tasks):
            try:
                task.result()
            except Exception as error:
                failures += 1
                detail = str(error) if isinstance(error, SelfieFailure) else type(error).__name__
                print(tasks[task] + ': ' + detail, flush=True)
    print(json.dumps({'staged': sum(x['state'] == 'uploaded' for x in journal['objects'].values()),
                      'session_failures': failures}), flush=True)
    check(not failures, 'One or more fixture sessions need reconciliation')


def verify(m, people, members, assets):
    comments, _, all_comments = comment_manifest(people)
    comments_by_clip, by_game = defaultdict(list), defaultdict(list)
    for row in all_comments:
        comments_by_clip[row['clip_id']].append(row)
    for row in members:
        by_game[row['game_id']].append(row['id'])
    alpha = next(p for p in people.values() if p['label'] == 'Development Alpha')
    with owner(m, alpha) as c, ThreadPoolExecutor(max_workers=5) as pool:
        check(profile(c) == alpha['current'], 'Alpha profile differs')

        def read_avatar(p):
            status, data = avatar(c, p)
            check(status == 200 and data == assets[p['id']], 'Avatar readback differs for ' + p['name'])
            return {'id': p['id'], 'sha256': sha(data)}

        avatars = list(pool.map(read_avatar, people.values()))
        for p in (alpha, people[comments['expected_posts'][0]['owner_id']]):
            check(avatar(c, p, anonymous=True)[0] in DENIED and
                  avatar(c, p, anonymous=True, public=True)[0] in DENIED, 'Avatar privacy changed')

        def read_community(game):
            rows = rpc(c, 'discover_community_players', {'target_game_id': game, 'search_query': ''})
            entries = {r['id']: r for r in rows}
            for uid in by_game[game]:
                current_profile(entries.get(uid), people[uid])
            return game

        games = list(pool.map(read_community, by_game))

        def read_clip(post):
            args = {'target_clip_id': post['id']}
            social = rpc(c, 'clip_social_state', args)
            current_profile(social.get('uploader'), people[post['owner_id']])
            rows = {r['id']: r for r in rpc(c, 'clip_comments', args)}
            for expected in comments_by_clip[post['id']]:
                current_profile(rows.get(expected['id'], {}).get('author'), people[expected['author_id']])
            return {'id': post['id'], 'likes': social['like_count'],
                    'comment_authors': len(comments_by_clip[post['id']])}

        clips = list(pool.map(read_clip, comments['expected_posts']))
    atomic_json(EVIDENCE, {'avatars': avatars, 'communities': games, 'clips': clips,
                           'anonymous_denials': 4, 'manifest_sha256': sha(MANIFEST.read_bytes())})
    print(json.dumps({'avatars': len(avatars), 'communities': len(games), 'clips': len(clips),
                      'comments': sum(p['comment_authors'] for p in clips),
                      'likes_visible': sum(p['likes'] for p in clips)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['upload', 'verify'])
    args = parser.parse_args()
    try:
        {'upload': upload, 'verify': verify}[args.action](*load())
    except Exception as error:
        print(str(error) if isinstance(error, SelfieFailure) else type(error).__name__, flush=True)
        raise SystemExit(1)
