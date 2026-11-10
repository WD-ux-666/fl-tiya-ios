#!/usr/bin/env python3
"""Import the reviewed development manifest without admin keys or public media.

prepare downloads/converts files; upload requires existing pending posts;
verify checks approved peer access and anonymous/signing denial. Approval is a
separate trusted operation after content review. Credentials stay in memory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'supabase/content/development-clips-2026-11-04.json'
PRIVATE = Path('/Users/shangbao666/.codex/private/fl-tiya-ios')
CACHE = PRIVATE / 'video-import-2026-11-04'
MAX_BYTES = 32 * 1024 * 1024


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Credentialed project requests must never forward headers elsewhere.
        return None


def digest(data):
    return hashlib.sha256(data).hexdigest()


def request(url, *, headers=None, data=None, method='GET', limit=MAX_BYTES):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.build_opener(NoRedirects()).open(req, timeout=45) as response:
            payload = response.read(limit + 1)
            if len(payload) > limit:
                raise RuntimeError('Response exceeded the import limit')
            return response.status, payload
    except urllib.error.HTTPError as error:
        # Never include a response body, request headers or credentials in logs.
        return error.code, b''


def prepare(manifest):
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    for clip in manifest['clips']:
        url = clip['download_url']
        if urllib.parse.urlsplit(url).hostname != 'upload.wikimedia.org':
            raise RuntimeError('Unreviewed download host')
        original = CACHE / (clip['slug'] + '.mov')
        if not original.exists():
            status, data = request(url, headers={'User-Agent': 'FLTiyaMediaImport/1.0'})
            if status != 200 or len(data) != clip['source_download_bytes']:
                raise RuntimeError('Source download status or byte count changed')
            original.write_bytes(data)
            original.chmod(0o600)
        source_data = original.read_bytes()
        if len(source_data) != clip['source_download_bytes']:
            raise RuntimeError('Cached source size mismatch')
        target = CACHE / (clip['slug'] + '.mp4')
        if not target.exists():
            subprocess.run(['/usr/bin/avconvert', '--source', str(original),
                '--preset', 'Preset640x480', '--output', str(target),
                '--start', '0', '--duration', '20'], check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=55)
            target.chmod(0o600)
        data = target.read_bytes()
        if not 0 < len(data) <= MAX_BYTES or b'ftyp' not in data[:32] or b'avc1' not in data:
            raise RuntimeError('Converted file is not a bounded H.264 MP4')
        clip['source_sha256'] = digest(source_data)
        clip['media_bytes'] = len(data)
        clip['media_sha256'] = digest(data)
        clip['media_type'] = 'video/mp4'
        print(clip['slug'], 'prepared', len(data), 'bytes')
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')


class Client:
    def __init__(self, manifest, label, *, account_file=None):
        config = plistlib.loads((ROOT / 'FLTiya/Resources/SupabaseConfig.plist').read_bytes())
        self.base = config['ProjectURL'].rstrip('/')
        self.key = config['PublishableKey']
        if self.base != 'https://' + manifest['project_ref'] + '.supabase.co':
            raise RuntimeError('Project mismatch')
        accounts = json.loads((account_file or PRIVATE / 'development-access.json').read_text())
        if accounts['project_ref'] != manifest['project_ref']:
            raise RuntimeError('Credential project mismatch')
        account = next(a for a in accounts['accounts'] if a['label'] == label)
        self.user_id = account['user_id']
        self.token = None
        status, payload = self.call('/functions/v1/development-login', method='POST',
            data=json.dumps({'access_code': account['access_code']}).encode())
        if status != 200:
            raise RuntimeError('Development login failed: HTTP ' + str(status))
        self.token = json.loads(payload)['access_token']
        try:
            status, payload = self.call('/rest/v1/rpc/session_context', method='POST', data=b'{}')
            context = json.loads(payload) if status == 200 else {}
            if context.get('user_id') != self.user_id or context.get('cohort') != 'development':
                raise RuntimeError('Unverified development context')
        except BaseException:
            self.close()
            raise

    def call(self, path, *, method='GET', data=None, media=False, anonymous=False):
        headers = {'apikey': self.key, 'Content-Type': 'video/mp4' if media else 'application/json'}
        if self.token and not anonymous:
            headers['Authorization'] = 'Bearer ' + self.token
        if media:
            headers['x-upsert'] = 'false'
        return request(self.base + path, headers=headers, data=data, method=method)

    def close(self):
        if self.token:
            status, _ = self.call('/auth/v1/logout?scope=local', method='POST')
            self.token = None
            if status not in (200, 204):
                raise RuntimeError('Import-session-only logout failed: HTTP ' + str(status))


def upload(manifest):
    client = Client(manifest, 'Development Alpha')
    try:
        for clip in manifest['clips']:
            if clip['owner_id'] != client.user_id:
                raise RuntimeError('Import owner mismatch')
            data = (CACHE / (clip['slug'] + '.mp4')).read_bytes()
            if digest(data) != clip['media_sha256'] or len(data) != clip['media_bytes']:
                raise RuntimeError('Reviewed media hash mismatch')
            endpoint = '/storage/v1/object/clips/' + clip['video_path']
            status, existing = client.call(endpoint)
            if status == 200:
                if digest(existing) != clip['media_sha256']:
                    raise RuntimeError('Immutable object collision')
            else:
                status, _ = client.call(endpoint, method='POST', data=data, media=True)
                if status != 200:
                    raise RuntimeError('Upload failed: HTTP ' + str(status))
            status, downloaded = client.call(endpoint)
            if status != 200 or digest(downloaded) != clip['media_sha256']:
                raise RuntimeError('Authenticated media readback failed')
            print(clip['slug'], 'uploaded and SHA-256 verified')
    finally:
        client.close()


def verify(manifest, expected_status):
    client = Client(manifest, 'Development Beta')
    results = []
    try:
        status, payload = client.call('/rest/v1/video_posts?select=id,status&status=eq.approved')
        assert status == 200
        visible = {p['id'] for p in json.loads(payload)} if status == 200 else set()
        ids = ','.join(c['id'] for c in manifest['clips'])
        metadata_status, metadata = client.call('/rest/v1/video_posts?select=id,status,game:games(name)&id=in.(' + ids + ')')
        assert metadata_status == 200
        peer_metadata = {p['id'] for p in json.loads(metadata)}
        anon_feed_status, _ = client.call('/rest/v1/video_posts?select=id', anonymous=True)
        assert anon_feed_status in (400, 401, 403)
        for clip in manifest['clips']:
            endpoint = '/storage/v1/object/clips/' + clip['video_path']
            status, data = client.call(endpoint)
            if expected_status == 'approved':
                assert clip['id'] in visible and clip['id'] in peer_metadata and status == 200 and digest(data) == clip['media_sha256']
            else:
                assert clip['id'] not in visible and clip['id'] not in peer_metadata and status in (400, 401, 403, 404)
            anonymous_status, _ = client.call(endpoint, anonymous=True)
            public_status, _ = client.call('/storage/v1/object/public/clips/' + clip['video_path'], anonymous=True)
            signed_status, _ = client.call('/storage/v1/object/sign/clips/' + clip['video_path'],
                method='POST', data=b'{"expiresIn":60}')
            assert anonymous_status in (400, 401, 403, 404)
            assert public_status in (400, 401, 403, 404)
            assert signed_status in (400, 401, 403, 404)
            results.append({'post_id': clip['id'], 'peer_media_http': status,
                'anonymous_http': anonymous_status, 'public_url_http': public_status,
                'signing_http': signed_status, 'peer_metadata_visible': clip['id'] in peer_metadata,
                'anonymous_feed_http': anon_feed_status, 'expected_status': expected_status})
    finally:
        client.close()
    out = ROOT / '.planning/2026-11-03-supabase-backend' / ('clips-http-' + expected_status + '.json')
    out.write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'upload', 'verify-pending', 'verify-approved'])
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest['cohort'] != 'development' or len(manifest['clips']) != 3:
        raise RuntimeError('Unexpected import scope')
    if args.action == 'prepare':
        prepare(manifest)
    elif args.action == 'upload':
        upload(manifest)
    else:
        verify(manifest, args.action.removeprefix('verify-'))
