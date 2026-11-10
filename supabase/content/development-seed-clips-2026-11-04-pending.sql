-- Project: gpstwmffctwqlcakmvgw; development cohort only.
-- Generated from the reviewed local seed manifest, SHA-256: b270758217529f78983f8126b1a62f16322229bf911c74ba18f2efb08e66d83d.
-- Never execute against another project. No credentials or service keys are embedded.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temporary table fltiya_seed_expected (
    id uuid primary key,
    owner_id uuid not null,
    game_id text not null,
    game_name text not null,
    caption text not null,
    video_path text not null unique,
    thumbnail_path text not null unique,
    video_bytes bigint not null,
    cover_bytes bigint not null,
    review_notes text not null
) on commit drop;

insert into pg_temp.fltiya_seed_expected values
(
    '0266cd87-d7a3-53a6-8a08-6f454c48a6a5'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'supertuxkart',
    'SuperTuxKart',
    'SuperTuxKart - Kart Racing Benchmark
Video: SuperTux Kart-Autoren.
https://commons.wikimedia.org/wiki/File:Benchmark_SuperTux_Kart_Base_Profile_2025.07.04_-_10.19.10.02.webm
CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
Seconds 30-50; H.264 MP4; cover extracted. Derivatives: CC BY-SA 4.0.
Game assets: mixed open licenses; see source credits.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/0266cd87-d7a3-53a6-8a08-6f454c48a6a5/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/0266cd87-d7a3-53a6-8a08-6f454c48a6a5/cover.png',
    9783747,
    333605,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Benchmark_SuperTux_Kart_Base_Profile_2025.07.04_-_10.19.10.02.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1100308893","creator":"SuperTux Kart-Autoren","game_artwork_creator":"SuperTuxKart contributors","license":"CC BY-SA 4.0","license_url":"https://creativecommons.org/licenses/by-sa/4.0/","permission_evidence":"File author field is SuperTux Kart-Autoren. File declares both GPL and CC BY-SA 4.0; embedded credits and asset licenses are present. Uploader category credits video creation to PantheraLeo1359531.","game_artwork_license":"Mixed open licenses, including CC BY-SA 3.0/4.0, CC0 and GPL; preserve the linked file credits and asset license information.","source_sha256":"39e219207d8bb379cfc507e04583f7e336dc2ddfbbe71b1b0835be37398b05a7","media_sha256":"dcc9f0a87bf68831c3f50c53a8685e2832b57aef3f10af5b1e846e68b68d18f5","thumbnail_sha256":"2917e07b52472df42116d3bb9a60c9fa3caea0d04a782d7397409992d859c46a","modifications":"Seconds 30-50 of the source; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 4.0.","duration_seconds":20.0,"game_artwork_license_url":"https://supertuxkart.net/Licensing","attribution_note":"Use the exact file author credit SuperTux Kart-Autoren; identify PantheraLeo1359531 as uploader/recording contributor separately. Do not describe every game asset as CC BY-SA 4.0.","clip_start_seconds":30,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes.","artwork_notice_requirement":"Preserve the source file credits and its mixed asset license information; do not represent every game asset as CC BY-SA 4.0."}'
),
(
    'df55c5a2-7441-54fa-acd8-8429d331bda9'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'freedoom',
    'Freedoom',
    'Freedoom - First-Level Action
Video: CapoFantasma97.
https://commons.wikimedia.org/wiki/File:Freedoom_-_Short_gameplay.webm
CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
First 20s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 4.0.
Game artwork: Freedoom contributors, BSD-3-Clause.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/df55c5a2-7441-54fa-acd8-8429d331bda9/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/df55c5a2-7441-54fa-acd8-8429d331bda9/cover.png',
    9718229,
    214150,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Freedoom_-_Short_gameplay.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1261285429","creator":"CapoFantasma97","game_artwork_creator":"Contributors to the Freedoom project","license":"CC BY-SA 4.0","license_url":"https://creativecommons.org/licenses/by-sa/4.0/","permission_evidence":"Own recording by CapoFantasma97. The file separately labels the video CC BY-SA 4.0 and the game artwork BSD.","game_artwork_license":"BSD-3-Clause artwork; game engine GPL-2.0. Retain the Freedoom copyright notice, BSD conditions and disclaimer with distribution documentation.","source_sha256":"d05d6715c9224ce752c94c9e566a86a60ebc41a0ba66e3afb3a445a0d550837a","media_sha256":"1f84e0a62b8b1d933abbea8194e6736774880d73661a5d539975964100bd14ab","thumbnail_sha256":"ea91072220d295a376c6a3577930cb4e5401680b0ad28ac616cae6bccd1891f0","modifications":"First 20 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 4.0.","duration_seconds":20.0,"game_artwork_license_url":"https://github.com/freedoom/freedoom/blob/master/COPYING.adoc","clip_start_seconds":0,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes.","artwork_notice_requirement":"Root must provide the Freedoom BSD copyright notice, conditions and disclaimer in readable accompanying credits."}'
),
(
    'efaae809-9e62-5ddb-96bc-eebbe47e2747'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'bobs-game',
    'Bob''s Game',
    'Bob''s Game - Puzzle Match
Video: Bobsgame.
https://commons.wikimedia.org/wiki/File:Bob%27s_game_puzzle_gameplay.webm
CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
First 20s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 4.0.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/efaae809-9e62-5ddb-96bc-eebbe47e2747/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/efaae809-9e62-5ddb-96bc-eebbe47e2747/cover.png',
    6891650,
    257728,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Bob%27s_game_puzzle_gameplay.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=960991149","creator":"Bobsgame","game_artwork_creator":"Bobsgame","license":"CC BY-SA 4.0","license_url":"https://creativecommons.org/licenses/by-sa/4.0/","permission_evidence":"Own work by Bobsgame; file records confirmation of author identity in Wikimedia ticket 2017011910017897.","game_artwork_license":"CC BY-SA 4.0 for this developer-authored footage; no blanket license to other game assets inferred.","source_sha256":"cef5cd009f0055c01945226c7597ab5a9744b7c2e78e86dc2888a0f4d6cafdb4","media_sha256":"40d52976e9d13198a826f75395a38387e46665474f7de8888bac718217168634","thumbnail_sha256":"31f791d32ebd9fea90e1b067c4418a0a5642f52a8fd7854588fde67f23281fbb","modifications":"First 20 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 4.0.","duration_seconds":20.0,"vrt_ticket":"2017011910017897","clip_start_seconds":0,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes."}'
),
(
    '6920e768-4d0a-5af1-a003-10ea2eeca518'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'guacamelee',
    'Guacamelee! Super Turbo Championship Edition',
    'Guacamelee! - Combat and Platforming
Video: DrinkBox Studios.
https://commons.wikimedia.org/wiki/File:Guacamelee%21_STCE_B-roll_gameplay.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 3.0.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/6920e768-4d0a-5af1-a003-10ea2eeca518/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/6920e768-4d0a-5af1-a003-10ea2eeca518/cover.png',
    9482486,
    337831,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Guacamelee%21_STCE_B-roll_gameplay.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1286483321","creator":"DrinkBox Studios","game_artwork_creator":"DrinkBox Studios","license":"CC BY-SA 3.0","license_url":"https://creativecommons.org/licenses/by-sa/3.0/","permission_evidence":"Provided by Chris McQuinn of DrinkBox via email. Commons VRT confirms copyright holder approval under the file license in ticket 2014070810016233.","game_artwork_license":"CC BY-SA 3.0 for this authorized developer footage; the game itself is not asserted to be freely licensed.","source_sha256":"8a0a4d212f15fb1bceab484c2a43db5e833994cc2d1a925f2e5ca4adb01de792","media_sha256":"1c511f82c26c26bf11c2d3d06bdb57ddf44c777aa9194d304f660ba20ba60f1f","thumbnail_sha256":"f1bd2ff7a6578a26cc16dfdcb7ed4cbc866a87f925008ac1fddca33ba43ee033","modifications":"First 20 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.","duration_seconds":20.0,"vrt_ticket":"2014070810016233","clip_start_seconds":0,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes."}'
),
(
    '89630fe1-6fbe-5d05-aafe-6b29afb38fb5'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'manifold-garden',
    'Manifold Garden',
    'Manifold Garden - Impossible Architecture
Video: William Chyr.
https://commons.wikimedia.org/wiki/File:ManifoldGarden_BRoll02_E3_V01.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 3.0.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/89630fe1-6fbe-5d05-aafe-6b29afb38fb5/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/89630fe1-6fbe-5d05-aafe-6b29afb38fb5/cover.png',
    9709616,
    403869,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:ManifoldGarden_BRoll02_E3_V01.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=960991188","creator":"William Chyr","game_artwork_creator":"William Chyr","license":"CC BY-SA 3.0","license_url":"https://creativecommons.org/licenses/by-sa/3.0/","permission_evidence":"Provided by author William Chyr via email. Commons VRT confirms copyright holder approval in ticket 2016062410003518.","game_artwork_license":"CC BY-SA 3.0 for this authorized developer footage; no blanket license to game asset files inferred.","source_sha256":"229101ab43a32a3e15e00d938d46114417c809a0198325ef60f236259fe71c65","media_sha256":"c6b46c21c7e654560b7911801310e6ee4e37c6d3782ed3143419ede0ff95f6dd","thumbnail_sha256":"c68654d0cb0dd4d0ce63dd3bfc70198b68cee4b7ec5c7a1348e0b5af67ff6d6d","modifications":"First 20 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.","duration_seconds":20.0,"vrt_ticket":"2016062410003518","clip_start_seconds":0,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes."}'
),
(
    '28a87f34-378d-5c97-9e64-b608349a53a4'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'fantastic-contraption',
    'Fantastic Contraption',
    'Fantastic Contraption - VR Machine Building
Video: Sarah Northway.
https://commons.wikimedia.org/wiki/File:Fantastic_Contraption_gameplay_condensed.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 3.0.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/28a87f34-378d-5c97-9e64-b608349a53a4/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/28a87f34-378d-5c97-9e64-b608349a53a4/cover.png',
    9794067,
    237155,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Fantastic_Contraption_gameplay_condensed.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1138718930","creator":"Sarah Northway","game_artwork_creator":"Sarah Northway (file attribution)","license":"CC BY-SA 3.0","license_url":"https://creativecommons.org/licenses/by-sa/3.0/","permission_evidence":"File credits Sarah Northway. Commons VRT confirms copyright holder approval in ticket 2016041110017522. Download is from Commons; the historical YouTube provenance is not being used as permission.","game_artwork_license":"CC BY-SA 3.0 for this authorized developer footage; no blanket license to other game assets inferred.","source_sha256":"0eb00d14a53c427553064826fda8639e17bdf890ef8951a56d9c5f2e3f61e919","media_sha256":"fac66e04d57989c7780f1fa936134bcac9ae6621473198caae9d75dcd57679a5","thumbnail_sha256":"d854dd319fef63f34983a5290e3a8a62c6f154f2579446bece22a4a764ffe5dd","modifications":"First 20 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.","duration_seconds":20.003,"vrt_ticket":"2016041110017522","clip_start_seconds":0,"requested_duration_seconds":20,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes."}'
),
(
    'bb5f6920-3801-5d4c-8f6e-14c87bcbcbb8'::uuid,
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,
    'push-me-pull-you',
    'Push Me Pull You',
    'Push Me Pull You - Team Play
Video: House House.
https://commons.wikimedia.org/wiki/File:Push_Me_Pull_You_gameplay_1.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 7.233s; H.264 MP4; cover extracted. Derivatives: CC BY-SA 3.0.',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/bb5f6920-3801-5d4c-8f6e-14c87bcbcbb8/video.mp4',
    '0a8b2ca1-9e56-4843-828c-07f560fabd2a/bb5f6920-3801-5d4c-8f6e-14c87bcbcbb8/cover.png',
    2392477,
    168463,
    '{"source_url":"https://commons.wikimedia.org/wiki/File:Push_Me_Pull_You_gameplay_1.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1150891364","creator":"House House","game_artwork_creator":"House House","license":"CC BY-SA 3.0","license_url":"https://creativecommons.org/licenses/by-sa/3.0/","permission_evidence":"Provided by Nico Disseldorp, director of House House, via email. Commons VRT confirms copyright holder approval in ticket 2016042710001885.","game_artwork_license":"CC BY-SA 3.0 for this authorized developer footage; no blanket license to other game assets inferred.","source_sha256":"dbf8804dedf2515776fb637b82463107de28bf11ff6be4240c4e0f5ebace40ea","media_sha256":"3f20be1101ee91a40fdf3bd362ffacf02a6ca7ca1f184c171228b35bd6b18155","thumbnail_sha256":"da6498fec1435bad9cbe7f31111cf36ce2f4196662e920f346958289b111edab","modifications":"First 7.233 seconds; converted from Commons MPEG-4 MOV to H.264 MP4 using macOS avconvert Preset640x480.","thumbnail_modifications":"Video frame extracted using macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.","duration_seconds":7.233,"vrt_ticket":"2016042710001885","clip_start_seconds":0,"requested_duration_seconds":7.233,"local_preparation_checks":"Source/video/cover SHA-256, H.264 MP4 structure, duration, PNG dimensions and byte bounds were checked. Quick Look produced decoded covers.","review_limits":"Preparation is not exhaustive moderation. Full gameplay, content suitability and native in-app playback were not reviewed by this helper.","root_execution_prerequisites":"Root must separately review the selected clips, verify pending access denials and authenticated media hashes, and preserve required artwork credits before executing this approval. SQL checks stored owner/MIME/size, not content hashes."}'
);

