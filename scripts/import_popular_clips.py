#!/usr/bin/env python3
"""Review-first development import for two licensed popular-game clips.

`render-pending` only writes inert SQL. `render-approve`, upload and HTTP
verification require all local source/video/cover bytes plus explicit visual
review in the manifest. The SQL is never executed by this helper. Run pending
SQL, upload, verify-pending, then review and execute approval SQL separately.
"""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import sys

sys.dont_write_bytecode = True
from import_development_clips import Client, digest, request
from prepare_popular_clips import CACHE, EXPECTED, MANIFEST, read_manifest

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'supabase/content'
PENDING = CONTENT / 'development-popular-clips-2026-11-04-pending.sql'
APPROVE = CONTENT / 'development-popular-clips-2026-11-04-approve.sql'
OWNER = '0a8b2ca1-9e56-4843-828c-07f560fabd2a'
PROJECT = 'gpstwmffctwqlcakmvgw'
BASE = 'https://' + PROJECT + '.supabase.co'
MAX_BYTES = 32 * 1024 * 1024
DENIED = (400, 401, 403, 404)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def local_file(path, byte_count, checksum, limit):
    require(path.is_file() and not path.is_symlink(), 'Expected regular cached file')
    require(stat.S_IMODE(path.stat().st_mode) == 0o600, 'Cached file permission mismatch')
    require(0 < byte_count <= limit and path.stat().st_size == byte_count,
            'Cached file byte count mismatch')
    data = path.read_bytes()
    require(len(data) == byte_count and digest(data) == checksum,
            'Cached file SHA-256 mismatch')
    return data


def preflight(manifest):
    require(not CACHE.is_symlink() and CACHE.is_dir() and
            stat.S_IMODE(CACHE.stat().st_mode) == 0o700,
            'Private cache directory is unavailable')
    uploads = {}
    for clip in manifest['clips']:
        require(clip['visual_review'] == 'accepted' and
                clip['preparation_status'] == 'prepared-awaiting-visual-review',
                'Decoded video and cover have not been explicitly reviewed')
        require(clip['media_type'] == 'video/mp4' and clip['media_codec'] == 'avc1' and
                clip['thumbnail_media_type'] == 'image/png', 'Prepared media type mismatch')
        require(0 < clip['duration_seconds'] <= clip['requested_duration_seconds'] + 0.1 and
                0 < clip['media_dimensions'][0] <= 640 and
                0 < clip['media_dimensions'][1] <= 480 and
                0 < clip['thumbnail_dimensions'][0] <= 640 and
                0 < clip['thumbnail_dimensions'][1] <= 640,
                'Prepared media geometry mismatch')
        folder = CACHE / clip['id']
        require(str(folder) == clip['local_cache_directory'] and folder.is_dir() and
                not folder.is_symlink() and stat.S_IMODE(folder.stat().st_mode) == 0o700,
                'Private clip folder mismatch')
        local_file(folder / 'source.mov', clip['source_download_bytes'],
                   clip['source_sha256'], MAX_BYTES)
        for name, path_key, bytes_key, sha_key, limit, mime in (
                ('video.mp4', 'video_path', 'media_bytes', 'media_sha256', MAX_BYTES, 'video/mp4'),
                ('cover.png', 'thumbnail_path', 'thumbnail_bytes', 'thumbnail_sha256',
                 2 * 1024 * 1024, 'image/png')):
            storage_path = OWNER + '/' + clip['id'] + '/' + name
            require(clip[path_key] == storage_path and storage_path not in uploads,
                    'Immutable media path mismatch')
            uploads[storage_path] = (local_file(folder / name, clip[bytes_key],
                clip[sha_key], limit), mime)
    require(len(uploads) == 4, 'Expected four reviewed media objects')
    return uploads


def sql_header(manifest):
    manifest_sha = hashlib.sha256(MANIFEST.read_bytes()).hexdigest()
    return ('-- FL-Tiya development cohort, project ' + PROJECT + '.\n'
            '-- Frozen manifest SHA-256: ' + manifest_sha + '. No credentials.\n'
            '-- Generated SQL is not evidence of completed media review or upload.\n'
            '-- Execute only after verifying the intended project and review stage.\n'
            'begin;\nset local lock_timeout = \'5s\';\n'
            'set local statement_timeout = \'30s\';\n')


