#!/usr/bin/env python3
"""Import the seven frozen development seed clips after root content review.

Run pending.sql first, then upload and verify-pending. Run approve.sql only after
the separate root review, followed by verify-approved. No approval is automatic.
Reuses the existing session-scoped client; never uses an admin/service key.
"""
import argparse
import json
from pathlib import Path
import stat
import sys
import uuid

sys.dont_write_bytecode = True
from import_development_clips import Client, digest, request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'supabase/content/development-seed-clips-2026-11-04.json'
CACHE = Path('/Users/shangbao666/.codex/private/fl-tiya-ios/seed-clips-2026-11-04')
PROJECT = 'gpstwmffctwqlcakmvgw'
BASE = 'https://' + PROJECT + '.supabase.co'
OWNER = '0a8b2ca1-9e56-4843-828c-07f560fabd2a'
EXPECTED = {
    '0266cd87-d7a3-53a6-8a08-6f454c48a6a5': 'supertuxkart',
    'df55c5a2-7441-54fa-acd8-8429d331bda9': 'freedoom',
    'efaae809-9e62-5ddb-96bc-eebbe47e2747': 'bobs-game',
    '6920e768-4d0a-5af1-a003-10ea2eeca518': 'guacamelee',
    '89630fe1-6fbe-5d05-aafe-6b29afb38fb5': 'manifold-garden',
    '28a87f34-378d-5c97-9e64-b608349a53a4': 'fantastic-contraption',
    'bb5f6920-3801-5d4c-8f6e-14c87bcbcbb8': 'push-me-pull-you',
}
DENIED = (400, 401, 403, 404)
MAX_BYTES = 32 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_local(path, size, checksum, limit):
    require(not path.is_symlink() and path.is_file(), 'Expected a regular cached file')
    require(stat.S_IMODE(path.stat().st_mode) == 0o600, 'Cached file permission mismatch')
    require(0 < size <= limit and path.stat().st_size == size, 'Cached file byte count mismatch')
    data = path.read_bytes()
    require(len(data) == size and digest(data) == checksum, 'Cached file SHA-256 mismatch')
    return data


def preflight():
    """Validate the full frozen manifest and all 21 files before creating Client."""
    raw = MANIFEST.read_bytes()
    manifest = json.loads(raw)
    require(manifest['project_ref'] == PROJECT and manifest['cohort'] == 'development', 'Import scope mismatch')
    clips = manifest['clips']
    require(len(clips) == 7 and {c['id']: c['game_id'] for c in clips} == EXPECTED, 'Seed registry mismatch')
    require(not CACHE.is_symlink() and stat.S_IMODE(CACHE.stat().st_mode) == 0o700, 'Cache directory permission mismatch')
    uploads = {}
    paths = set()
    for clip in clips:
        post_id = clip['id']
        require(str(uuid.UUID(post_id)) == post_id and clip['owner_id'] == OWNER, 'Seed owner or UUID mismatch')
        require(len(clip['caption']) <= 500 and clip['caption'].isascii(), 'Caption scope mismatch')
        folder = CACHE / post_id
        require(str(folder) == clip['local_cache_directory'] and not folder.is_symlink(), 'Cache path mismatch')
        require(stat.S_IMODE(folder.stat().st_mode) == 0o700, 'Post cache permission mismatch')
        read_local(folder / 'source.mov', clip['source_download_bytes'], clip['source_sha256'], MAX_BYTES)
        for name, field, size_key, hash_key, mime, limit in (
                ('video.mp4', 'video_path', 'media_bytes', 'media_sha256', 'video/mp4', MAX_BYTES),
                ('cover.png', 'thumbnail_path', 'thumbnail_bytes', 'thumbnail_sha256', 'image/png', 2 * 1024 * 1024)):
            storage_path = OWNER + '/' + post_id + '/' + name
            require(clip[field] == storage_path and storage_path not in paths, 'Immutable media path mismatch')
            require(clip['media_type' if name == 'video.mp4' else 'thumbnail_media_type'] == mime, 'Media MIME mismatch')
            paths.add(storage_path)
            uploads[storage_path] = (read_local(folder / name, clip[size_key], clip[hash_key], limit), mime)
    require(len(uploads) == 14, 'Expected fourteen unique prepared media objects')
    return manifest, uploads


def metadata(client, clips):
    # Deliberately has no status predicate: a hidden pending row must not be
    # mistaken for an approved-only filter returning no rows.
    ids = ','.join(c['id'] for c in clips)
    endpoint = ('/rest/v1/video_posts?select=id,owner_id,status,game_id,caption,video_path,'
                'thumbnail_path,game:games(id,name)&id=in.(' + ids + ')')
    status, payload = client.call(endpoint)
    require(status == 200, 'Unfiltered seed metadata query failed: HTTP ' + str(status))
    rows = json.loads(payload)
    require(isinstance(rows, list), 'Unexpected seed metadata representation')
    return rows


