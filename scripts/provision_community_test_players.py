#!/usr/bin/env python3
"""Manage three explicitly fictional, isolated development community fixtures.

prepare writes private credentials and a guarded reservation SQL file. A trusted
operator applies that file to the manifest's project before provision uses the
existing development-login function and normal owner-scoped REST permissions.
verify checks real hosted visibility and persists one fixture-to-fixture pending
request. It never accepts requests or befriends Development Alpha automatically.
No credentials, sessions, or raw upstream errors are printed or saved in the repo.
"""
import argparse
from contextlib import ExitStack, contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets

from import_development_clips import Client, ROOT, PRIVATE

MANIFEST = ROOT / 'supabase/content/development-community-players-2026-11-06.json'
CURRENT_PROFILES = ROOT / 'supabase/content/development-player-profiles-2026-11-06.json'
ACCESS = PRIVATE / 'community-test-access-2026-11-06.json'
RESERVATIONS = PRIVATE / 'community-test-reservations-2026-11-06.sql'
RETIRE = PRIVATE / 'community-test-retire-2026-11-06.sql'
REPORT = ROOT / '.planning/2026-11-03-supabase-backend/community-test-players-http-2026-11-06.json'
PROJECT = 'gpstwmffctwqlcakmvgw'


def write_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(value)
    path.chmod(0o600)


def checked_manifest():
    if CURRENT_PROFILES.exists():
        raise RuntimeError('Historical shared-player utility superseded by current community manifests')
    value = json.loads(MANIFEST.read_text())
    if value['project_ref'] != PROJECT or value['cohort'] != 'development':
        raise RuntimeError('Fixture project/cohort mismatch')
    if len(value['players']) != 3 or len(set(value['game_ids'])) != 12:
        raise RuntimeError('Unexpected fixture scope')
    for player in value['players']:
        if not player['display_name'].startswith('[TEST] ') or 'Fictional test account' not in player['bio']:
            raise RuntimeError('Missing visible fictional test labeling')
    return value


def checked_access(manifest):
    value = json.loads(ACCESS.read_text())
    if value['project_ref'] != PROJECT or value['fixture_set'] != manifest['fixture_set']:
        raise RuntimeError('Private fixture manifest mismatch')
    expected = {(p['label'], p['user_id']) for p in manifest['players']}
    if {(a['label'], a['user_id']) for a in value['accounts']} != expected:
        raise RuntimeError('Private fixture identity mismatch')
    return value


def prepare(manifest):
    if ACCESS.exists():
        private = checked_access(manifest)
    else:
        private = {
            'project_ref': PROJECT,
            'fixture_set': manifest['fixture_set'],
            'cohort': 'development',
            'expires_at': manifest['expires_at'],
            'accounts': [dict(label=p['label'], user_id=p['user_id'],
                access_code='FLD_' + secrets.token_urlsafe(32)) for p in manifest['players']],
            'manual_test_flow': [
                'Sign in with Development Alpha using the existing private development-access.json.',
                'Open Players, choose any game, then Apply friend to a [TEST] profile.',
                'Sign out, use that fixture account access_code in Development access, then open Messages > Friend requests.',
                'Accept or decline explicitly. No fixture auto-accepts; notifications require refresh or reopening.',
                'Sign back in as Alpha to inspect the persisted request / friendship and send messages.',
                'Voice and video calls require an accepted friendship and configured LiveKit; these checks do not place a call.'
            ],
            'cleanup': {
                'owned_user_ids': [p['user_id'] for p in manifest['players']],
                'owned_game_cards': 36,
                'retire_sql': str(RETIRE),
                'note': 'Retirement only disables these reservations. Actual account deletion is a separate exact-ID admin operation. Preserve Alpha, Beta, experience users and all clips.'
            }
        }
        write_private(ACCESS, json.dumps(private, indent=2) + '\n')
    statements = ['-- Private generated reservations; never store this file in the repository.', 'begin;']
    retire = ['-- Disable only this fixture set; do not change baseline accounts or content.', 'begin;']
    for account in private['accounts']:
        user = account['user_id']
        label = account['label']
        email = 'development.' + user + '@example.invalid'
        code_hash = hashlib.sha256(account['access_code'].encode()).hexdigest()
        statements.append(f"""do $fixture$
begin
 if exists(select 1 from private.development_accounts where user_id='{user}'::uuid) then
  if not exists(select 1 from private.development_accounts where user_id='{user}'::uuid
      and email='{email}' and label='{label}' and code_hash='{code_hash}'
      and enabled and expires_at='{manifest['expires_at']}'::timestamptz) then
   raise exception 'fixture_reservation_collision';
  end if;
 elsif exists(select 1 from auth.users where id='{user}'::uuid or lower(email)='{email}') then
  raise exception 'fixture_identity_already_exists';
 else
  insert into private.development_accounts(user_id,email,label,code_hash,enabled,expires_at)
   values('{user}'::uuid,'{email}','{label}','{code_hash}',true,'{manifest['expires_at']}'::timestamptz);
 end if;
end $fixture$;""")
        retire.append(f"update private.development_accounts set enabled=false where user_id='{user}'::uuid and label='{label}';")
    statements.extend(['commit;', "select count(*) as enabled_fixture_reservations from private.development_accounts where label in ('Development TEST Ember','Development TEST Harbor','Development TEST Summit') and enabled;"])
    retire.append('commit;')
    write_private(RESERVATIONS, '\n'.join(statements) + '\n')
    write_private(RETIRE, '\n'.join(retire) + '\n')
    print(json.dumps({'credentials_file': str(ACCESS), 'reservation_sql_file': str(RESERVATIONS),
        'retire_sql_file': str(RETIRE), 'accounts': 3, 'game_cards': 36}))


