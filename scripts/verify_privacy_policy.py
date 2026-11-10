#!/usr/bin/env python3
"""Check the public policy with no Supabase key, session or cookie jar."""
import hashlib
import json
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy'


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def verify():
    expected = (ROOT / 'supabase/functions/privacy-policy/policy.json').read_bytes()
    assert expected == (ROOT / 'FLTiya/Resources/PrivacyPolicy.json').read_bytes()
    policy = json.loads(expected)
    cases = []
    cookie_names = set()
    for query, method, expected_status in [
        ('', 'GET', 200), ('?format=json', 'GET', 200),
        ('', 'HEAD', 200), ('?format=json', 'HEAD', 200),
        ('', 'OPTIONS', 204), ('', 'POST', 405),
        ('?format=html', 'GET', 400), ('?user_id=fixture', 'GET', 400),
        ('?format=json&format=json', 'GET', 400),
    ]:
        request = urllib.request.Request(URL + query, method=method)
        try:
            response = urllib.request.build_opener(NoRedirects()).open(request, timeout=25)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            actual, headers, data = response.status, response.headers, response.read(131073)
        assert actual == expected_status, (method, query, actual)
        assert len(data) <= 131072
        # The application handler sets no cookies. The hosting infrastructure
        # can set __cf_bm. Record names only, never Cookie/Set-Cookie values.
        cookie_names.update(cookie.split('=', 1)[0] for cookie in headers.get_all('Set-Cookie', []))
        if method == 'GET' and actual == 200:
            assert headers.get('X-Policy-Version') == policy['document_version']
            if query:
                assert headers.get_content_type() == 'application/json'
                assert data == expected, 'Hosted policy differs from the bundled canonical copy'
            else:
                assert headers.get_content_type() == 'text/plain'
                assert data.decode().startswith('FL-Tiya Privacy Policy\nDraft · Not yet effective\nContact: '
                                                + policy['contact'] + '\n')
                assert b'<html' not in data and b'example.com' not in data
        if method in ('HEAD', 'OPTIONS'):
            assert not data
        cases.append({'method': method, 'query': query, 'http': actual})
    report = {'status': 'passed', 'url': URL, 'unauthenticated': True, 'cases': cases,
              'document_version': policy['document_version'],
              'json_sha256': hashlib.sha256(expected).hexdigest(),
              'hosting_cookie_names': sorted(cookie_names), 'native_runtime_verified': False}
    (ROOT / '.planning/2026-11-03-supabase-backend/privacy-policy-live-http-2026-11-06.json').write_text(
        json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    verify()
