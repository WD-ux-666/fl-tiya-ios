#!/usr/bin/env python3
"""Upload reviewed immutable covers and verify private access; never approve posts.

Uses the existing development importer credentials in memory. Pending/reapproval
is a separate, exact-row trusted SQL operation. No public or signed URLs are used.
"""
import argparse
import json
import os
import struct
import uuid

from import_development_clips import CACHE, MANIFEST, ROOT, Client, digest, request

MAX_COVER_BYTES = 2 * 1024 * 1024
REPORTS = ROOT / '.planning/2026-11-03-supabase-backend'


def cover_data(clip):
    expected = clip['owner_id'] + '/' + clip['id'] + '/cover.png'
    if clip['thumbnail_path'] != expected:
        raise RuntimeError('Unexpected cover path')
    data = (CACHE / 'covers' / (clip['slug'] + '.mp4.png')).read_bytes()
    if not 0 < len(data) <= MAX_COVER_BYTES or data[:8] != b'\x89PNG\r\n\x1a\n':
        raise RuntimeError('Cover is not a bounded PNG')
    if struct.unpack('>II', data[16:24]) != tuple(clip['thumbnail_dimensions']):
        raise RuntimeError('Cover dimensions changed')
    if len(data) != clip['thumbnail_bytes'] or digest(data) != clip['thumbnail_sha256']:
        raise RuntimeError('Reviewed cover hash changed')
    return data


def call(client, path, *, method='GET', data=None, anonymous=False, upload=False):
    headers = {'apikey': client.key,
               'Content-Type': 'image/png' if upload else 'application/json'}
    if client.token and not anonymous:
        headers['Authorization'] = 'Bearer ' + client.token
    if upload:
        headers['x-upsert'] = 'false'
    return request(client.base + path, headers=headers, data=data, method=method,
                   limit=MAX_COVER_BYTES)


def upload(manifest):
    # Validate all three local files before starting any upload.
    payloads = [(clip, cover_data(clip)) for clip in manifest['clips']]
    client = Client(manifest, 'Development Alpha')
    try:
        for clip, data in payloads:
            if clip['owner_id'] != client.user_id:
                raise RuntimeError('Cover owner mismatch')
            endpoint = '/storage/v1/object/clips/' + clip['thumbnail_path']
            status, existing = call(client, endpoint)
            if status == 200:
                if digest(existing) != clip['thumbnail_sha256']:
                    raise RuntimeError('Immutable cover collision')
            else:
                status, _ = call(client, endpoint, method='POST', data=data, upload=True)
                if status != 200:
                    raise RuntimeError('Cover upload failed: HTTP ' + str(status))
            status, downloaded = call(client, endpoint + '?cacheNonce=' + str(uuid.uuid4()))
            if status != 200 or downloaded != data:
                raise RuntimeError('Authenticated cover readback failed')
            print(clip['slug'], 'cover uploaded and SHA-256 verified')
    finally:
        client.close()


def verify(manifest, expected_status):
    client = Client(manifest, 'Development Beta')
    results = []
    try:
        ids = ','.join(c['id'] for c in manifest['clips'])
        status, payload = call(client,
            '/rest/v1/video_posts?select=id,status,thumbnail_path,caption,game:games(name)'
            '&id=in.(' + ids + ')')
        if status != 200:
            raise RuntimeError('Peer cover metadata query failed')
        visible = {p['id']: p for p in json.loads(payload)}
        anon_feed, _ = call(client, '/rest/v1/video_posts?select=id', anonymous=True)
        assert anon_feed in (400, 401, 403)
        for clip in manifest['clips']:
            cover_data(clip)
            path = clip['thumbnail_path']
            endpoint = '/storage/v1/object/clips/' + path
            status, data = call(client, endpoint + '?cacheNonce=' + str(uuid.uuid4()))
            if expected_status == 'approved':
                assert visible[clip['id']]['status'] == 'approved'
                assert visible[clip['id']]['thumbnail_path'] == path
                assert visible[clip['id']]['caption'] == clip['caption']
                assert status == 200 and digest(data) == clip['thumbnail_sha256']
            else:
                assert clip['id'] not in visible and status in (400, 401, 403, 404)
            anonymous, _ = call(client, endpoint, anonymous=True)
            public, _ = call(client, '/storage/v1/object/public/clips/' + path, anonymous=True)
            signing, _ = call(client, '/storage/v1/object/sign/clips/' + path,
                              method='POST', data=b'{"expiresIn":60}')
            assert all(s in (400, 401, 403, 404) for s in (anonymous, public, signing))
            results.append({'post_id': clip['id'], 'peer_cover_http': status,
                'peer_metadata_visible': clip['id'] in visible,
                'sha256_verified': expected_status == 'approved',
                'anonymous_http': anonymous, 'public_url_http': public,
                'signing_http': signing, 'anonymous_feed_http': anon_feed,
                'expected_status': expected_status})
    finally:
        client.close()
    out = REPORTS / ('covers-http-' + expected_status + '.json')
    out.write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['upload', 'verify-pending', 'verify-approved'])
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest['project_ref'] != 'gpstwmffctwqlcakmvgw' or \
            manifest['cohort'] != 'development' or len(manifest['clips']) != 3:
        raise RuntimeError('Unexpected cover import scope')
    if args.action == 'upload':
        upload(manifest)
    else:
        verify(manifest, args.action.removeprefix('verify-'))