@contextmanager
def fixture_client(manifest, label, *, baseline=False):
    client = Client(manifest, label, account_file=None if baseline else ACCESS)
    try:
        yield client
    finally:
        client.close()


def json_call(client, path, *, method='GET', value=None, expected=(200,)):
    status, body = client.call(path, method=method,
        data=None if value is None else json.dumps(value).encode())
    if status not in expected:
        raise RuntimeError('Fixture request failed: HTTP ' + str(status))
    return json.loads(body) if body else None


def provision(manifest):
    if CURRENT_PROFILES.exists():
        raise RuntimeError('Legacy provisioning disabled: current display profiles are managed by '
                           'supabase/content/development-player-profiles-2026-11-06.json. '
                           'Use the current UUID-keyed profile maintenance workflow.')
    checked_access(manifest)
    for player in manifest['players']:
        with fixture_client(manifest, player['label']) as client:
            if client.user_id != player['user_id']:
                raise RuntimeError('Fixture actor mismatch')
            profile = {k: player[k] for k in ('handle', 'display_name', 'bio')}
            profile['avatar_path'] = None  # Use the app's existing helmet placeholder.
            json_call(client, '/rest/v1/profiles?id=eq.' + client.user_id,
                method='PATCH', value=profile, expected=(204,))
            current = json_call(client, '/rest/v1/game_cards?select=game_id&user_id=eq.' + client.user_id)
            existing = {card['game_id'] for card in current}
            missing = [dict(user_id=client.user_id, game_id=game, player_name=player['display_name'],
                days_played=None, progress=player['playstyle'] + ' (fictional test data)')
                for game in manifest['game_ids'] if game not in existing]
            if missing:
                json_call(client, '/rest/v1/game_cards', method='POST', value=missing, expected=(201,))
            saved = json_call(client, '/rest/v1/profiles?select=id,handle,display_name,bio,avatar_path&id=eq.' + client.user_id)
            cards = json_call(client, '/rest/v1/game_cards?select=game_id&user_id=eq.' + client.user_id)
            if saved != [dict(id=client.user_id, **profile)] or {c['game_id'] for c in cards} != set(manifest['game_ids']):
                raise RuntimeError('Fixture profile/card readback mismatch')
            print(json.dumps({'user_id': client.user_id, 'display_name': player['display_name'], 'saved_game_cards': len(cards)}))


