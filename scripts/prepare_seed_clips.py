#!/usr/bin/env python3
"""Prepare seven reviewed Commons clips locally; performs no auth or uploads.

Uses only Python's standard library, macOS avconvert and Quick Look. All media
stays in a private cache outside Git. A separate review/import step is required.
"""
import argparse
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / '.planning/2026-11-03-supabase-backend/video-candidates-2026-11-04.json'
MANIFEST = ROOT / 'supabase/content/development-seed-clips-2026-11-04.json'
CACHE = Path('/Users/shangbao666/.codex/private/fl-tiya-ios/seed-clips-2026-11-04')
OWNER = '0a8b2ca1-9e56-4843-828c-07f560fabd2a'
PROJECT = 'gpstwmffctwqlcakmvgw'
GAME_IDS = ('supertuxkart', 'freedoom', 'bobs-game', 'guacamelee',
            'manifold-garden', 'fantastic-contraption', 'push-me-pull-you')
MAX_BYTES = 32 * 1024 * 1024
MAX_COVER_BYTES = 2 * 1024 * 1024


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def private_directory(path):
    if path.is_symlink():
        raise RuntimeError('Private media directory must not be a symlink')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)


def save_manifest(manifest):
    temporary = MANIFEST.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    os.replace(temporary, MANIFEST)


def download_source(clip, target):
    url = urllib.parse.urlsplit(clip['download_url'])
    if (url.scheme != 'https' or url.hostname != 'upload.wikimedia.org'
            or url.username or url.password or url.port or url.query or url.fragment
            or not url.path.startswith('/wikipedia/commons/transcoded/')
            or not url.path.endswith('.360p.mpeg4.mov')):
        raise RuntimeError('Download URL is outside the reviewed Commons scope')
    expected = clip['source_download_bytes']
    if not 0 < expected <= MAX_BYTES:
        raise RuntimeError('Source exceeds the byte limit')
    if target.exists():
        if target.is_symlink() or target.stat().st_size != expected:
            raise RuntimeError('Cached source identity or size mismatch')
        target.chmod(0o600)
        if clip.get('source_sha256') and sha256(target) != clip['source_sha256']:
            raise RuntimeError('Cached source hash changed')
        return
    opener = urllib.request.build_opener(NoRedirects())
    partial = target.with_suffix('.partial')
    request = urllib.request.Request(clip['download_url'],
        headers={'User-Agent': 'FLTiyaLocalMediaPreparation/1.0'})
    for attempt in range(3):
        try:
            with opener.open(request, timeout=35) as response:
                if response.status != 200 or response.headers.get_content_type() != 'video/quicktime':
                    raise RuntimeError('Unexpected source response')
                if int(response.headers.get('Content-Length', '-1')) != expected:
                    raise RuntimeError('Source Content-Length changed since review')
                received = 0
                started = time.monotonic()
                with partial.open('wb') as output:
                    partial.chmod(0o600)
                    while True:
                        chunk = response.read(min(256 * 1024, MAX_BYTES + 1 - received))
                        if not chunk:
                            break
                        received += len(chunk)
                        if received > MAX_BYTES or time.monotonic() - started > 120:
                            raise RuntimeError('Source transfer exceeded its bound')
                        output.write(chunk)
                if received != expected:
                    raise RuntimeError('Source bytes differ from the reviewed derivative')
                os.replace(partial, target)
                target.chmod(0o600)
                return
        except urllib.error.HTTPError as error:
            if error.code != 429 or attempt == 2:
                raise RuntimeError('Commons download failed: HTTP ' + str(error.code)) from None
            retry = error.headers.get('Retry-After')
            delay = 5 * (attempt + 1)
            if retry:
                try:
                    delay = float(retry)
                except ValueError:
                    retry_time = parsedate_to_datetime(retry)
                    delay = (retry_time - datetime.now(timezone.utc)).total_seconds()
            if not math.isfinite(delay) or delay > 60:
                raise RuntimeError('Commons requests a longer backoff; resume preparation later')
            delay = max(0, delay)
            print(clip['slug'], 'Commons HTTP 429; waiting', round(delay, 1), 'seconds', flush=True)
            time.sleep(delay)
        finally:
            if partial.exists():
                partial.unlink()


