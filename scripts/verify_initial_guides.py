#!/usr/bin/env python3
"""Verify the eight reviewed development Guides without publishing content.

Run verify-draft after draft.sql, and verify-published after approved SQL.
Uses a new Development Beta session and revokes only that local session.
The only write probes target a guarded nonexistent UUID or invalid crawler args.
"""
import argparse
import json
from pathlib import Path
import sys
import urllib.parse
import uuid

sys.dont_write_bytecode = True
from import_development_clips import Client, digest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'supabase/content/development-zzz-guides-2026-11-04.json'
MANIFEST_SHA256 = '25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36'
PROJECT = 'gpstwmffctwqlcakmvgw'
BASE = 'https://' + PROJECT + '.supabase.co'
GAME = 'zenless-zone-zero'
PROBE_ID = '00000000-0000-0000-0000-000000000000'
EXPECTED_IDS = frozenset((
    'cdfb5f16-1c25-5b72-890c-e3d4a3690d63', '836fc1a5-a875-5d49-8f2d-40c003e652e1',
    '3070a276-401f-50c3-9fdb-78f17c5b320c', '4181086f-6ba5-51fc-b425-cc2a3ec119ee',
    '329419be-b9e8-5ae1-875b-79f2a0010953', 'ff105627-73ee-5b59-96fe-b86bb85d6b17',
    'f0e2061f-43f6-548b-9b0f-4579ae60b1e3', 'f9d3ae61-2169-5587-b590-3ff9a700fe09',
))
FIELDS = ('id', 'game_id', 'title', 'summary', 'source_url', 'source_name',
          'source_author', 'attribution', 'cohort')
SELECT = ','.join(FIELDS + ('status', 'published_at'))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def preflight():
    """Finish all manifest validation before Client can access credentials."""
    raw = MANIFEST.read_bytes()
    require(digest(raw) == MANIFEST_SHA256, 'Final guide manifest changed; review SQL and verifier together')
    manifest = json.loads(raw)
    guides = manifest['guides']
    require(manifest['project_ref'] == PROJECT and manifest['cohort'] == 'development', 'Guide project/cohort mismatch')
    require(len(guides) == 8 and {g['id'] for g in guides} == EXPECTED_IDS, 'Expected exactly eight initial Guides')
    for guide in guides:
        require(str(uuid.UUID(guide['id'])) == guide['id'] and guide['id'] != PROBE_ID, 'Guide UUID mismatch')
        require(guide['game_id'] == GAME and guide['cohort'] == 'development', 'Guide metadata scope mismatch')
        require(0 < len(guide['title'].strip()) <= 200 and len(guide['summary']) <= 1000, 'Guide text bounds mismatch')
        require(bool(guide['source_name'].strip()) and bool(guide['attribution'].strip()), 'Missing guide attribution')
        require(guide['source_author'] is None or isinstance(guide['source_author'], str), 'Invalid nullable source author')
        parsed = urllib.parse.urlsplit(guide['source_url'])
        require(parsed.scheme == 'https' and parsed.hostname in ('zenless.hoyoverse.com', 'steamcommunity.com')
                and not parsed.username and not parsed.password and not parsed.port
                and not parsed.query and not parsed.fragment, 'Unexpected publisher source URL')
        require(all(key in guide for key in FIELDS), 'Guide manifest fields are incomplete')
    return manifest


def read_rows(client, endpoint, anonymous=False):
    status, payload = client.call(endpoint, anonymous=anonymous)
    require(status == 200, 'Guide query failed: HTTP ' + str(status))
    rows = json.loads(payload)
    require(isinstance(rows, list), 'Unexpected guide response representation')
    return rows


def exact_published(rows, guides):
    require(len(rows) == 8 and {r['id'] for r in rows} == EXPECTED_IDS, 'Expected exactly eight published Guides')
    expected = {g['id']: g for g in guides}
    for row in rows:
        guide = expected[row['id']]
        require(all(row[key] == guide[key] for key in FIELDS), 'Published guide metadata differs from final manifest')
        require(row['status'] == 'published' and bool(row['published_at']), 'Guide publication fields differ')


def verify(manifest, published):
    guides = manifest['guides']
    ids_endpoint = '/rest/v1/guides?select=' + SELECT + '&id=in.(' + ','.join(g['id'] for g in guides) + ')'
    # No cohort predicate: the normal per-game query must enforce cohort in RLS.
    game_endpoint = ('/rest/v1/guides?select=' + SELECT + '&game_id=eq.' + GAME
                     + '&status=eq.published&order=published_at.desc,id.asc')
    client = Client(manifest, 'Development Beta')
    try:
        require(client.base == BASE, 'Unexpected project endpoint')
        rows = read_rows(client, ids_endpoint)  # Deliberately has no status predicate.
        if published:
            exact_published(rows, guides)
            game_rows = read_rows(client, game_endpoint)
            exact_published(game_rows, guides)
        else:
            require(rows == [], 'Draft guide metadata is visible to Development Beta')
            game_rows = None
        anonymous = {}
        for name, endpoint in (('ids', ids_endpoint), ('per_game', game_endpoint)):
            status, _ = client.call(endpoint, anonymous=True)
            require(status in (401, 403), 'Anonymous Guides read was not denied')
            anonymous[name] = status

        probe_endpoint = '/rest/v1/guides?id=eq.' + PROBE_ID
        require(read_rows(client, probe_endpoint + '&select=id') == [], 'Write probe UUID is visible; refusing PATCH')
        patch_status, _ = client.call(probe_endpoint, method='PATCH',
            data=b'{"summary":"Permission probe for a nonexistent Guide."}')
        require(patch_status == 403, 'Authenticated Guides PATCH must be denied with HTTP 403')

        # Values have valid API types but are deliberately invalid for execution.
        # claim cannot create a run with this malformed hash; finish rejects null
        # arrays before looking up or changing a run even if EXECUTE was misgranted.
        probes = (
            ('claim_guide_crawl', {'p_token_hash': 'invalid-verification-probe'}),
            ('finish_guide_crawl', {'p_run_id': PROBE_ID, 'p_candidates': None, 'p_errors': None}),
        )
        rpc_results = []
        for name, arguments in probes:
            for is_anonymous in (False, True):
                status, _ = client.call('/rest/v1/rpc/' + name, method='POST',
                    data=json.dumps(arguments).encode(), anonymous=is_anonymous)
                require(status in (401, 403), 'Service-only crawler RPC access was not denied')
                rpc_results.append({'rpc': name, 'role': 'anon' if is_anonymous else 'authenticated', 'http': status})
    finally:
        client.close()
    print(json.dumps({'phase': 'published' if published else 'draft',
        'unfiltered_id_query_http': 200, 'visible_initial_guides': len(rows),
        'per_game_published_guides': len(game_rows) if game_rows is not None else None,
        'anonymous_reads': anonymous, 'nonexistent_uuid_patch_http': patch_status,
        'service_only_rpc_probes': rpc_results}, indent=2))


if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument('action', choices=('verify-draft', 'verify-published'))
        action = parser.parse_args().action
        checked = preflight()
        verify(checked, action == 'verify-published')
    except Exception as error:
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('Initial Guides verification stopped: ' + message, file=sys.stderr)
        sys.exit(1)