def verify(manifest):
    checked_access(manifest)
    fixture_ids = {p['user_id'] for p in manifest['players']}
    result = {'project_ref': PROJECT, 'fixture_set': manifest['fixture_set'],
        'verified_at': datetime.now(timezone.utc).isoformat(), 'communities': []}
    with ExitStack() as stack:
        alpha = stack.enter_context(fixture_client(manifest, 'Development Alpha', baseline=True))
        clients = [stack.enter_context(fixture_client(manifest, p['label'])) for p in manifest['players']]
        # Alpha's untouched outgoing applications remain available for manual UI testing.
        for game in manifest['game_ids']:
            rows = json_call(alpha, '/rest/v1/rpc/discover_community_players', method='POST',
                value={'target_game_id': game, 'search_query': ''})
            visible = [row for row in rows if row['id'] in fixture_ids]
            if len(visible) != 3 or any(not row['display_name'].startswith('[TEST] ') for row in visible):
                raise RuntimeError('Missing visibly labeled community fixtures')
            result['communities'].append({'game_id': game, 'visible_test_players': len(visible),
                'relationships': sorted(row['relationship'] for row in visible)})
        alpha_friends = json_call(alpha, '/rest/v1/friendships?select=user_low,user_high')
        if any(row['user_low'] in fixture_ids or row['user_high'] in fixture_ids for row in alpha_friends):
            raise RuntimeError('Alpha already befriended a fixture; use manual testing state explicitly')
        # A genuine persisted request is created solely between new fixture accounts.
        sender, recipient = clients[:2]
        request = json_call(sender, '/rest/v1/rpc/send_friend_request', method='POST',
            value={'target_user_id': recipient.user_id})
        request_id = request['id']
        if request['status'] != 'pending':
            raise RuntimeError('Fixture request unexpectedly accepted')
        received = json_call(recipient, '/rest/v1/friend_requests?select=id,sender_id,recipient_id,status&id=eq.' + request_id)
        if received != [dict(id=request_id, sender_id=sender.user_id, recipient_id=recipient.user_id, status='pending')]:
            raise RuntimeError('Recipient cannot read the persisted request')
        again = json_call(sender, '/rest/v1/rpc/send_friend_request', method='POST',
            value={'target_user_id': recipient.user_id})
        if again['id'] != request_id:
            raise RuntimeError('Repeated Apply friend was not idempotent')
        result['pending_fixture_request'] = received[0]
        result['repeat_apply_same_request'] = True
        result['alpha_fixture_friendships'] = 0
        availability = json_call(alpha, '/functions/v1/call-service', method='POST', value={'action': 'availability'})
        if not isinstance(availability.get('available'), bool):
            raise RuntimeError('Missing call service availability result')
        result['call_service_available'] = availability['available']
        result['nonfriend_relationship_enforced_via_http'] = availability['available']
        result['nonfriend_call_http'] = []
        for kind in ('voice', 'video'):
            status, _ = alpha.call('/functions/v1/call-service', method='POST',
                data=json.dumps({'action': 'create', 'target_user_id': clients[2].user_id, 'kind': kind}).encode())
            expected_status = 403 if availability['available'] else 503
            if status != expected_status:
                raise RuntimeError('Nonfriend call was not rejected: HTTP ' + str(status))
            result['nonfriend_call_http'].append({'kind': kind, 'status': status})
        status, _ = alpha.call('/rest/v1/rpc/discover_community_players', method='POST',
            data=b'{"target_game_id":null,"search_query":""}', anonymous=True)
        if status not in (400, 401, 403):
            raise RuntimeError('Anonymous community discovery was not denied')
        result['anonymous_discovery_http'] = status
        clips = json_call(alpha, '/rest/v1/video_posts?select=id&status=eq.approved')
        if len(clips) != 10:
            raise RuntimeError('Existing approved clip count changed')
        result['existing_approved_clips'] = len(clips)
    # Explicitly sign back in: a fresh recipient session must see the same row.
    with fixture_client(manifest, manifest['players'][1]['label']) as recipient:
        reread = json_call(recipient, '/rest/v1/friend_requests?select=id,status&id=eq.' + request_id)
        if reread != [dict(id=request_id, status='pending')]:
            raise RuntimeError('Pending request did not survive session switching')
    result['pending_request_survived_new_session'] = True
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'provision', 'verify'])
    args = parser.parse_args()
    manifest = checked_manifest()
    {'prepare': prepare, 'provision': provision, 'verify': verify}[args.action](manifest)