def atoms(data, begin=0, end=None):
    end = len(data) if end is None else end
    cursor = begin
    while cursor < end:
        if cursor + 8 > end:
            raise RuntimeError('Truncated MP4 atom header')
        size, kind = struct.unpack_from('>I4s', data, cursor)
        header = 8
        if size == 1:
            if cursor + 16 > end:
                raise RuntimeError('Truncated extended MP4 atom')
            size = struct.unpack_from('>Q', data, cursor + 8)[0]
            header = 16
        elif size == 0:
            size = end - cursor
        if size < header or cursor + size > end:
            raise RuntimeError('Invalid MP4 atom size')
        yield kind, cursor + header, cursor + size
        cursor += size


def child(data, atom, kind):
    return next((item for item in atoms(data, atom[1], atom[2]) if item[0] == kind), None)


def mp4_details(path):
    data = path.read_bytes()
    if not 0 < len(data) <= MAX_BYTES:
        raise RuntimeError('Prepared MP4 exceeds the byte limit')
    top = list(atoms(data))
    if not any(a[0] == b'ftyp' for a in top):
        raise RuntimeError('Missing MP4 file type')
    moov = next(a for a in top if a[0] == b'moov')
    for track in atoms(data, moov[1], moov[2]):
        if track[0] != b'trak':
            continue
        mdia = child(data, track, b'mdia')
        handler = child(data, mdia, b'hdlr') if mdia else None
        if not handler or data[handler[1] + 8:handler[1] + 12] != b'vide':
            continue
        tkhd = child(data, track, b'tkhd')
        width, height = struct.unpack_from('>II', data, tkhd[2] - 8)
        width, height = round(width / 65536), round(height / 65536)
        mdhd = child(data, mdia, b'mdhd')
        offset = mdhd[1]
        if data[offset] == 1:
            timescale = struct.unpack_from('>I', data, offset + 20)[0]
            duration = struct.unpack_from('>Q', data, offset + 24)[0]
        elif data[offset] == 0:
            timescale, duration = struct.unpack_from('>II', data, offset + 12)
        else:
            raise RuntimeError('Unsupported video media header')
        minf = child(data, mdia, b'minf')
        stbl = child(data, minf, b'stbl')
        stsd = child(data, stbl, b'stsd')
        codec = data[stsd[1] + 12:stsd[1] + 16]
        if codec != b'avc1' or not timescale or not 0 < width <= 640 or not 0 < height <= 480:
            raise RuntimeError('Prepared video is not the expected bounded H.264 output')
        return {'codec': 'avc1', 'dimensions': [width, height],
                'duration_seconds': round(duration / timescale, 3)}
    raise RuntimeError('No video track in prepared MP4')


def png_dimensions(path):
    data = path.read_bytes()
    if (not 0 < len(data) <= MAX_COVER_BYTES or data[:8] != b'\x89PNG\r\n\x1a\n'
            or data[12:16] != b'IHDR'):
        raise RuntimeError('Cover is not a bounded PNG')
    width, height = struct.unpack_from('>II', data, 16)
    if not 0 < width <= 640 or not 0 < height <= 640:
        raise RuntimeError('Cover dimensions exceed 640 pixels')
    return [width, height]


