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
    video_path text not null unique, thumbnail_path text not null unique,
    review_notes text not null
) on commit drop;
insert into pg_temp.fltiya_popular_expected values
('084d6071-d274-52b3-8f24-62b731a741cb', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 'minecraft', 'Minecraft', 'Minecraft - Xbox Mexico Gameplay (2023)
Video: Xbox México.
Source: https://commons.wikimedia.org/wiki/File:Minecraft_Gameplay.webm
CC BY 3.0: https://creativecommons.org/licenses/by/3.0/
First 8.8s; H.264 MP4 conversion; cover extracted from video. Derivatives: CC BY 3.0.', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/cover.png', '{"source_url":"https://commons.wikimedia.org/wiki/File:Minecraft_Gameplay.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1287415827","original_publisher_url":"https://www.youtube.com/watch?v=T1Ua2SVUhYw","creator":"Xbox México","source_date":"2023-04-03","content_kind":"gameplay","license":"CC BY 3.0","license_url":"https://creativecommons.org/licenses/by/3.0/","permission_evidence":"Commons file credits Xbox México, an official Xbox subsidiary, and explicitly documents that this specific depiction was released under CC BY. It does not extend permission to other Minecraft media.","source_sha256":"b98e64cd5c8dca1f7b550f1b9aff159c753382669b15cbf0928fe8c6bec50b41","media_sha256":"f844035d4673ea28fe5600a04fe5f6c9814bc2c5d571a2fbc72cf99079c7cf51","thumbnail_sha256":"5e294bbe9b94843d4d8536afa31e0b8fba73d9c0b23fd074bf637295313b2d14","modifications":"First 8.8 seconds; Commons MOV transcode to H.264 MP4; Quick Look frame cover.","review_limits":"Local decoded video/cover visual review and authenticated byte/hash readback must be completed separately; SQL checks owner/MIME/size, not hashes."}'),
('86916319-1668-569a-8fd0-8ff991d483c4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 'pubg-mobile', 'PUBG MOBILE', 'PUBG MOBILE - Erangel Imagination Plaza (2023 official promo)
Video: PUBG MOBILE.
Source: https://commons.wikimedia.org/wiki/File:PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm
CC BY 3.0: https://creativecommons.org/licenses/by/3.0/
Seconds 45-65; H.264 MP4 conversion; cover extracted from video. Derivatives: CC BY 3.0.', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/cover.png', '{"source_url":"https://commons.wikimedia.org/wiki/File:PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm","source_permanent_url":"https://commons.wikimedia.org/w/index.php?oldid=1039390211","original_publisher_url":"https://www.youtube.com/watch?v=tWZ9nZIeins","creator":"PUBG MOBILE","source_date":"2023-03-18","content_kind":"official-promo","license":"CC BY 3.0","license_url":"https://creativecommons.org/licenses/by/3.0/","permission_evidence":"Commons credits the official PUBG MOBILE channel and records independent license review on 2024-12-27 confirming CC BY 3.0 on the source. This is a 2023 anniversary promotion, not current gameplay.","source_sha256":"6800914df2fa10204830b842dbfacfbca501d4a712a6a2607b83c3b12a33afd9","media_sha256":"960e32ac7cb585e20884e3a26084e5b670f30a47acd75a78b4c0cd92457467e6","thumbnail_sha256":"3fe836e2abd2836a79f588942a50c94b909017c8de056273aba3555d3e3563da","modifications":"Seconds 45-65; Commons MOV transcode to H.264 MP4; Quick Look frame cover.","review_limits":"Local decoded video/cover visual review and authenticated byte/hash readback must be completed separately; SQL checks owner/MIME/size, not hashes."}');

create temporary table fltiya_popular_objects (
    path text primary key, owner_id uuid not null, bytes bigint not null, mime text not null
) on commit drop;
insert into pg_temp.fltiya_popular_objects values
('0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 3981926, 'video/mp4'),
('0a8b2ca1-9e56-4843-828c-07f560fabd2a/084d6071-d274-52b3-8f24-62b731a741cb/cover.png', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 318243, 'image/png'),
('0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/video.mp4', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 5960105, 'video/mp4'),
('0a8b2ca1-9e56-4843-828c-07f560fabd2a/86916319-1668-569a-8fd0-8ff991d483c4/cover.png', '0a8b2ca1-9e56-4843-828c-07f560fabd2a', 335625, 'image/png');

do $approve$
declare matches integer; changed integer;
begin
    if (select count(*) from pg_temp.fltiya_popular_expected) <> 2
       or (select count(*) from pg_temp.fltiya_popular_objects) <> 4 then
        raise exception 'Expected two reviewed posts and four media objects';
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
select id,status from public.video_posts where id in ('084d6071-d274-52b3-8f24-62b731a741cb'::uuid, '86916319-1668-569a-8fd0-8ff991d483c4'::uuid) order by id;
