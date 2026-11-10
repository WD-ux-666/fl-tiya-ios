begin;
do $$ begin if not exists (select 1 from private.accounts where user_id='0a8b2ca1-9e56-4843-828c-07f560fabd2a' and cohort='development' and state='active') then raise exception 'Expected development importer'; end if; end $$;
insert into public.games(id,name) values ('zero-ad','0 A.D.'),('minetest','Minetest') on conflict(id) do nothing;
insert into public.video_posts(id,owner_id,game_id,caption,video_path) values ('57da4558-affa-44e7-8b1f-ae77236ad3fc','0a8b2ca1-9e56-4843-828c-07f560fabd2a','zero-ad','0 A.D. - Village and Resource Gathering
Imported test clip. Video: PantheraLeo1359531; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.','0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/video.mp4'),('92a21b23-6a4f-4671-8619-3a018d8967b4','0a8b2ca1-9e56-4843-828c-07f560fabd2a','minetest','Minetest - Flowing Lava
Imported test clip. Video: PantheraLeo1359531; game: Perttu Ahola / The Minetest Team.
Source: https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.','0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/video.mp4'),('6963e789-64f3-4ca9-8ad8-b31651602692','0a8b2ca1-9e56-4843-828c-07f560fabd2a','zero-ad','0 A.D. - Winter 2007 Gameplay Preview
Imported test clip. Video: Wildfire Games; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.','0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/video.mp4');
commit;
select id,status from public.video_posts where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') order by id;