def render_pending(manifest):
    require(len(manifest['clips']) == 2 and
            {c['id']: c['game_id'] for c in manifest['clips']} == EXPECTED,
            'Pending source registry mismatch')
    rows = []
    for clip in manifest['clips']:
        rows.append('(' + ', '.join(quote(str(clip[key])) for key in
            ('id', 'owner_id', 'game_id', 'game_name', 'caption',
             'video_path', 'thumbnail_path')) + ')')
    ids = ', '.join(quote(c['id']) + '::uuid' for c in manifest['clips'])
    sql = sql_header(manifest) + """
create temporary table fltiya_popular_expected (
    id uuid primary key, owner_id uuid not null, game_id text not null,
    game_name text not null, caption text not null,
    video_path text not null unique, thumbnail_path text not null unique
) on commit drop;
insert into pg_temp.fltiya_popular_expected values
""" + ',\n'.join(rows) + ";\n" + """
lock table public.video_posts in share row exclusive mode;
do $pending$
begin
    if (select count(*) from pg_temp.fltiya_popular_expected) <> 2 then
        raise exception 'Expected two reviewed popular-game sources';
    end if;
    perform 1 from private.accounts
    where user_id='""" + OWNER + """'::uuid and cohort='development' and state='active'
    for share;
    if not found or not private.account_is_eligible('""" + OWNER + """'::uuid) then
        raise exception 'Expected eligible development Alpha owner';
    end if;
    if not exists (select 1 from storage.buckets where id='clips' and public=false) then
        raise exception 'Expected private clips bucket';
    end if;
    if exists (select 1 from public.games g join pg_temp.fltiya_popular_expected e
               on e.game_id=g.id where g.name is distinct from e.game_name) then
        raise exception 'Existing game name differs from the source registry';
    end if;
    if exists (select 1 from public.video_posts v
               where v.id in (select id from pg_temp.fltiya_popular_expected)
                  or v.video_path in (select video_path from pg_temp.fltiya_popular_expected
                                      union all select thumbnail_path from pg_temp.fltiya_popular_expected)
                  or v.thumbnail_path in (select video_path from pg_temp.fltiya_popular_expected
                                          union all select thumbnail_path from pg_temp.fltiya_popular_expected)) then
        raise exception 'Popular clip id or immutable path already exists';
    end if;
    if exists (select 1 from storage.objects o where o.bucket_id='clips'
               and o.name in (select video_path from pg_temp.fltiya_popular_expected
                              union all select thumbnail_path from pg_temp.fltiya_popular_expected)) then
        raise exception 'Storage path already exists before pending insertion';
    end if;
end;
$pending$;
insert into public.games(id,name)
select game_id,game_name from pg_temp.fltiya_popular_expected on conflict(id) do nothing;
insert into public.video_posts(id,owner_id,game_id,caption,video_path,thumbnail_path,status)
select id,owner_id,game_id,caption,video_path,thumbnail_path,'pending'
from pg_temp.fltiya_popular_expected;
commit;
select id,status from public.video_posts where id in (""" + ids + ") order by id;\n"
    PENDING.write_text(sql)
    print(PENDING)


