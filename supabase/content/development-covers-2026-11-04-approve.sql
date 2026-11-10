-- Append cover-specific reviews, preserving the prior video review records.
begin;
select id from public.video_posts where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') for update;
do $$ declare matches integer; begin
select count(*) into matches from public.video_posts v
join (values ('57da4558-affa-44e7-8b1f-ae77236ad3fc'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/cover.png','0 A.D. - Village and Resource Gathering
Imported test clip. Video: PantheraLeo1359531; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.
Cover: extracted video frame; CC BY-SA 3.0.',412416::bigint),('92a21b23-6a4f-4671-8619-3a018d8967b4'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/cover.png','Minetest - Flowing Lava
Imported test clip. Video: PantheraLeo1359531; game: Perttu Ahola / The Minetest Team.
Source: https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.
Cover: extracted video frame; CC BY-SA 3.0.',389876::bigint),('6963e789-64f3-4ca9-8ad8-b31651602692'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid,'0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/video.mp4','0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/cover.png','0 A.D. - Winter 2007 Gameplay Preview
Imported test clip. Video: Wildfire Games; game: Wildfire Games.
Source: https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv
CC BY-SA 3.0: https://creativecommons.org/licenses/by-sa/3.0/
First 20 seconds; H.264 MP4 conversion. Derivative: CC BY-SA 3.0.
Cover: extracted video frame; CC BY-SA 3.0.',316745::bigint)) e(id,owner_id,video_path,cover_path,caption,bytes) on v.id=e.id and v.owner_id=e.owner_id and v.video_path=e.video_path
and v.thumbnail_path=e.cover_path and v.caption=e.caption
join private.accounts a on a.user_id=v.owner_id
join storage.objects o on o.bucket_id='clips' and o.name=e.cover_path
where v.status='pending' and v.approved_at is null and a.cohort='development' and a.state='active'
and o.owner_id=v.owner_id::text and o.metadata->>'mimetype'='image/png'
and (o.metadata->>'size')::bigint=e.bytes
and exists(select 1 from private.video_reviews r where r.post_id=v.id and r.decision='approved' and r.reviewer_reference='licensed-development-import-2026-11-04');
if matches<>3 then raise exception 'Expected three pending reviewed covers with exact paths, owners, type and sizes'; end if;
end $$;
insert into private.video_reviews(post_id,decision,reviewer_reference,notes) values ('57da4558-affa-44e7-8b1f-ae77236ad3fc','approved','licensed-development-cover-import-2026-11-04','{"source_url": "https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm", "creator": "PantheraLeo1359531", "license": "CC BY-SA 3.0", "license_url": "https://creativecommons.org/licenses/by-sa/3.0/", "media_sha256": "1f133245f09a8a69f5e31492acf4567664f4304a31fd7c68b98cef82e7205205", "thumbnail_path": "0a8b2ca1-9e56-4843-828c-07f560fabd2a/57da4558-affa-44e7-8b1f-ae77236ad3fc/cover.png", "thumbnail_sha256": "b0ebd87b874d5f9d3330c34fbcff02367df61615d270fedfe0de1af167a35dc4", "thumbnail_bytes": 412416, "thumbnail_dimensions": [640, 360], "thumbnail_modifications": "Video frame extracted by macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.", "review": "Actual extracted gameplay frame visually inspected; bounded PNG dimensions checked; authenticated owner full-byte readback matched; pending peer access denied. Native cover display not executed."}'),('92a21b23-6a4f-4671-8619-3a018d8967b4','approved','licensed-development-cover-import-2026-11-04','{"source_url": "https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm", "creator": "PantheraLeo1359531", "license": "CC BY-SA 3.0", "license_url": "https://creativecommons.org/licenses/by-sa/3.0/", "media_sha256": "42b748b83935a432fff7e1ee1bcd063671c492cc49b4f840f5b6bf6a7a0ebc33", "thumbnail_path": "0a8b2ca1-9e56-4843-828c-07f560fabd2a/92a21b23-6a4f-4671-8619-3a018d8967b4/cover.png", "thumbnail_sha256": "35789120b39b1125bcda9d2f72488dedb1da0e07b745851962c0928963c2c7cb", "thumbnail_bytes": 389876, "thumbnail_dimensions": [640, 360], "thumbnail_modifications": "Video frame extracted by macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.", "review": "Actual extracted gameplay frame visually inspected; bounded PNG dimensions checked; authenticated owner full-byte readback matched; pending peer access denied. Native cover display not executed."}'),('6963e789-64f3-4ca9-8ad8-b31651602692','approved','licensed-development-cover-import-2026-11-04','{"source_url": "https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv", "creator": "Wildfire Games", "license": "CC BY-SA 3.0", "license_url": "https://creativecommons.org/licenses/by-sa/3.0/", "media_sha256": "404dd9103fc4275abb94b05b09b90c99fe8f78d11eaef12faed26dcc2cbdd2cc", "thumbnail_path": "0a8b2ca1-9e56-4843-828c-07f560fabd2a/6963e789-64f3-4ca9-8ad8-b31651602692/cover.png", "thumbnail_sha256": "243f921a8531c18e4561f05e4180265f5c2746f88ee95bd4daf1e0d16b52545a", "thumbnail_bytes": 316745, "thumbnail_dimensions": [480, 360], "thumbnail_modifications": "Video frame extracted by macOS Quick Look at maximum 640 pixels; no artwork added. Cover derivative: CC BY-SA 3.0.", "review": "Actual extracted gameplay frame visually inspected; bounded PNG dimensions checked; authenticated owner full-byte readback matched; pending peer access denied. Native cover display not executed."}');
update public.video_posts set status='approved',approved_at=now() where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') and status='pending';
commit;
select id,status,thumbnail_path from public.video_posts where id in ('57da4558-affa-44e7-8b1f-ae77236ad3fc','92a21b23-6a4f-4671-8619-3a018d8967b4','6963e789-64f3-4ca9-8ad8-b31651602692') order by id;
