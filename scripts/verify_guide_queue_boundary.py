#!/usr/bin/env python3
"""Check managed pg_net is unreachable through the app's Data API roles.

Supabase owns pg_net grants. Query only an opaque ID, never queue headers/body.
Uses a separate Beta session and revokes only that session on completion.
"""
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
from import_development_clips import Client, NoRedirects
from verify_initial_guides import preflight


def check(client, anonymous):
    headers = {'apikey': client.key, 'Accept-Profile': 'net'}
    if not anonymous:
        headers['Authorization'] = 'Bearer ' + client.token
    request = urllib.request.Request(
        client.base + '/rest/v1/http_request_queue?select=id&limit=1', headers=headers)
    try:
        with urllib.request.build_opener(NoRedirects()).open(request, timeout=20) as response:
            raise RuntimeError('Managed queue schema unexpectedly reachable: HTTP ' + str(response.status))
    except urllib.error.HTTPError as error:
        payload = error.read(8193)
        if len(payload) > 8192:
            raise RuntimeError('Unexpected schema-denial response size')
        code = json.loads(payload).get('code')
        if error.code != 406 or code != 'PGRST106':
            raise RuntimeError('Expected schema exclusion, received HTTP ' + str(error.code))
        return {'role': 'anon' if anonymous else 'authenticated', 'http': error.code, 'code': code}


if __name__ == '__main__':
    try:
        client = Client(preflight(), 'Development Beta')
        try:
            results = [check(client, False), check(client, True)]
        finally:
            client.close()
        print(json.dumps({'queue_data_api_probes': results,
                          'constraint': 'Managed pg_net grants remain PUBLIC; direct database logins are trusted.'}, indent=2))
    except Exception as error:
        print('Guide queue verification stopped: ' + (
            str(error) if isinstance(error, RuntimeError) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