def render_approve(manifest, uploads):
    require(len(uploads) == 4, 'Approval needs four locally verified files')
    rows = []
    objects = []
    for clip in manifest['clips']:
        notes = {key: clip[key] for key in ('source_url', 'source_permanent_url',
            'original_publisher_url', 'creator', 'source_date', 'content_kind',
            'license', 'license_url', 'permission_evidence', 'source_sha256',
            'media_sha256', 'thumbnail_sha256')}
        start = clip['clip_start_seconds']
        duration = clip['requested_duration_seconds']
        segment = (f'First {duration:g} seconds' if start == 0 else
                   f'Seconds {start:g}-{start + duration:g}')
        notes['modifications'] = (
            segment + '; Commons MOV transcode to H.264 MP4; Quick Look frame cover.')
        notes['review_limits'] = ('Local decoded video/cover visual review and authenticated '
            'byte/hash readback must be completed separately; SQL checks owner/MIME/size, not hashes.')
        row = [clip['id'], clip['owner_id'], clip['game_id'], clip['game_name'],
               clip['caption'], clip['video_path'], clip['thumbnail_path'],
               json.dumps(notes, ensure_ascii=False, separators=(',', ':'))]
        rows.append('(' + ', '.join(quote(str(v)) for v in row) + ')')
        for key, bytes_key, mime in (('video_path', 'media_bytes', 'video/mp4'),
                                    ('thumbnail_path', 'thumbnail_bytes', 'image/png')):
            objects.append('(' + ', '.join((quote(clip[key]), quote(clip['owner_id']),
                str(clip[bytes_key]), quote(mime))) + ')')
    ids = ', '.join(quote(c['id']) + '::uuid' for c in manifest['clips'])
    sql = sql_header(manifest) + """
create temporary table fltiya_popular_expected (
    id uuid primary key, owner_id uuid not null, game_id text not null,
    game_name text not null, caption text not null,
    video_path text not null unique, thumbnail_path text not null unique,
    review_notes text not null
) on commit drop;
insert into pg_temp.fltiya_popular_expected values
""" + ',\n'.join(rows) + ";\n" + """
create temporary table fltiya_popular_objects (
    path text primary key, owner_id uuid not null, bytes bigint not null, mime text not null
) on commit drop;
insert into pg_temp.fltiya_popular_objects values
""" + ',\n'.join(objects) + ";\n" + """
do $approve$
declare matches integer; changed integer;
begin
    if (select count(*) from pg_temp.fltiya_popular_expected) <> 2
       or (select count(*) from pg_temp.fltiya_popular_objects) <> 4 then
        raise exception 'Expected two reviewed posts and four media objects';
    end if;
    perform 1 from private.accounts
    where user_id='""" + OWNER + """'::uuid and cohort='development' and state='active'
    for share;
    if not found or not private.account_is_eligible('""" + OWNER + """'::uuid) then
        raise exception 'Expected eligible development Alpha owner';
    end if;
    if not exists (select 1 from storage.buckets where id='clips' and public=false) then
        raise exception 'Expected private clips bucket';
    end if;
    perform 1 from public.video_posts v join pg_temp.fltiya_popular_expected e on e.id=v.id
    for update of v;
    select count(*) into matches from public.video_posts v
    join pg_temp.fltiya_popular_expected e on e.id=v.id
    join public.games g on g.id=e.game_id
    where v.owner_id=e.owner_id and v.game_id=e.game_id and v.caption=e.caption
      and v.video_path=e.video_path and v.thumbnail_path=e.thumbnail_path
      and v.status='pending' and v.approved_at is null and g.name=e.game_name;
    if matches <> 2 then raise exception 'Expected two exact pending posts'; end if;
    if exists (select 1 from private.video_reviews r
               join pg_temp.fltiya_popular_expected e on e.id=r.post_id) then
        raise exception 'Popular posts already have review records';
    end if;
    perform 1 from storage.objects o join pg_temp.fltiya_popular_objects e
    on o.bucket_id='clips' and o.name=e.path for share of o;
    select count(*) into matches from storage.objects o
    join pg_temp.fltiya_popular_objects e on o.bucket_id='clips' and o.name=e.path
    where o.owner_id=e.owner_id::text and o.metadata->>'mimetype'=e.mime
      and (o.metadata->>'size')::bigint=e.bytes;
    if matches <> 4 then raise exception 'Expected four exact owner/MIME/size objects'; end if;
    insert into private.video_reviews(post_id,decision,reviewer_reference,notes)
    select id,'approved','licensed-development-popular-import-2026-11-04',review_notes
    from pg_temp.fltiya_popular_expected;
    get diagnostics changed = row_count;
    if changed <> 2 then raise exception 'Expected two review records'; end if;
    update public.video_posts v set status='approved',approved_at=statement_timestamp()
    from pg_temp.fltiya_popular_expected e
    where v.id=e.id and v.owner_id=e.owner_id and v.status='pending';
    get diagnostics changed = row_count;
    if changed <> 2 then raise exception 'Expected two approved posts'; end if;
end;
$approve$;
commit;
select id,status from public.video_posts where id in (""" + ids + ") order by id;\n"
    APPROVE.write_text(sql)
    print(APPROVE)


