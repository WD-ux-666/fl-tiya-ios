#!/usr/bin/env python3
"""Read-only live call readiness/ACL checks using short-lived test sessions.

No calls or relationships are created. Codes/tokens never enter the report.
"""
import json
from pathlib import Path
import urllib.error
import urllib.request
from import_development_clips import Client, NoRedirects

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / '.planning/2026-11-03-supabase-backend/friends-calls-http.json'


def invoke(client, path, body, anonymous=False):
    headers = {'apikey': client.key, 'Content-Type': 'application/json'}
    if not anonymous:
        headers['Authorization'] = 'Bearer ' + client.token
    request = urllib.request.Request(client.base + path, method='POST', headers=headers,
                                     data=json.dumps(body).encode())
    try:
        response = urllib.request.build_opener(NoRedirects()).open(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        status = response.code
        data = response.read(65537)
    if len(data) > 65536:
        raise RuntimeError('Unexpected response size')
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        raise RuntimeError('Unexpected response format') from None
    return status, value


def main():
    evidence = {'project_ref': 'gpstwmffctwqlcakmvgw', 'checks': [],
                'creates_call': False, 'changes_friendship': False, 'live_media_tested': False}
    clients = []
    try:
        for label in ['Development Alpha', 'Development Beta']:
            client = Client(evidence, label)
            clients.append(client)
            endpoint = '/functions/v1/call-service'
            status, value = invoke(client, endpoint, {'action': 'availability'})
            assert status == 200 and value == {'available': False}, 'Expected unconfigured RTC'
            evidence['checks'].append({'account': label, 'action': 'availability', 'status': status, 'available': False})
            status, value = invoke(client, endpoint, {'action': 'state'})
            assert status == 200 and value == {'call': None}, 'Unexpected active call'
            evidence['checks'].append({'account': label, 'action': 'state', 'status': status, 'call': None})
        client, peer = clients
        for kind in ['voice', 'video']:
            status, value = invoke(client, '/functions/v1/call-service',
                {'action': 'create', 'target_user_id': peer.user_id, 'kind': kind})
            assert status == 503 and value == {'error': 'calls_unavailable'}, 'RTC must fail closed'
            evidence['checks'].append({'action': 'create_' + kind, 'status': status, 'error': value['error']})
        status, value = invoke(client, '/functions/v1/call-service', {'action': 'state'}, anonymous=True)
        assert status == 401, 'Anonymous call state exposed'
        evidence['checks'].append({'action': 'anonymous_state', 'status': status})
        status, value = invoke(client, '/rest/v1/rpc/call_action',
            {'actor_user_id': client.user_id, 'actor_session_id': '00000000-0000-0000-0000-000000000000', 'action': 'state'})
        assert status == 403, 'Client obtained service-only call action'
        evidence['checks'].append({'action': 'direct_rpc', 'status': status})
    finally:
        for client in clients:
            client.close()
    evidence['verification_sessions_signed_out'] = True
    REPORT.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'http_checks_passed': len(evidence['checks']), 'media_tested': False,
                      'rtc_available': False, 'verification_sessions_signed_out': True}))


if __name__ == '__main__':
    main()