def manifest_from_research():
    research = json.loads(RESEARCH.read_text())
    if tuple(x['game_id'] for x in research['candidates']) != GAME_IDS:
        raise RuntimeError('Candidate registry changed')
    prior = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    if prior and (prior.get('project_ref') != PROJECT or prior.get('cohort') != 'development'):
        raise RuntimeError('Existing manifest is outside the preparation scope')
    prior_clips = {x['id']: x for x in prior.get('clips', [])}
    clips = []
    for source in research['candidates']:
        post_id = str(uuid.uuid5(uuid.NAMESPACE_URL, source['source_url']))
        if source['id'] != post_id or source['license'] not in ('CC BY-SA 3.0', 'CC BY-SA 4.0'):
            raise RuntimeError('Source identity or selected license changed')
        start = source.get('clip_start_seconds', 0)
        duration = min(20, source['source_duration_seconds'] - start)
        if start < 0 or duration <= 0:
            raise RuntimeError('Selected source segment is outside the video')
        segment = ('Seconds ' + str(start).removesuffix('.0') + '-'
                   + str(start + duration).removesuffix('.0')) if start else (
                   'First ' + str(duration).removesuffix('.0') + 's')
        caption = (source['title'] + '\nVideo: ' + source['creator'] + '.\n'
            + source['source_url'] + '\n' + source['license'] + ': ' + source['license_url']
            + '\n' + segment
            + '; H.264 MP4; cover extracted. Derivatives: ' + source['license'] + '.')
        if source['game_id'] == 'freedoom':
            caption += '\nGame artwork: Freedoom contributors, BSD-3-Clause.'
        elif source['game_id'] == 'supertuxkart':
            caption += '\nGame assets: mixed open licenses; see source credits.'
        if len(caption) > 500 or not caption.isascii():
            raise RuntimeError('Caption must be English and at most 500 characters')
        clip = {key: source[key] for key in ('title', 'creator', 'game_id', 'game_name',
            'game_artwork_creator', 'source_title', 'source_url', 'source_permanent_url',
            'download_url', 'license', 'license_url', 'permission_evidence', 'game_artwork_license')}
        for key in ('game_artwork_license_url', 'vrt_ticket', 'vrt_ticket_url', 'attribution_note'):
            if key in source:
                clip[key] = source[key]
        clip.update({'id': post_id, 'slug': source['game_id'] + '-seed', 'owner_id': OWNER,
            'source_download_bytes': source['download_bytes'], 'source_duration_seconds': source['source_duration_seconds'],
            'clip_start_seconds': start, 'requested_duration_seconds': duration,
            'video_path': OWNER + '/' + post_id + '/video.mp4',
            'thumbnail_path': OWNER + '/' + post_id + '/cover.png', 'caption': caption,
            'modifications': segment + '; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.',
            'thumbnail_modifications': 'Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: ' + source['license'] + '.',
            'local_cache_directory': str(CACHE / post_id)})
        previous = prior_clips.get(post_id, {})
        for key in ('source_sha256', 'media_bytes', 'media_sha256', 'media_type', 'media_codec',
                    'duration_seconds', 'media_dimensions', 'thumbnail_bytes', 'thumbnail_sha256',
                    'thumbnail_dimensions', 'thumbnail_media_type', 'preparation_status'):
            if key in previous:
                clip[key] = previous[key]
        clips.append(clip)
    return {'project_ref': PROJECT, 'cohort': 'development', 'license_checked_on': '2026-11-04',
        'scope': 'Local preparation only; awaiting root media review and authorized import.',
        'cache_directory': str(CACHE), 'clips': clips}


def prepare(manifest):
    private_directory(CACHE)
    for clip in manifest['clips']:
        folder = CACHE / clip['id']
        private_directory(folder)
        original, target, cover = (folder / name for name in ('source.mov', 'video.mp4', 'cover.png'))
        print(clip['slug'], 'preparing', flush=True)
        download_source(clip, original)
        clip['source_sha256'] = sha256(original)
        if not target.exists():
            subprocess.run(['/usr/bin/avconvert', '--source', str(original), '--preset',
                'Preset640x480', '--output', str(target), '--start', str(clip['clip_start_seconds']), '--duration',
                str(clip['requested_duration_seconds'])], check=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=90)
        if target.is_symlink():
            raise RuntimeError('Prepared media must not be a symlink')
        target.chmod(0o600)
        details = mp4_details(target)
        if not 0 < details['duration_seconds'] <= clip['requested_duration_seconds'] + 0.1:
            raise RuntimeError('Prepared video duration is outside the selected segment')
        if clip.get('media_sha256') and sha256(target) != clip['media_sha256']:
            raise RuntimeError('Existing prepared video hash changed')
        if not cover.exists():
            quicklook = folder / 'quicklook'
            private_directory(quicklook)
            subprocess.run(['/usr/bin/qlmanage', '-t', '-s', '640', '-o', str(quicklook),
                str(target)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
            generated = quicklook / 'video.mp4.png'
            png_dimensions(generated)
            os.replace(generated, cover)
            quicklook.rmdir()
        if cover.is_symlink():
            raise RuntimeError('Prepared cover must not be a symlink')
        cover.chmod(0o600)
        dimensions = png_dimensions(cover)
        if clip.get('thumbnail_sha256') and sha256(cover) != clip['thumbnail_sha256']:
            raise RuntimeError('Existing prepared cover hash changed')
        clip.update({'media_bytes': target.stat().st_size, 'media_sha256': sha256(target),
            'media_type': 'video/mp4', 'media_codec': details['codec'],
            'duration_seconds': details['duration_seconds'], 'media_dimensions': details['dimensions'],
            'thumbnail_bytes': cover.stat().st_size, 'thumbnail_sha256': sha256(cover),
            'thumbnail_dimensions': dimensions, 'thumbnail_media_type': 'image/png',
            'preparation_status': 'prepared-awaiting-visual-review'})
        save_manifest(manifest)
        print(clip['slug'], 'prepared', clip['media_bytes'], 'MP4 bytes;',
            clip['thumbnail_bytes'], 'PNG bytes;', clip['duration_seconds'], 'seconds', flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare'])
    parser.parse_args()
    output = manifest_from_research()
    save_manifest(output)
    prepare(output)