def metadata(client, clips):
    ids = ','.join(c['id'] for c in clips)
    status, body = client.call('/rest/v1/video_posts?select=id,owner_id,status,game_id,'
        'caption,video_path,thumbnail_path,game:games(id,name)&id=in.(' + ids + ')')
    require(status == 200, 'Unfiltered metadata query failed')
    rows = json.loads(body)
    require(isinstance(rows, list), 'Unexpected metadata format')
    return rows


def exact_rows(rows, clips, status):
    require(len(rows) == 2 and {r['id'] for r in rows} == set(EXPECTED),
            'Expected two exact popular posts')
    expected = {c['id']: c for c in clips}
    for row in rows:
        clip = expected[row['id']]
        require(row['status'] == status and
                all(row[k] == clip[k] for k in
                    ('owner_id', 'game_id', 'caption', 'video_path', 'thumbnail_path')) and
                row['game'] == {'id': clip['game_id'], 'name': clip['game_name']},
                'Hosted metadata differs from the frozen manifest')


def upload(manifest, uploads):
    client = Client(manifest, 'Development Alpha')
    try:
        require(client.base == BASE and client.user_id == OWNER, 'Development owner mismatch')
        exact_rows(metadata(client, manifest['clips']), manifest['clips'], 'pending')
        for path, (data, mime) in uploads.items():
            endpoint = '/storage/v1/object/clips/' + path
            status, existing = client.call(endpoint)
            if status == 200:
                require(len(existing) == len(data) and digest(existing) == digest(data),
                        'Immutable object collision')
            else:
                require(status in (400, 404), 'Owner media lookup failed')
                headers = {'apikey': client.key, 'Authorization': 'Bearer ' + client.token,
                           'Content-Type': mime, 'x-upsert': 'false'}
                status, _ = request(BASE + endpoint, headers=headers, data=data, method='POST')
                require(status in (200, 400, 409), 'Immutable media upload failed')
            status, readback = client.call(endpoint)
            require(status == 200 and len(readback) == len(data) and
                    digest(readback) == digest(data), 'Authenticated media readback mismatch')
            print(path, 'SHA-256 readback verified', flush=True)
    finally:
        client.close()


def verify(manifest, uploads, approved):
    client = Client(manifest, 'Development Beta')
    try:
        require(client.base == BASE and client.user_id != OWNER, 'Expected development peer')
        rows = metadata(client, manifest['clips'])
        if approved:
            exact_rows(rows, manifest['clips'], 'approved')
        else:
            require(rows == [], 'Pending metadata is visible to peer')
        anon_status, _ = client.call('/rest/v1/video_posts?select=id', anonymous=True)
        require(anon_status in (400, 401, 403), 'Anonymous feed was readable')
        for path, (data, _) in uploads.items():
            endpoint = '/storage/v1/object/clips/' + path
            peer_status, body = client.call(endpoint)
            if approved:
                require(peer_status == 200 and len(body) == len(data) and
                        digest(body) == digest(data), 'Approved peer media differs')
            else:
                require(peer_status in DENIED, 'Pending media is visible to peer')
            anonymous, _ = client.call(endpoint, anonymous=True)
            public, _ = client.call('/storage/v1/object/public/clips/' + path, anonymous=True)
            signed, _ = client.call('/storage/v1/object/sign/clips/' + path,
                                    method='POST', data=b'{"expiresIn":60}')
            require(all(code in DENIED for code in (anonymous, public, signed)),
                    'Private media access boundary failed')
            print(json.dumps({'path': path, 'peer_http': peer_status,
                'anonymous_http': anonymous, 'public_http': public,
                'sign_http': signed}), flush=True)
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('render-pending', 'render-approve',
        'upload', 'verify-pending', 'verify-approved'))
    action = parser.parse_args().action
    manifest = read_manifest()
    if action == 'render-pending':
        render_pending(manifest)
        return
    uploads = preflight(manifest)
    if action == 'render-approve':
        render_pending(manifest)  # Keep both SQL files bound to one frozen manifest.
        render_approve(manifest, uploads)
    elif action == 'upload':
        upload(manifest, uploads)
    else:
        verify(manifest, uploads, action == 'verify-approved')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Fixed output avoids logging credentials, responses, or media bytes.
        print('Popular clip import stopped: ' +
              (str(error) if isinstance(error, RuntimeError) else type(error).__name__),
              file=sys.stderr)
        raise SystemExit(1)
