-- Project: gpstwmffctwqlcakmvgw. Initial eight development Guides only.
-- Frozen source manifest SHA-256: 25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36.
-- No source article bodies or publisher images are imported.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';

create temporary table fltiya_initial_guides_expected (
    id uuid primary key,
    game_id text not null,
    title text not null,
    summary text not null,
    source_url text not null unique,
    source_name text not null,
    source_author text,
    attribution text not null,
    cohort text not null,
    review_note text not null check(char_length(review_note)<=2000)
) on commit drop;

insert into pg_temp.fltiya_initial_guides_expected values
(
    'cdfb5f16-1c25-5b72-890c-e3d4a3690d63'::uuid,
    'zenless-zone-zero',
    '"Enigma of the Labyrinth" Gameplay Guide — Maps & Items',
    'A publisher guide to map and item systems in Enigma of the Labyrinth, the permanent exploration mode introduced in Version 3.1. Read the original illustrated guide before planning an investigation. Maps and items; no unverified routes, rates, or item tables are reproduced.',
    'https://zenless.hoyoverse.com/en-us/news/165548',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2026-08-06. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/165548","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"guide","source_published_at":"2026-08-06","editorial_note":"Maps and items; no unverified routes, rates, or item tables are reproduced.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    '836fc1a5-a875-5d49-8f2d-40c003e652e1'::uuid,
    'zenless-zone-zero',
    '"Enigma of the Labyrinth" Gameplay Guide — Infrastructure & Commissions',
    'Learn where the official guide explains infrastructure, crafting, and commissions in Enigma of the Labyrinth. This reference is useful when planning what to build or which commission to pursue next. Overview only; detailed mechanics are in the source illustrations.',
    'https://zenless.hoyoverse.com/en-us/news/165510',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2026-08-05. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/165510","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"guide","source_published_at":"2026-08-05","editorial_note":"Overview only; detailed mechanics are in the source illustrations.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    '3070a276-401f-50c3-9fdb-78f17c5b320c'::uuid,
    'zenless-zone-zero',
    'Annihilation Simulacrum Gameplay Guide',
    'The official introduction to Annihilation Simulacrum presents it as a high difficulty combat challenge. Use the source guide to check its rules before taking a squad into the mode. No current season rules, rewards, unlock criteria, or strategy are inferred from the introduction.',
    'https://zenless.hoyoverse.com/en-us/news/164845',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2026-06-18. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/164845","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"guide","source_published_at":"2026-06-18","editorial_note":"No current season rules, rewards, unlock criteria, or strategy are inferred from the introduction.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    '4181086f-6ba5-51fc-b425-cc2a3ec119ee'::uuid,
    'zenless-zone-zero',
    'Ridu Renovation Talk Vol. 4: Daily Life at Suibian Temple',
    'An official introduction to Suibian Temple management and Divination in Season 2. It explains the daily activities associated with the temple after the story moves to Waifei Peninsula. Older system guide; check current in-game details before applying specific numbers.',
    'https://zenless.hoyoverse.com/en-us/news/156675',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2025-06-02. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/156675","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"guide","source_published_at":"2025-06-02","editorial_note":"Older system guide; check current in-game details before applying specific numbers.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    '329419be-b9e8-5ae1-875b-79f2a0010953'::uuid,
    'zenless-zone-zero',
    'Ridu Renovation Talk Vol. 13 | System & Gameplay Updates',
    'This developer guide introduces Version 3.1 changes to Deadly Assault and other systems. It provides background for returning players who want to understand how those features changed. Version-specific system overview, not an optimized combat build or tier list.',
    'https://zenless.hoyoverse.com/en-us/news/165369',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2026-07-27. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/165369","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"guide","source_published_at":"2026-07-27","editorial_note":"Version-specific system overview, not an optimized combat build or tier list.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    'ff105627-73ee-5b59-96fe-b86bb85d6b17'::uuid,
    'zenless-zone-zero',
    'Account help: How to Fix the Issue of Linking the Wrong HoYoverse Account',
    'The publisher explains how to request help after linking the wrong HoYoverse account to Steam. Open the original instructions for the current appeal route and the information support needs. Steam account support tutorial. The page display date and RSS publication timestamp differ; the timestamp here is the observed RSS pubDate. No appeal form token or user data is stored.',
    'https://steamcommunity.com/games/4162040/announcements/detail/702145613257509311',
    'HoYoverse / COGNOSPHERE',
    'Overtimeboo',
    'HoYoverse / COGNOSPHERE. Original author: Overtimeboo. Original publication: 2026-06-18. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://steamcommunity.com/games/4162040/announcements/detail/702145613257509311","source_name":"HoYoverse / COGNOSPHERE","source_author":"Overtimeboo","content_kind":"support_tutorial","source_published_at":"2026-06-18T05:04:34Z","editorial_note":"Steam account support tutorial. The page display date and RSS publication timestamp differ; the timestamp here is the observed RSS pubDate. No appeal form token or user data is stored.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    'f0e2061f-43f6-548b-9b0f-4579ae60b1e3'::uuid,
    'zenless-zone-zero',
    'Character reference: Official Agent Roster',
    'Browse the official roster for character introductions. Anby Demara, Nicole Demara, and Billy Kid are represented in the Cunning Hares group; use each current profile for the publisher''s characterization. The landing page title changes with its featured Agent. Do not treat the current featured title as a permanent name for the entire roster.',
    'https://zenless.hoyoverse.com/en-us/character',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/character","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"character_reference","source_published_at":null,"editorial_note":"The landing page title changes with its featured Agent. Do not treat the current featured title as a permanent name for the entire roster.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
),
(
    'f9d3ae61-2169-5587-b590-3ff9a700fe09'::uuid,
    'zenless-zone-zero',
    'Historical world guide: The Bangboo',
    'An early official world guide introduces Bangboo as helpful devices in New Eridu and the Hollows. It is a setting reference rather than a current combat build or progression guide. Historical pre-release worldbuilding reference. Keep its date visible and exclude it from current-mechanics claims.',
    'https://zenless.hoyoverse.com/en-us/news/102383',
    'HoYoverse / COGNOSPHERE',
    null,
    'HoYoverse / COGNOSPHERE. Original publication: 2022-07-02. Short overview by FL-Tiya. Read the original source for full instructions and artwork.',
    'development',
    '{"source_url":"https://zenless.hoyoverse.com/en-us/news/102383","source_name":"HoYoverse / COGNOSPHERE","source_author":null,"content_kind":"world_guide","source_published_at":"2022-07-02","editorial_note":"Historical pre-release worldbuilding reference. Keep its date visible and exclude it from current-mechanics claims.","manifest_sha256":"25973f377166cb4108845c7b010b0452f0c36ef432a51f2d7a4c8c4cd6f90e36","review_scope":"Original English summaries, publisher links and attribution only; no article bodies or character images imported. Historical and version-specific limits are retained. This approval does not grant a license to publisher artwork or assert exhaustive source verification."}'
);