def exact_rows(rows, clips, status):
    require(len(rows) == 7 and {r['id'] for r in rows} == set(EXPECTED), 'Expected exactly seven visible seed rows')
    expected = {c['id']: c for c in clips}
    for row in rows:
        clip = expected[row['id']]
        require(row['status'] == status, 'Unexpected seed post status')
        for key in ('owner_id', 'game_id', 'caption', 'video_path', 'thumbnail_path'):
            require(row[key] == clip[key], 'Seed metadata differs from the frozen manifest')
        require(row.get('game') == {'id': clip['game_id'], 'name': clip['game_name']}, 'Seed game registry differs from the reviewed manifest')


def exact_media(status, body, prepared):
    return status == 200 and len(body) == len(prepared) and digest(body) == digest(prepared)


def upload(manifest, uploads):
    client = Client(manifest, 'Development Alpha')
    try:
        require(client.base == BASE and client.user_id == OWNER, 'Development Alpha identity mismatch')
        exact_rows(metadata(client, manifest['clips']), manifest['clips'], 'pending')
        for clip in manifest['clips']:
            for key in ('video_path', 'thumbnail_path'):
                path = clip[key]
                data, mime = uploads[path]
                endpoint = '/storage/v1/object/clips/' + path
                status, existing = client.call(endpoint)
                if status == 200:
                    require(exact_media(status, existing, data), 'Immutable object collision: existing SHA-256 differs')
                else:
                    # Storage uses 400 as well as 404 for absent/private objects.
                    # A POST with x-upsert=false can never replace a collision.
                    require(status in (400, 404), 'Owner media lookup failed: HTTP ' + str(status))
                    headers = {'apikey': client.key, 'Authorization': 'Bearer ' + client.token,
                               'Content-Type': mime, 'x-upsert': 'false'}
                    status, _ = request(BASE + endpoint, headers=headers, data=data, method='POST')
                    require(status in (200, 400, 409), 'Immutable media upload failed: HTTP ' + str(status))
                    # On an upload collision, reuse is allowed only after an exact
                    # authenticated byte/hash readback, never from an error body.
                read_status, readback = client.call(endpoint)
                require(exact_media(read_status, readback, data), 'Authenticated immutable media readback mismatch')
            print(json.dumps({'id': clip['id'], 'upload': 'both-media-sha256-verified'}), flush=True)
    finally:
        client.close()  # Existing Client revokes only this newly created local session.


def verify(manifest, uploads, approved):
    client = Client(manifest, 'Development Beta')
    expected_status = 'approved' if approved else 'pending'
    results = []
    try:
        require(client.base == BASE and client.user_id != OWNER, 'Development Beta must be a peer of Alpha')
        rows = metadata(client, manifest['clips'])
        if approved:
            exact_rows(rows, manifest['clips'], 'approved')
        else:
            require(rows == [], 'Pending seed metadata is visible to the development peer')
        anon_feed_status, _ = client.call('/rest/v1/video_posts?select=id', anonymous=True)
        require(anon_feed_status == 401, 'Anonymous video feed must return HTTP 401')
        for clip in manifest['clips']:
            media_results = []
            for key in ('video_path', 'thumbnail_path'):
                path = clip[key]
                data, _ = uploads[path]
                endpoint = '/storage/v1/object/clips/' + path
                peer_status, body = client.call(endpoint)
                if approved:
                    require(exact_media(peer_status, body, data), 'Approved peer media SHA-256 mismatch')
                else:
                    require(peer_status in DENIED, 'Pending media is visible to the development peer')
                anonymous_status, _ = client.call(endpoint, anonymous=True)
                public_status, _ = client.call('/storage/v1/object/public/clips/' + path, anonymous=True)
                signed_status, _ = client.call('/storage/v1/object/sign/clips/' + path,
                                               method='POST', data=b'{"expiresIn":60}')
                require(anonymous_status in DENIED, 'Anonymous media access was not denied')
                require(public_status in DENIED, 'Public media access was not denied')
                require(signed_status in DENIED, 'Signed media capability was not denied')
                media_results.append({'kind': 'video' if key == 'video_path' else 'cover',
                    'peer_http': peer_status, 'anonymous_http': anonymous_status,
                    'public_http': public_status, 'sign_http': signed_status,
                    'peer_sha256_match': approved})
            results.append({'id': clip['id'], 'expected_status': expected_status,
                            'metadata_visible': approved, 'media': media_results})
    finally:
        client.close()
    print(json.dumps({'expected_status': expected_status, 'unfiltered_id_query_http': 200,
        'visible_seed_rows': len(rows), 'anonymous_feed_http': anon_feed_status, 'clips': results}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('upload', 'verify-pending', 'verify-approved'))
    action = parser.parse_args().action
    manifest, uploads = preflight()  # No Client/credential access before this completes.
    if action == 'upload':
        upload(manifest, uploads)
    else:
        verify(manifest, uploads, action == 'verify-approved')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Never emit response payloads, auth headers, tokens or credential data.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('Seed import stopped: ' + message, file=sys.stderr)
        sys.exit(1)
