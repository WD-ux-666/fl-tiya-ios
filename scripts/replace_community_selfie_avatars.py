#!/usr/bin/env python3
"""Stage and verify exactly 36 private community-avatar replacements.

Uploads use existing owner sessions and fresh immutable names. This utility never
attaches an avatar, changes a profile, executes SQL, or retries an upload. A
separate reviewed transaction must attach all staged objects before verification.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
from urllib.parse import urlsplit
import uuid

from expand_development_communities import owner, profile
from import_development_clips import ROOT
from transfer_development_clip_publishers import Client, close_session, request, rpc

PROJECT = 'gpstwmffctwqlcakmvgw'
PLAN = ROOT / '.planning/2026-11-03-supabase-backend'
MANIFEST = ROOT / 'supabase/content/development-community-selfies-2026-11-06.json'
ROSTER = ROOT / 'supabase/content/development-community-rosters-2026-11-06.json'
COMMENTS = ROOT / 'supabase/content/development-community-comments-2026-11-06.json'
JOURNAL = PLAN / 'community-selfies-uploads-2026-11-06.json'
EVIDENCE = PLAN / 'community-selfies-http-verify-2026-11-06.json'
MAX_BYTES = 5 * 1024 * 1024
PROFILE_FIELDS = ('id', 'handle', 'display_name', 'bio', 'avatar_path')
DENIED = (400, 401, 403, 404)


class SelfieFailure(RuntimeError):
    """A deliberately safe diagnostic, containing no upstream response data."""


def check(value, message):
    if not value:
        raise SelfieFailure(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def valid_uuid(value):
    return isinstance(value, str) and str(uuid.UUID(value)) == value


def avatar_path(value, uid):
    parts = value.split('/') if isinstance(value, str) else []
    check(len(parts) == 2 and parts[0] == uid, 'Avatar owner path mismatch')
    filename = Path(parts[1])
    check(filename.suffix in ('.jpg', '.jpeg', '.png', '.webp') and valid_uuid(filename.stem),
          'Avatar filename must be a lowercase UUID with an allowed image extension')


def jpeg_dimensions(data):
    check(data[:2] == b'\xff\xd8' and data[-2:] == b'\xff\xd9', 'Expected a complete JPEG file')
    offset = 2
    while offset < len(data) - 2:
        check(data[offset] == 0xff, 'Invalid JPEG marker')
        while offset < len(data) and data[offset] == 0xff:
            offset += 1
        check(offset < len(data), 'Truncated JPEG marker')
        marker = data[offset]
        offset += 1
        check(marker not in (0x00, 0xd8, 0xd9, 0xda), 'JPEG dimensions missing')
        if marker == 0x01 or 0xd0 <= marker <= 0xd7:
            continue
        check(offset + 2 <= len(data), 'Truncated JPEG segment')
        size = struct.unpack('>H', data[offset:offset + 2])[0]
        check(size >= 2 and offset + size <= len(data), 'Invalid JPEG segment size')
        if marker in (0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
                      0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf):
            check(size >= 8 and data[offset + 2] == 8, 'Unsupported JPEG frame')
            height, width = struct.unpack('>HH', data[offset + 3:offset + 7])
            return [width, height]
        offset += size
    raise SelfieFailure('JPEG dimensions missing')


def checked_bytes(data, p):
    check(len(data) == p['bytes'] and sha(data) == p['sha256'],
          'JPEG byte count or SHA256 differs for ' + p['current']['display_name'])
    check(jpeg_dimensions(data) == p['dimensions'] == [128, 128], 'JPEG dimensions differ')


def load():
    raw = MANIFEST.read_bytes()
    m = json.loads(raw)
    check(m['project_ref'] == PROJECT and m['cohort'] == 'development' and m['fictional'] is True,
          'Wrong selfie project/cohort')
    expiry = datetime.fromisoformat(m['expires_at'].replace('Z', '+00:00'))
    check(expiry.tzinfo is not None and expiry > datetime.now(timezone.utc), 'Fixture manifest expired')
    people = m['profiles']
    check(len(people) == 36 and len({p['id'] for p in people}) == 36, 'Expected exactly 36 profile IDs')
    roster_raw = ROSTER.read_bytes()
    check(m['roster_manifest'] == str(ROSTER.relative_to(ROOT))
          and m['roster_manifest_sha256'] == sha(roster_raw), 'Reviewed Phase25 roster changed')
    roster = json.loads(roster_raw)
    check(roster['project_ref'] == PROJECT and roster['cohort'] == 'development' and roster['fictional'] is True,
          'Wrong canonical roster project/cohort')
    check(m['fixture_set'] == roster['fixture_set'] == 'community-expansion-2026-11-06',
          'Wrong community fixture set')
    members = roster['players']
    check(len(members) == 36 and {p['id'] for p in people} == {p['id'] for p in members},
          'Replacement IDs differ from canonical community roster')
    check(Counter(Counter(p['game_id'] for p in members).values()) == Counter({3: 12}),
          'Canonical communities must remain 12 disjoint triples')
    roster_by_id = {p['id']: p for p in members}
    assets, paths, hashes = {}, set(), set()
    for p in people:
        check(valid_uuid(p['id']) and type(p['existing']) is bool, 'Invalid fixture identity')
        check(p['reservation_label'] == roster_by_id[p['id']]['reservation_label']
              and p['existing'] == roster_by_id[p['id']]['existing'], 'Fixture reservation changed')
        before, after = p['original'], p['current']
        check(set(before) == set(after) and set(PROFILE_FIELDS + ('created_at',)) <= set(before),
              'Full profile snapshots required')
        check(before['id'] == after['id'] == p['id'] and before['avatar_path'] != after['avatar_path']
              and {k: v for k, v in before.items() if k != 'avatar_path'}
              == {k: v for k, v in after.items() if k != 'avatar_path'}, 'Only avatar_path may change')
        check(all(after[k] == roster_by_id[p['id']][k] for k in ('handle', 'display_name', 'bio')),
              'Profile text differs from canonical roster')
        check(before['avatar_path'] == roster_by_id[p['id']]['avatar_path'], 'Original roster avatar changed')
        avatar_path(before['avatar_path'], p['id'])
        avatar_path(after['avatar_path'], p['id'])
        check(Path(after['avatar_path']).suffix in ('.jpg', '.jpeg') and after['avatar_path'] not in paths,
              'Replacement path must be a fresh JPEG name')
        paths.add(after['avatar_path'])
        check(p['mime'] == 'image/jpeg' and type(p['bytes']) is int and 0 < p['bytes'] <= MAX_BYTES
              and p['dimensions'] == [128, 128], 'Invalid JPEG metadata')
        check(isinstance(p['sha256'], str) and len(p['sha256']) == 64
              and all(c in '0123456789abcdef' for c in p['sha256']), 'Invalid JPEG SHA256')
        source = Path(p['source'])
        check(not source.is_absolute() and '..' not in source.parts and source.suffix == '.jpg',
              'Source must be a repository-relative JPG')
        resolved = (ROOT / source).resolve(strict=True)
        check(resolved.is_relative_to(ROOT.resolve()) and resolved.is_file()
              and resolved.stat().st_size == p['bytes'], 'Local JPEG source is missing or changed')
        url = urlsplit(p['source_url'])
        check(url.scheme == 'https' and url.hostname and not url.username and not url.password,
              'Source provenance must use an HTTPS URL without credentials')
        data = resolved.read_bytes()
        checked_bytes(data, p)
        check(p['sha256'] not in hashes, 'Duplicate selfie image')
        hashes.add(p['sha256'])
        assets[p['id']] = data
    check(sum(p['existing'] for p in people) == 3, 'Expected three original fixture owners')
    return m, sha(raw), assets, members


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix=path.name + '.', delete=False) as output:
            temporary = Path(output.name)
            json.dump(value, output, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def staged_record(p, state):
    return dict(avatar_path=p['current']['avatar_path'], source=p['source'], bytes=p['bytes'],
                sha256=p['sha256'], mime=p['mime'], dimensions=p['dimensions'], state=state)


def journal(m, digest, *, complete=False):
    value = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else dict(
        project_ref=PROJECT, manifest_sha256=digest, objects={})
    check(value['project_ref'] == PROJECT and value['manifest_sha256'] == digest,
          'Upload journal belongs to a different manifest')
    people = {p['id']: p for p in m['profiles']}
    check(isinstance(value['objects'], dict) and set(value['objects']) <= set(people), 'Unknown staged owner')
    for uid, record in value['objects'].items():
        check(record == staged_record(people[uid], 'uploaded'),
              'Unconfirmed or changed upload for ' + people[uid]['current']['display_name']
              + '; automatic retry refused; inspect the object and journal before resuming')
    if complete:
        check(set(value['objects']) == set(people), 'All 36 confirmed uploads are required')
    return value


def avatar(c, p, *, data=None, anonymous=False, public=False):
    prefix = '' if data is not None else ('public/' if public else 'authenticated/')
    headers = {'apikey': c.key}
    if not anonymous:
        headers['Authorization'] = 'Bearer ' + c.token
    if data is not None:
        headers.update({'Content-Type': p['mime'], 'x-upsert': 'false', 'Cache-Control': 'max-age=0'})
    return request(c.base + '/storage/v1/object/' + prefix + 'avatars/' + p['current']['avatar_path'],
                   headers=headers, data=data, method='POST' if data is not None else 'GET', limit=MAX_BYTES)


def upload(m, digest, assets, _members):
    staged = journal(m, digest)
    for p in m['profiles']:
        name = p['current']['display_name']
        if p['id'] in staged['objects']:
            # journal() already requires an exact confirmed immutable upload.
            # The attachment SQL rechecks live owners/metadata/full profiles;
            # final verification reads every owner, including resumed entries.
            print(json.dumps(dict(player=name, confirmed_upload_retained=True)), flush=True)
            continue
        try:
            with owner(m, p) as c:
                actual = profile(c)
                check(actual in (p['original'], p['current']), 'Owner profile changed independently for ' + name)
                if p['id'] not in staged['objects']:
                    check(actual == p['original'], 'Attached avatar lacks a confirmed staging record for ' + name)
                    # Persist intent BEFORE the POST. An interrupted or uncertain write
                    # therefore blocks another upload attempt, including on a later run.
                    staged['objects'][p['id']] = staged_record(p, 'attempting')
                    atomic_json(JOURNAL, staged)
                    status, _ = avatar(c, p, data=assets[p['id']])
                    check(status == 200, 'Upload unconfirmed for ' + name + ': HTTP ' + str(status)
                          + '; no retry performed; inspect the object and journal before resuming')
                    staged['objects'][p['id']] = staged_record(p, 'uploaded')
                    atomic_json(JOURNAL, staged)
        except SelfieFailure:
            raise
        except Exception:
            raise SelfieFailure('Upload/session step failed for ' + name
                               + '; no upload retry performed; inspect the journal before resuming') from None
        print(json.dumps(dict(player=name, immutable_upload_confirmed=True,
                              byte_readback='pending_profile_attachment')), flush=True)
    print(json.dumps(dict(status='staged', objects=36, profiles_mutated=False,
                          byte_readback='pending_profile_attachment')), flush=True)


def current_profile(row, p):
    check(isinstance(row, dict) and all(row.get(k) == p['current'][k] for k in PROFILE_FIELDS),
          'Current profile reader differs for ' + p['current']['display_name'])


def comment_manifest(people):
    raw = COMMENTS.read_bytes()
    cm = json.loads(raw)
    check(cm['project_ref'] == PROJECT and cm['cohort'] == 'development' and cm['fictional'] is True,
          'Wrong Phase25 comments manifest')
    posts, comments = cm['expected_posts'], cm['original_comments'] + cm['comments']
    check(len(posts) == 10 and len({p['id'] for p in posts}) == 10
          and len(cm['original_comments']) == 20 and len(cm['comments']) == 40
          and len({c['id'] for c in comments}) == 60, 'Unexpected Phase25 post/comment scope')
    check(all(p['owner_id'] in people and p['status'] == 'approved' for p in posts), 'Unknown clip publisher')
    check(all(c['clip_id'] in {p['id'] for p in posts} and c['author_id'] in people for c in comments),
          'Unknown expected comment or author')
    for p in posts:
        entries = [c for c in comments if c['clip_id'] == p['id']]
        check(len(entries) == 6 and len({c['author_id'] for c in entries}) == 6,
              'Each clip must retain six distinct fixture commenters')
    return cm, sha(raw), comments


def verify(m, digest, _assets, members):
    journal(m, digest, complete=True)
    people = {p['id']: p for p in m['profiles']}
    cm, comment_digest, comments = comment_manifest(people)
    result = dict(status='passed', project_ref=PROJECT, manifest_sha256=digest,
                  phase25_comments_manifest_sha256=comment_digest, owners=[], avatars=[], communities=[], clips=[])
    def check_owner(p):
        try:
            with owner(m, p) as c:
                check(profile(c) == p['current'], 'Owner full profile differs for ' + p['current']['display_name'])
                status, data = avatar(c, p)
                check(status == 200, 'Owner avatar HTTP ' + str(status) + ' for ' + p['current']['display_name'])
                checked_bytes(data, p)
        except SelfieFailure:
            raise
        except Exception:
            raise SelfieFailure('Owner verification/session failed for ' + p['current']['display_name']) from None
        print(json.dumps(dict(player=p['current']['display_name'], owner_profile_and_jpeg_verified=True)), flush=True)
        return dict(id=p['id'], owner_http=status, sha256=p['sha256'], full_profile_matches=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        result['owners'] = list(pool.map(check_owner, m['profiles']))
    c = Client(m, 'Development Alpha')
    try:
        def peer(p):
            status, data = avatar(c, p)
            check(status == 200, 'Peer avatar HTTP ' + str(status) + ' for ' + p['current']['display_name'])
            checked_bytes(data, p)
            anonymous, _ = avatar(c, p, anonymous=True)
            public, _ = avatar(c, p, anonymous=True, public=True)
            check(anonymous in DENIED and public in DENIED, 'Avatar privacy failed for ' + p['current']['display_name'])
            return dict(id=p['id'], sha256=p['sha256'], peer_http=status,
                        anonymous_http=anonymous, public_http=public)
        with ThreadPoolExecutor(max_workers=4) as pool:
            result['avatars'] = list(pool.map(peer, m['profiles']))
        found = set()
        for game in sorted({p['game_id'] for p in members}):
            expected = {p['id'] for p in members if p['game_id'] == game}
            rows = rpc(c, 'discover_community_players', dict(target_game_id=game, search_query=''))
            ids = {row['id'] for row in rows}
            check(len(ids) == len(rows) and ids & set(people) == expected and not found & expected,
                  'Community fixtures missing or shared: ' + game)
            for row in rows:
                if row['id'] in expected:
                    current_profile(row, people[row['id']])
            found |= expected
            result['communities'].append(dict(game_id=game, fixture_members=sorted(expected)))
        check(found == set(people), 'Expected 36 distinct community members')
        status, payload = c.call('/rest/v1/video_posts?select=*&status=eq.approved&order=created_at.desc,id.desc')
        expected_posts = sorted(cm['expected_posts'], key=lambda p: (p['created_at'], p['id']), reverse=True)
        check(status == 200 and json.loads(payload) == expected_posts, 'Home media/order metadata changed')
        for post in expected_posts:
            social = rpc(c, 'clip_social_state', dict(target_clip_id=post['id']))
            current_profile(social.get('uploader'), people[post['owner_id']])
            rows = rpc(c, 'clip_comments', dict(target_clip_id=post['id']))
            by_id = {row['id']: row for row in rows}
            check(len(by_id) == len(rows), 'Duplicate returned comment IDs')
            for expected in [entry for entry in comments if entry['clip_id'] == post['id']]:
                actual = by_id.get(expected['id'])
                check(actual and actual.get('clip_id') == expected['clip_id']
                      and actual.get('body') == expected['body'] and actual.get('status') == 'approved',
                      'Expected approved comment changed')
                if 'created_at' in expected:
                    check(actual.get('created_at') == expected['created_at'], 'Original comment timestamp changed')
                current_profile(actual.get('author'), people[expected['author_id']])
            check(social['comment_count'] >= 6, 'Visible fixture comment count decreased')
            result['clips'].append(dict(id=post['id'], publisher_id=post['owner_id'],
                                        uploader_avatar_matches=True, fixture_comment_authors_checked=6,
                                        visible_comment_count=social['comment_count']))
    finally:
        close_session(c)
    result.update(recorded_at_utc=datetime.now(timezone.utc).isoformat(timespec='seconds'),
                  profiles_checked=36, owner_jpeg_hashes_checked=36, peer_jpeg_hashes_checked=36,
                  anonymous_public_denials=72, communities_checked=12, uploader_profiles_checked=10,
                  fixture_comment_authors_checked=60, home_media_metadata_preserved=True,
                  social_business_data_mutated=False, native_build_or_run_performed=False)
    atomic_json(EVIDENCE, result)
    print(json.dumps(dict(status='passed', owners=36, peers=36, anonymous_public_denials=72,
                          communities=12, uploaders=10, fixture_comments=60)), flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['upload', 'verify'])
    args = parser.parse_args()
    try:
        check(not (ROOT / 'supabase/content/development-lifestyle-avatars-2026-11-09.json').exists(),
              'Historical selfie batch; use replace_development_lifestyle_avatars.py for current avatars')
        inputs = load()  # All 36 local files are validated before any session is opened.
        {'upload': upload, 'verify': verify}[args.action](*inputs)
    except Exception as error:
        print(json.dumps(dict(status='failed', action=args.action, error_type=type(error).__name__,
                              detail=str(error) if isinstance(error, SelfieFailure)
                              else 'Local data or transport failure; no raw upstream data logged')), flush=True)
        raise SystemExit(1)
