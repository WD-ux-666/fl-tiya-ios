#!/usr/bin/env python3
"""Prepare the two source-reviewed popular-game clips in a private local cache.

No authentication, database change, upload, or approval occurs here. The source
and output hashes are frozen only after a successful bounded download/convert.
The resulting videos and covers still require visual review.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from prepare_seed_clips import NoRedirects, mp4_details, png_dimensions, private_directory

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'supabase/content/development-popular-clips-2026-11-04.json'
CACHE = Path('/Users/shangbao666/.codex/private/fl-tiya-ios/popular-clips-2026-11-04')
MAX_BYTES = 32 * 1024 * 1024
MAX_COVER_BYTES = 2 * 1024 * 1024
EXPECTED = {
    '084d6071-d274-52b3-8f24-62b731a741cb': 'minecraft',
    '86916319-1668-569a-8fd0-8ff991d483c4': 'pubg-mobile',
}
REVIEWED_URLS = {
    '084d6071-d274-52b3-8f24-62b731a741cb': (
        'https://commons.wikimedia.org/wiki/File:Minecraft_Gameplay.webm',
        'https://upload.wikimedia.org/wikipedia/commons/transcoded/0/04/Minecraft_Gameplay.webm/Minecraft_Gameplay.webm.360p.mpeg4.mov'),
    '86916319-1668-569a-8fd0-8ff991d483c4': (
        'https://commons.wikimedia.org/wiki/File:PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm',
        'https://upload.wikimedia.org/wikipedia/commons/transcoded/c/c8/PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm/PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm.360p.mpeg4.mov'),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_manifest():
    manifest = json.loads(MANIFEST.read_text())
    require(manifest['project_ref'] == 'gpstwmffctwqlcakmvgw' and
            manifest['cohort'] == 'development', 'Wrong project or cohort')
    clips = manifest['clips']
    require(len(clips) == 2 and {c['id']: c['game_id'] for c in clips} == EXPECTED,
            'Popular clip registry changed')
    for clip in clips:
        require(str(uuid.uuid5(uuid.NAMESPACE_URL, clip['source_url'])) == clip['id'],
                'Source identity changed')
        require((clip['source_url'], clip['download_url']) == REVIEWED_URLS[clip['id']],
                'Reviewed source or derivative URL changed')
        require(clip['license'] == 'CC BY 3.0' and
                clip['license_url'] == 'https://creativecommons.org/licenses/by/3.0/',
                'Reviewed license changed')
        require(clip['owner_id'] == '0a8b2ca1-9e56-4843-828c-07f560fabd2a' and
                clip['video_path'] == clip['owner_id'] + '/' + clip['id'] + '/video.mp4' and
                clip['thumbnail_path'] == clip['owner_id'] + '/' + clip['id'] + '/cover.png',
                'Reviewed owner or immutable storage path changed')
        require(0 <= clip['clip_start_seconds'] and 0 < clip['requested_duration_seconds'] <= 20 and
                clip['clip_start_seconds'] + clip['requested_duration_seconds'] <= clip['source_duration_seconds'],
                'Requested segment is outside the source')
        require(len(clip['caption']) <= 500, 'Caption exceeds the post limit')
        source = urllib.parse.urlsplit(clip['download_url'])
        expected_suffix = '/' + clip['source_title'].replace(' ', '_').replace("'", '%27') + '.360p.mpeg4.mov'
        require(source.scheme == 'https' and source.netloc == 'upload.wikimedia.org' and
                source.path.startswith('/wikipedia/commons/transcoded/') and
                source.path.endswith(expected_suffix) and not source.query and not source.fragment,
                'Download is outside the reviewed Commons transcode')
    return manifest


def save_manifest(manifest):
    temporary = MANIFEST.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    os.replace(temporary, MANIFEST)


def download(clip, path):
    if path.exists():
        require(not path.is_symlink() and path.is_file() and
                0 < path.stat().st_size <= MAX_BYTES, 'Cached source is invalid')
        if 'source_download_bytes' in clip:
            require(path.stat().st_size == clip['source_download_bytes'] and
                    digest(path) == clip['source_sha256'], 'Frozen source bytes changed')
        path.chmod(0o600)
        return
    request = urllib.request.Request(clip['download_url'],
        headers={'User-Agent': 'FLTiyaPopularMediaPreparation/1.0'})
    partial = path.with_suffix('.partial')
    try:
        with urllib.request.build_opener(NoRedirects()).open(request, timeout=35) as response:
            require(response.status == 200 and
                    response.headers.get_content_type() == 'video/quicktime',
                    'Unexpected source response')
            announced = int(response.headers.get('Content-Length', '0'))
            require(0 < announced <= MAX_BYTES, 'Source size is missing or exceeds the bound')
            with partial.open('wb') as output:
                partial.chmod(0o600)
                count = 0
                started = time.monotonic()
                while count < announced:
                    require(time.monotonic() - started <= 120,
                            'Source transfer exceeded the time bound')
                    chunk = response.read(min(256 * 1024, announced - count))
                    require(bool(chunk), 'Source transfer ended early')
                    count += len(chunk)
                    output.write(chunk)
                require(not response.read(1), 'Source exceeded its announced size')
            require(partial.stat().st_size == announced, 'Source byte count changed')
        os.replace(partial, path)
    finally:
        if partial.exists():
            partial.unlink()
    clip['source_download_bytes'] = path.stat().st_size
    clip['source_sha256'] = digest(path)


def prepare():
    manifest = read_manifest()
    private_directory(CACHE)
    for clip in manifest['clips']:
        folder = CACHE / clip['id']
        private_directory(folder)
        source, media, cover = (folder / name for name in ('source.mov', 'video.mp4', 'cover.png'))
        download(clip, source)
        if not media.exists():
            subprocess.run(['/usr/bin/avconvert', '--source', str(source), '--preset',
                'Preset640x480', '--output', str(media), '--start', str(clip['clip_start_seconds']),
                '--duration', str(clip['requested_duration_seconds'])], check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
        require(not media.is_symlink(), 'Prepared video is a symlink')
        media.chmod(0o600)
        details = mp4_details(media)
        require(0 < details['duration_seconds'] <= clip['requested_duration_seconds'] + 0.1,
                'Prepared duration exceeds the selected segment')
        if clip.get('media_sha256'):
            require(digest(media) == clip['media_sha256'], 'Frozen MP4 bytes changed')
        if not cover.exists():
            quicklook = folder / 'quicklook'
            private_directory(quicklook)
            subprocess.run(['/usr/bin/qlmanage', '-t', '-s', '640', '-o', str(quicklook),
                str(media)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45)
            generated = quicklook / 'video.mp4.png'
            png_dimensions(generated)
            os.replace(generated, cover)
            quicklook.rmdir()
        require(not cover.is_symlink(), 'Prepared cover is a symlink')
        cover.chmod(0o600)
        require(0 < cover.stat().st_size <= MAX_COVER_BYTES, 'Cover exceeds the byte limit')
        dimensions = png_dimensions(cover)
        if clip.get('thumbnail_sha256'):
            require(digest(cover) == clip['thumbnail_sha256'], 'Frozen cover bytes changed')
        clip.update({'source_download_bytes': source.stat().st_size,
            'source_sha256': digest(source), 'media_bytes': media.stat().st_size,
            'media_sha256': digest(media), 'media_type': 'video/mp4',
            'media_codec': details['codec'], 'duration_seconds': details['duration_seconds'],
            'media_dimensions': details['dimensions'], 'thumbnail_bytes': cover.stat().st_size,
            'thumbnail_sha256': digest(cover), 'thumbnail_dimensions': dimensions,
            'thumbnail_media_type': 'image/png', 'local_cache_directory': str(folder),
            'preparation_status': 'prepared-awaiting-visual-review'})
        save_manifest(manifest)
        print(clip['slug'], 'prepared; review', media, cover, flush=True)


if __name__ == '__main__':
    os.umask(0o077)
    try:
        prepare()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError,
            urllib.error.URLError) as error:
        # Never include response bodies or inherited environment in output.
        print('Popular clip preparation stopped:', type(error).__name__)
        raise SystemExit(1)