-- This stage creates pending posts only. Media preparation is not an approval.
lock table public.video_posts in share row exclusive mode;

do $seed_pending$
begin
    perform 1 from private.accounts
    where user_id='0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid and cohort='development' and state='active'
    for share;
    if not found or not private.account_is_eligible('0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid) then
        raise exception 'Expected eligible active development Alpha owner';
    end if;
    if (select count(*) from pg_temp.fltiya_seed_expected) <> 7 then
        raise exception 'Expected exactly seven frozen seed posts';
    end if;
    if not exists (select 1 from storage.buckets where id='clips' and public=false) then
        raise exception 'Expected private clips bucket';
    end if;
    if exists (
        select 1 from public.video_posts v
        where v.id in (select id from pg_temp.fltiya_seed_expected)
           or v.video_path in (
               select video_path from pg_temp.fltiya_seed_expected
               union all select thumbnail_path from pg_temp.fltiya_seed_expected)
           or v.thumbnail_path in (
               select video_path from pg_temp.fltiya_seed_expected
               union all select thumbnail_path from pg_temp.fltiya_seed_expected)
    ) then
        raise exception 'Seed post id or immutable media path already exists';
    end if;
    if exists (
        select 1 from storage.objects o where o.bucket_id='clips'
        and o.name in (
            select video_path from pg_temp.fltiya_seed_expected
            union all select thumbnail_path from pg_temp.fltiya_seed_expected)
    ) then
        raise exception 'Seed storage path already exists before pending insertion';
    end if;
    if exists (
        select 1 from public.games g join pg_temp.fltiya_seed_expected e on e.game_id=g.id
        where g.name is distinct from e.game_name
    ) then
        raise exception 'Existing game name differs; review without overwriting the registry';
    end if;
end;
$seed_pending$;

insert into public.games(id,name)
select game_id,game_name from pg_temp.fltiya_seed_expected
on conflict(id) do nothing;

insert into public.video_posts(id,owner_id,game_id,caption,video_path,thumbnail_path,status)
select id,owner_id,game_id,caption,video_path,thumbnail_path,'pending'
from pg_temp.fltiya_seed_expected;

commit;
select id,status from public.video_posts where id in ('0266cd87-d7a3-53a6-8a08-6f454c48a6a5'::uuid, 'df55c5a2-7441-54fa-acd8-8429d331bda9'::uuid, 'efaae809-9e62-5ddb-96bc-eebbe47e2747'::uuid, '6920e768-4d0a-5af1-a003-10ea2eeca518'::uuid, '89630fe1-6fbe-5d05-aafe-6b29afb38fb5'::uuid, '28a87f34-378d-5c97-9e64-b608349a53a4'::uuid, 'bb5f6920-3801-5d4c-8f6e-14c87bcbcbb8'::uuid) order by id;
