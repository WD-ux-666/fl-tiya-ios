#!/usr/bin/env python3
"""Delete only a fresh anonymous fixture that this process creates.

No admin credentials, existing development access codes or existing accounts
are used. Session tokens stay in memory and are never printed or persisted.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import time
import uuid

from import_development_clips import request

ROOT = Path(__file__).resolve().parents[1]
PROJECT_URL = 'https://gpstwmffctwqlcakmvgw.supabase.co'


def verify():
    config = plistlib.loads((ROOT / 'FLTiya/Resources/SupabaseConfig.plist').read_bytes())
    assert config['ProjectURL'].rstrip('/') == PROJECT_URL, 'Unexpected test project'
    key = config['PublishableKey']
    marker = 'account-deletion-fixture-' + str(uuid.uuid4())
    token = None
    fixture_id = None
    deleted = False
    report = {'project': 'gpstwmffctwqlcakmvgw', 'existing_accounts_targeted': False}

    def call(path, method='GET', body=None, content_type='application/json', authenticated=True):
        headers = {'apikey': key, 'Content-Type': content_type}
        if authenticated and token:
            headers['Authorization'] = 'Bearer ' + token
        return request(PROJECT_URL + path, headers=headers, data=body, method=method)

    def rpc(name, value):
        status, data = call('/rest/v1/rpc/' + name, 'POST', json.dumps(value).encode())
        assert status == 200, 'Fixture RPC failed: ' + name + ' HTTP ' + str(status)
        return json.loads(data)

    try:
        status, data = call('/auth/v1/signup', 'POST', json.dumps({'data': {'fixture_marker': marker}}).encode(),
                            authenticated=False)
        assert status == 200, 'Fixture signup HTTP ' + str(status)
        signup = json.loads(data)
        token = signup['access_token']
        fixture_id = signup['user']['id']
        assert str(uuid.UUID(fixture_id)) == fixture_id
        status, data = call('/auth/v1/user')
        user = json.loads(data) if status == 200 else {}
        assert user.get('id') == fixture_id and user.get('is_anonymous') is True
        assert user.get('user_metadata', {}).get('fixture_marker') == marker
        context = rpc('session_context', {})
        assert context['user_id'] == fixture_id and context['is_experience'] is True

        # Upload an unchanged original asset as this fixture's private avatar.
        avatar = (ROOT / 'FLTiya/Resources/Assets.xcassets/SocialThemeArt/'
                  'StickerPrivacy.imageset/StickerPrivacy.png').read_bytes()
        avatar_path = fixture_id + '/' + str(uuid.uuid4()) + '.png'
        status, _ = call('/storage/v1/object/avatars/' + avatar_path, 'POST', avatar, 'image/png')
        assert status == 200, 'Fixture avatar upload HTTP ' + str(status)
        status, _ = call('/rest/v1/profiles?id=eq.' + fixture_id, 'PATCH',
                         json.dumps({'avatar_path': avatar_path, 'display_name': 'Deletion fixture'}).encode())
        assert status == 204, 'Fixture avatar attachment HTTP ' + str(status)
        status, readback = call('/storage/v1/object/avatars/' + avatar_path)
        assert status == 200 and hashlib.sha256(avatar).digest() == hashlib.sha256(readback).digest()

        # Body identity selection is rejected; only the current verified session
        # may choose its own account, and publishable-key-only requests fail.
        status, _ = call('/functions/v1/delete-account', 'POST', b'{"user_id":"ignored"}')
        assert status == 400, 'Identity-selecting deletion request was not rejected'
        status, _ = call('/functions/v1/delete-account', 'POST', b'{}', authenticated=False)
        assert status == 401, 'Unauthenticated deletion was not rejected'
        assert rpc('session_context', {})['user_id'] == fixture_id

        status, data = call('/functions/v1/delete-account', 'POST', b'{}')
        assert status == 200 and json.loads(data) == {'deleted': True}, 'Fixture deletion HTTP ' + str(status)
        deleted = True
        auth_status, _ = call('/auth/v1/user')
        context_status, _ = call('/rest/v1/rpc/session_context', 'POST', b'{}')
        storage_status, _ = call('/storage/v1/object/avatars/' + avatar_path)
        # A previously fetched URL can still be served from the provider's CDN.
        # Verify a fresh request and separately observe invalidation of the old
        # cache key; never mistake a cached 200 for an existing Storage row.
        cached_status = storage_status
        fresh_storage_status, _ = call('/storage/v1/object/avatars/' + avatar_path
                                      + '?deletion_check=' + str(uuid.uuid4()))
        assert auth_status in (401, 403, 404), 'Deleted Auth user still available'
        assert context_status in (400, 401, 403), 'Deleted session retained business access'
        assert fresh_storage_status in (400, 401, 403, 404), 'Fresh deleted media request was not denied'
        deadline = time.monotonic() + 70
        while storage_status == 200 and time.monotonic() < deadline:
            time.sleep(3)
            storage_status, _ = call('/storage/v1/object/avatars/' + avatar_path)
        assert storage_status in (400, 401, 403, 404), 'Deleted media cache did not expire within observation window'
        report.update(status='passed', fixture_id=fixture_id, fixture_deleted=True,
                      owned_avatar_uploaded_and_verified=True, identity_body_rejected=True,
                      unauthenticated_deletion_rejected=True, deleted_auth_http=auth_status,
                      deleted_session_http=context_status, deleted_avatar_http=storage_status,
                      immediate_cached_avatar_http=cached_status,
                      fresh_deleted_avatar_http=fresh_storage_status)
        (ROOT / '.planning/2026-11-03-supabase-backend/account-deletion-live-http-2026-11-06.json').write_text(
            json.dumps(report, indent=2) + '\n')
        print(json.dumps(report))
    finally:
        if fixture_id and token and not deleted:
            # Compatibility endpoint is scoped to the same just-created actor.
            status, _ = call('/functions/v1/delete-experience-account', 'POST', b'{}')
            if status != 200:
                raise RuntimeError('Fresh fixture cleanup needs attention; fixture UUID: ' + fixture_id)


if __name__ == '__main__':
    verify()
