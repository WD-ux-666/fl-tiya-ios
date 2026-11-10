#!/usr/bin/env python3
"""Guarded, exact-ten development publisher transfer. Never prints credentials.

prepare backs up unchanged private objects and generates trusted data SQL;
upload requires the staged rows and uses genuine fixture sessions;
verify reads final author, relationship, media and privacy paths as Alpha.
SQL execution is a separate reviewed administrative action. Original objects
remain private for rollback. This script never changes RLS or Storage metadata.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error

from import_development_clips import Client as BaseClient, PRIVATE, ROOT

MANIFEST = ROOT / 'supabase/content/development-clip-publishers-2026-11-06.json'
CACHE = PRIVATE / 'publisher-transfer-2026-11-06'
EVIDENCE = ROOT / '.planning/2026-11-03-supabase-backend/clip-publisher-transfer-2026-11-06.json'
FIXTURE_ACCESS = PRIVATE / 'community-test-access-2026-11-06.json'


def request(url, *, headers=None, data=None, method='GET', limit=32 * 1024 * 1024):
    """Use system TLS; credentials travel only through curl's stdin config.

    urllib had repeated TLS transport failures on this Mac. No redirects,
    command-line credentials, response logging or automatic write retries.
    Transient request/response files are private and removed before returning.
    """
    require(url.startswith('https://gpstwmffctwqlcakmvgw.supabase.co/'), 'Unexpected HTTP origin')
    with tempfile.TemporaryDirectory(prefix='publisher-http-', dir=PRIVATE) as directory:
        response = Path(directory) / 'response'
        config = ['url = ' + json.dumps(url), 'request = ' + json.dumps(method),
                  'output = ' + json.dumps(str(response))]
        for key, value in (headers or {}).items():
            require(not any(c in key + value for c in '\r\n\0'), 'Invalid HTTP header')
            config.append('header = ' + json.dumps(key + ': ' + value))
        if data is not None:
            body = Path(directory) / 'body'
            body.write_bytes(data)
            body.chmod(0o600)
            config.append('data-binary = ' + json.dumps('@' + str(body)))
        result = subprocess.run(['/usr/bin/curl', '-q', '--config', '-', '--silent', '--show-error',
                                 '--proto', '=https', '--max-redirs', '0', '--connect-timeout', '15',
                                 '--max-time', '45', '--max-filesize', str(limit),
                                 '--write-out', '%{http_code}'],
                                input=('\n'.join(config) + '\n').encode(),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=50)
        if result.returncode:
            raise urllib.error.URLError('System HTTP transport failed')
        status = int(result.stdout.decode('ascii'))
        if status >= 400:
            return status, b''
        require(response.stat().st_size <= limit, 'HTTP response exceeded bound')
        return status, response.read_bytes()


class Client(BaseClient):
    def call(self, path, *, method='GET', data=None, media=False, anonymous=False):
        headers = {'apikey': self.key, 'Content-Type': 'video/mp4' if media else 'application/json'}
        if self.token and not anonymous:
            headers['Authorization'] = 'Bearer ' + self.token
        if media:
            headers['x-upsert'] = 'false'
        return request(self.base + path, headers=headers, data=data, method=method)


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def rpc(client, name, params):
    status, payload = client.call('/rest/v1/rpc/' + name, method='POST',
                                 data=json.dumps(params).encode())
    require(status == 200, name + ' HTTP ' + str(status))
    return json.loads(payload)


def media(client, obj, path, *, upload=False):
    headers = {'apikey': client.key, 'Authorization': 'Bearer ' + client.token}
    if upload:
        headers.update({'Content-Type': obj['mime'], 'x-upsert': 'false'})
        return request(client.base + '/storage/v1/object/clips/' + path,
                       method='POST', headers=headers,
                       data=(CACHE / obj['cache_name']).read_bytes())
    return request(client.base + '/storage/v1/object/authenticated/clips/' + path,
                   headers=headers)


def checked_bytes(obj, data):
    require(len(data) == obj['bytes'], 'Object byte count changed')
    if 'sha256' in obj:
        require(sha(data) == obj['sha256'], 'Object SHA256 changed')


def close_session(client):
    # Retry only an uncertain transport failure on this temporary session's
    # local logout. Never revoke another device's sessions or repeat a purchase.
    for attempt in range(2):
        try:
            client.close()
            return
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt:
                raise


def prepare(manifest):
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    client = Client(manifest, 'Development Alpha')
    try:
        def backup(item):
            post, obj = item
            obj['cache_name'] = post['original']['id'] + '-' + obj['name'].rsplit('/', 1)[1]
            destination = CACHE / obj['cache_name']
            if destination.exists():
                require(not destination.is_symlink(), 'Cache symlink rejected')
                data = destination.read_bytes()
            else:
                status, data = media(client, obj, obj['name'])
                require(status == 200, 'Original media download HTTP ' + str(status))
                checked_bytes(obj, data)
                destination.write_bytes(data)
                destination.chmod(0o600)
            checked_bytes(obj, data)
            obj['sha256'] = sha(data)
            obj['target_path'] = post['target_owner_id'] + '/' + post['original']['id'] + '/' + obj['name'].rsplit('/', 1)[1]
        items = [(p, o) for p in manifest['posts'] for o in p['objects']]
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(backup, items))
    finally:
        close_session(client)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    generate_sql(manifest)
    print(json.dumps({'prepared_objects': len(items), 'bytes': sum(o['bytes'] for _, o in items),
                      'sha256_verified': True, 'remote_business_data_mutated': False}), flush=True)


def generate_sql(manifest):
    rows = []
    for post in manifest['posts']:
        original = post['original']
        staged = dict(original, owner_id=post['target_owner_id'],
                      video_path=post['target_video_path'], thumbnail_path=post['target_thumbnail_path'],
                      status='pending', approved_at=None)
        final = dict(staged, status='approved', approved_at=original['approved_at'])
        rows.append(dict(original=original, staged=staged, final=final, objects=post['objects']))
    payload = json.dumps(rows, separators=(',', ':'))
    require('$transfer$' not in payload, 'Unexpected SQL delimiter')
    common = "begin;\nset local lock_timeout='5s';\nset local statement_timeout='20s';\n"
    common += "create temporary table expected on commit drop as select * from jsonb_to_recordset($transfer$" + payload + "$transfer$::jsonb) as e(original jsonb,staged jsonb,final jsonb,objects jsonb);\n"
    common += "select v.id from public.video_posts v join expected e on v.id=(e.original->>'id')::uuid for update of v;\n"
    def guard(condition, message):
        return "do $$ begin if not (" + condition + ") then raise exception '" + message + "'; end if; end $$;\n"
    count = "(select count(*)=10 from public.video_posts v join expected e on to_jsonb(v)="
    stage = common + guard(count + "e.original)", 'Original post snapshot changed')
    stage += guard("(select count(*)=10 from public.video_posts where status='approved')", 'Approved feed scope changed')
    stage += guard("(select count(distinct p.id)=3 from expected e join public.profiles p on p.id=(e.staged->>'owner_id')::uuid where p.display_name in ('[TEST] Ember','[TEST] Harbor','[TEST] Summit'))", 'Fixture profile scope changed')
    stage += guard("not exists(select 1 from storage.objects o join expected e on o.bucket_id='clips' and o.name in(e.staged->>'video_path',e.staged->>'thumbnail_path'))", 'Target object already exists')
    stage += update_sql('staged') + "commit;\nselect count(*) as pending_transferred_posts from public.video_posts where id in(select (x->'original'->>'id')::uuid from jsonb_array_elements($transfer$" + payload + "$transfer$::jsonb) x) and status='pending';\n"
    approve = common + guard(count + "e.staged)", 'Staged post snapshot changed')
    approve += guard("(select count(*)=20 from expected e cross join lateral jsonb_array_elements(e.objects) x join storage.objects o on o.bucket_id='clips' and o.name=x->>'target_path' where o.owner_id=e.staged->>'owner_id' and (o.metadata->>'size')::bigint=(x->>'bytes')::bigint and o.metadata->>'mimetype'=x->>'mime')", 'New Storage ownership or bytes mismatch')
    approve += update_sql('final') + "commit;\nselect count(*) as approved_feed_posts from public.video_posts where status='approved';\n"
    restore = common + guard("(select count(*)=10 from public.video_posts v join expected e on to_jsonb(v)=e.staged or to_jsonb(v)=e.final)", 'Transfer snapshot changed; restore refused')
    restore += guard("(select count(*)=20 from expected e cross join lateral jsonb_array_elements(e.objects) x join storage.objects o on o.bucket_id='clips' and o.name=x->>'name' where o.owner_id=e.original->>'owner_id' and (o.metadata->>'size')::bigint=(x->>'bytes')::bigint)", 'Original Storage backup missing')
    restore += update_sql('original') + "commit;\n"
    for suffix, sql in [('stage', stage), ('approve', approve), ('restore', restore)]:
        (MANIFEST.parent / ('development-clip-publishers-2026-11-06-' + suffix + '.sql')).write_text(sql)


def update_sql(state):
    return "update public.video_posts v set owner_id=(e." + state + "->>'owner_id')::uuid,video_path=e." + state + "->>'video_path',thumbnail_path=e." + state + "->>'thumbnail_path',status=e." + state + "->>'status',approved_at=(e." + state + "->>'approved_at')::timestamptz from expected e where v.id=(e.original->>'id')::uuid;\n"


def upload(manifest):
    clients = {}
    try:
        for post in manifest['posts']:
            label = post['target_label']
            if label not in clients:
                clients[label] = Client(manifest, label, account_file=FIXTURE_ACCESS)
            client = clients[label]
            require(client.user_id == post['target_owner_id'], 'Fixture actor mismatch')
            for obj in post['objects']:
                checked_bytes(obj, (CACHE / obj['cache_name']).read_bytes())
                status, data = media(client, obj, obj['target_path'])
                if status != 200:
                    require(status in (400, 404), 'Unexpected pre-upload read HTTP ' + str(status))
                    status, _ = media(client, obj, obj['target_path'], upload=True)
                    require(status in (200, 201), 'Upload failed HTTP ' + str(status))
                    status, data = media(client, obj, obj['target_path'])
                require(status == 200, 'Uploaded object unavailable')
                checked_bytes(obj, data)
            print(json.dumps({'post_id': post['original']['id'], 'publisher': post['target_display_name'],
                              'uploaded_objects_readback_sha256': 2}), flush=True)
    finally:
        for client in clients.values():
            close_session(client)


def verify(manifest):
    client = Client(manifest, 'Development Alpha')
    try:
        status, payload = client.call('/rest/v1/video_posts?select=*&status=eq.approved&order=created_at.desc,id.desc')
        require(status == 200, 'Approved feed failed')
        actual = json.loads(payload)
        require(len(actual) == 10, 'Expected ten approved clips')
        ids = [p['id'] for p in actual]
        baseline = sorted([p['original'] for p in manifest['posts']], key=lambda p: (p['created_at'], p['id']), reverse=True)
        require(ids == [p['id'] for p in baseline], 'Raw feed ordering changed')
        by_id = {p['id']: p for p in actual}
        results = []
        for post in manifest['posts']:
            original = post['original']
            final = dict(original, owner_id=post['target_owner_id'], video_path=post['target_video_path'],
                         thumbnail_path=post['target_thumbnail_path'])
            require(by_id[original['id']] == final, 'Post metadata changed beyond ownership/paths')
            state = rpc(client, 'clip_social_state', {'target_clip_id': original['id']})
            require(state['uploader']['id'] == post['target_owner_id'] != client.user_id,
                    'Alpha still sees self as uploader')
            require(state['uploader']['display_name'] == post['target_display_name'], 'Wrong publisher name')
            for obj in post['objects']:
                status, data = media(client, obj, obj['target_path'])
                require(status == 200, 'Alpha media read failed')
                checked_bytes(obj, data)
                for prefix in ('authenticated', 'public'):
                    status, _ = client.call('/storage/v1/object/' + prefix + '/clips/' + obj['target_path'], anonymous=True)
                    require(status in (400, 401, 403, 404), 'Anonymous media exposed')
            results.append({'id': original['id'], 'publisher': post['target_display_name'],
                            'is_following': state['is_following'], 'media_and_cover_sha256': True})
        players = rpc(client, 'discover_community_players', {'target_game_id': None, 'search_query': ''})
        relations = {p['id']: p['relationship'] for p in players}
        publishers = []
        for owner in sorted({p['target_owner_id'] for p in manifest['posts']}):
            require(relations.get(owner) in ('none', 'incoming', 'outgoing', 'friends'),
                    'Fixture profile or relationship unavailable')
            follow = rpc(client, 'player_follow_state', {'target_user_id': owner})
            require(type(follow['is_following']) is bool, 'Invalid follow state')
            publishers.append({'user_id': owner, 'relationship': relations[owner],
                               'is_following': follow['is_following']})
        evidence = {'status': 'passed', 'project_ref': manifest['project_ref'], 'approved_clips': 10,
                    'actual_fixture_publishers': dict(Counter(p['target_display_name'] for p in manifest['posts'])),
                    'alpha_is_not_author': True, 'original_order_and_metadata_preserved': True,
                    'byte_identical_media_objects': 20, 'anonymous_media_denials': 40,
                    'alpha_publisher_states': publishers,
                    'social_business_data_mutated_by_verification': False,
                    'native_build_or_launch_performed': False, 'posts': results}
    finally:
        close_session(client)
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({k: v for k, v in evidence.items() if k != 'posts'}), flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'upload', 'verify'])
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    require(manifest['project_ref'] == 'gpstwmffctwqlcakmvgw' and len(manifest['posts']) == 10,
            'Unexpected project or transfer scope')
    try:
        {'prepare': prepare, 'upload': upload, 'verify': verify}[args.action](manifest)
    except Exception as error:
        # HTTP library exception strings can contain endpoint or header details.
        print(json.dumps({'status': 'failed', 'action': args.action,
                          'error_type': type(error).__name__,
                          'detail': str(error) if isinstance(error, RuntimeError) else 'Transport or local data failure'}), flush=True)
        raise SystemExit(1)
