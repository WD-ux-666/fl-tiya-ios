-- FL-Tiya development cohort, project gpstwmffctwqlcakmvgw.
-- Frozen manifest SHA-256: f1fcd8802caa5462ad27c92f0b49196f89d232b9404a12d030ecf433fb5036e8. No credentials.
-- Generated SQL is not evidence of completed media review or upload.
-- Execute only after verifying the intended project and review stage.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create temporary table fltiya_popular_expected (
    id uuid primary key, owner_id uuid not null, game_id text not null,
    game_name text not null, caption text not null,
    video_path text not null unique, thumbnail_path text not null unique
) on commit drop;
insert into pg_temp.fltiya_popular_expected values
('084d6071-d274-52b3-8f24-62b731a741cb', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 'minecraft', 'Minecraft', 'Minecraft - Xbox Mexico Gameplay (2023)
Video: Xbox México.
Source: https://commons.wikimedia.org/wiki/File:Minecraft_Gameplay.webm
CC BY 3.0: https://creativecommons.org/licenses/by/3.0/
First 8.8s; H.264 MP4 conversion; cover extracted from video. Derivatives: CC BY 3.0.', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/cover.png'),
('86916319-1668-569a-8fd0-8ff991d483c4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 'pubg-mobile', 'PUBG MOBILE', 'PUBG MOBILE - Erangel Imagination Plaza (2023 official promo)
Video: PUBG MOBILE.
Source: https://commons.wikimedia.org/wiki/File:PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm
CC BY 3.0: https://creativecommons.org/licenses/by/3.0/
Seconds 45-65; H.264 MP4 conversion; cover extracted from video. Derivatives: CC BY 3.0.', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/cover.png');

lock table public.video_posts in share row exclusive mode;
do $pending$
begin
    if (select count(*) from pg_temp.fltiya_popular_expected) <> 2 then
        raise exception 'Expected two reviewed popular-game sources';
    end if;
    perform 1 from private.accounts
    where user_id='0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid and cohort='development' and state='active'
    for share;
    if not found or not private.account_is_eligible('0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid) then
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
select id,status from public.video_posts where id in ('084d6071-d274-52b3-8f24-62b731a741cb'::uuid, '86916319-1668-569a-8fd0-8ff991d483c4'::uuid) order by id;