-- Execute only after root editorial review and a successful verify-draft.
-- Append exactly eight review decisions before publishing the matched drafts.
do $initial_guides_approve$
declare
    matches integer;
    changed integer;
begin
    if (select count(*) from pg_temp.fltiya_initial_guides_expected) <> 8
       or exists (select 1 from pg_temp.fltiya_initial_guides_expected
                  where cohort<>'development' or game_id<>'zenless-zone-zero') then
        raise exception 'Expected eight exact development ZZZ Guides';
    end if;
    if not exists (select 1 from public.games where id='zenless-zone-zero') then
        raise exception 'Expected existing Zenless Zone Zero registry entry';
    end if;
    -- The verifier may PATCH only this absent sentinel, never a real guide.
    if exists (select 1 from public.guides where id='00000000-0000-0000-0000-000000000000'::uuid) then
        raise exception 'Nonexistent write-probe UUID is already in use';
    end if;
    perform 1 from public.guides g
    join pg_temp.fltiya_initial_guides_expected e on e.id=g.id
    for update of g;
    select count(*) into matches
    from public.guides g join pg_temp.fltiya_initial_guides_expected e on e.id=g.id
    where g.status='draft' and g.published_at is null
      and (g.id,g.game_id,g.title,g.summary,g.source_url,g.source_name,g.source_author,g.attribution,g.cohort) is not distinct from (e.id,e.game_id,e.title,e.summary,e.source_url,e.source_name,e.source_author,e.attribution,e.cohort);
    if matches<>8 then
        raise exception 'Expected eight unchanged development Guide drafts';
    end if;
    if exists (
        select 1 from private.guide_reviews r
        join pg_temp.fltiya_initial_guides_expected e on e.id=r.guide_id
        where r.decision='approved'
    ) then
        raise exception 'Initial Guides already have approved review records';
    end if;

    insert into private.guide_reviews(guide_id,decision,reviewed_by,note)
    select id,'approved','initial-zzz-guides-editorial-review-2026-11-04',review_note
    from pg_temp.fltiya_initial_guides_expected;
    get diagnostics changed=row_count;
    if changed<>8 then
        raise exception 'Expected eight appended editorial reviews';
    end if;
    update public.guides g set status='published',published_at=statement_timestamp()
    from pg_temp.fltiya_initial_guides_expected e
    where g.id=e.id and g.status='draft' and g.cohort='development';
    get diagnostics changed=row_count;
    if changed<>8 then
        raise exception 'Expected eight published development Guides';
    end if;
end;
$initial_guides_approve$;

commit;
select id,status from public.guides where id in ('cdfb5f16-1c25-5b72-890c-e3d4a3690d63'::uuid, '836fc1a5-a875-5d49-8f2d-40c003e652e1'::uuid, '3070a276-401f-50c3-9fdb-78f17c5b320c'::uuid, '4181086f-6ba5-51fc-b425-cc2a3ec119ee'::uuid, '329419be-b9e8-5ae1-875b-79f2a0010953'::uuid, 'ff105627-73ee-5b59-96fe-b86bb85d6b17'::uuid, 'f0e2061f-43f6-548b-9b0f-4579ae60b1e3'::uuid, 'f9d3ae61-2169-5587-b590-3ff9a700fe09'::uuid) order by id;
