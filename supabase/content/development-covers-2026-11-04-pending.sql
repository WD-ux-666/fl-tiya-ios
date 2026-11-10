-- Exact-three revision of existing reviewed development clips. New objects remain private.
begin;
select id from public.video_posts where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') for update;
do $$ declare matches integer; begin
select count(*) into matches from public.video_posts v
join (values ('57da4558-affa-44e7-8b1f-ae77236ad3fc'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/cover.png','0 A.D. - Village and Resource Gathering
Imported test clip. Video: PantheraLeo1359531; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',412416::bigint),('92a21b23-6a4f-4671-8619-3a018d8967b4'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/cover.png','Minetest - Flowing Lava
Imported test clip. Video: PantheraLeo1359531; game: Perttu Ahola / The Minetest Team.
Source: https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',389876::bigint),('6963e789-64f3-4ca9-8ad8-b31651602692'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/cover.png','0 A.D. - Winter 2007 Gameplay Preview
Imported test clip. Video: Wildfire Games; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',316745::bigint)) e(id,owner_id,video_path,cover_path,caption,bytes) on v.id=e.id and v.owner_id=e.owner_id and v.video_path=e.video_path
join private.accounts a on a.user_id=v.owner_id
where v.status='approved' and v.thumbnail_path is null and v.caption=e.caption
and a.cohort='development' and a.state='active'
and not exists(select 1 from storage.objects o where o.bucket_id='clips' and o.name=e.cover_path);
if matches<>3 then raise exception 'Expected exactly three unchanged approved development clips without covers'; end if;
end $$;
update public.video_posts v set status='pending',approved_at=null,thumbnail_path=e.cover_path,
caption=e.caption||E'\nCover: extracted video frame; CC BY-SA 3.0.'
from (values ('57da4558-affa-44e7-8b1f-ae77236ad3fc'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/cover.png','0 A.D. - Village and Resource Gathering
Imported test clip. Video: PantheraLeo1359531; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',412416::bigint),('92a21b23-6a4f-4671-8619-3a018d8967b4'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/cover.png','Minetest - Flowing Lava
Imported test clip. Video: PantheraLeo1359531; game: Perttu Ahola / The Minetest Team.
Source: https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',389876::bigint),('6963e789-64f3-4ca9-8ad8-b31651602692'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/cover.png','0 A.D. - Winter 2007 Gameplay Preview
Imported test clip. Video: Wildfire Games; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.',316745::bigint)) e(id,owner_id,video_path,cover_path,caption,bytes) where v.id=e.id;
commit;
select id,status,thumbnail_path from public.video_posts where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') order by id;
