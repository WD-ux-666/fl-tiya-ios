-- Opt in the 36 fictional players from the November 6 community roster.
-- Pin the reviewed November 9 scenic avatar paths and exclude other test logins.
-- Apply only after the curated community player migration, in FL-Tiya.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '20s';

do $publish$
declare
    expected_fixtures jsonb;
    matched_count integer;
begin
    select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(fixture)) into expected_fixtures
    from (values
        ('5b0dc3ad-4518-55d0-8488-3628d86cacdf', 'bobs-game', 'emma_rowan', 'Emma Rowan', 'Puzzle breaks between busy days. Here for satisfying chains and friendly score chasing.', '5b0dc3ad-4518-55d0-8488-3628d86cacdf/29edd499-3e8e-57bb-af4b-42e5aa6b6824.jpg', 'Development Community Emma Rowan', 30989),
        ('59bc0e8f-d247-582f-856d-6f3ed13de457', 'bobs-game', 'ezra_cole', 'Ezra Cole', 'Always hunting for a cleaner chain. Small puzzle games are my favorite way to unwind.', '59bc0e8f-d247-582f-856d-6f3ed13de457/ec980965-f86e-5bf4-94ca-f7107aaa9c2a.jpg', 'Development Community Ezra Cole', 31917),
        ('dc7e5f57-b1ed-5c06-bf84-5fec2ce9635a', 'bobs-game', 'luca_west', 'Luca West', 'Just a quick puzzle before bed, until it becomes five more. Comparing high scores for fun.', 'dc7e5f57-b1ed-5c06-bf84-5fec2ce9635a/5d6afe70-490c-53f0-a2fb-d67519001689.jpg', 'Development Community Luca West', 25508),
        ('3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0', 'fantastic-contraption', 'iris_shaw', 'Iris Shaw', 'Building weird machines and seeing what rolls. The silly solutions are usually the best.', '3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0/68b5ad02-252c-5ca1-95bb-9597cd416d52.jpg', 'Development Community Iris Shaw', 27950),
        ('19dbbc8f-5796-527c-9a2b-1bd882fab368', 'fantastic-contraption', 'leah_quinn', 'Leah Quinn', 'Part puzzle fan, part improvised engineer. I like finding a different way to solve things.', '19dbbc8f-5796-527c-9a2b-1bd882fab368/48568bb8-1dfe-5c62-829f-6591aa5b1af8.jpg', 'Development Community Leah Quinn', 25478),
        ('73942806-20d7-54c8-bc77-1419d1bd9d7c', 'fantastic-contraption', 'sam_archer', 'Sam Archer', 'Overthinking simple puzzles is a hobby. Send me your most ridiculous working machine.', '73942806-20d7-54c8-bc77-1419d1bd9d7c/9b885cee-3256-502a-8388-fb20391390f8.jpg', 'Development Community Sam Archer', 29894),
        ('52ae9afd-9819-5727-bd73-3b20c9d21168', 'freedoom', 'alex_rivers', 'Alex Rivers', 'Map exploring with a side of chaotic aim. Here to trade favorite retro game finds.', '52ae9afd-9819-5727-bd73-3b20c9d21168/b7c58fbc-50f8-548d-aaf7-d23b882df296.jpg', 'Development Community Alex Rivers', 41220),
        ('97dd6a5a-0881-51ae-b6f7-e2aee09754a8', 'freedoom', 'dante_knox', 'Dante Knox', 'Retro shooters, custom maps and fast little runs. Taking the scenic route is optional.', '97dd6a5a-0881-51ae-b6f7-e2aee09754a8/c54b63c3-be86-4ab5-bad6-9d1c0caeab8f.jpg', 'Development Community Dante Knox', 13659),
        ('786fc76d-1070-55b4-81ef-30a08dcdae4e', 'freedoom', 'naomi_chase', 'Naomi Chase', 'Old-school action and new community maps. Always looking for another level to explore.', '786fc76d-1070-55b4-81ef-30a08dcdae4e/ecee6191-8af5-59df-a318-42305df6b408.jpg', 'Development Community Naomi Chase', 15965),
        ('256e3201-3934-5ae7-804a-02186ad08eec', 'guacamelee', 'diego_cruz', 'Diego Cruz', 'A little platforming, a lot of missed jumps. Always up for a co-op challenge.', '256e3201-3934-5ae7-804a-02186ad08eec/d418725a-4c03-4c52-ba72-a300da7c5cff.jpg', 'Development Community Diego Cruz', 25547),
        ('64428a1b-6ad1-5461-baf2-7f50d94b4b20', 'guacamelee', 'max_turner', 'Max Turner', 'Chasing one clean combo before calling it a night. Send me your best boss tip.', '64428a1b-6ad1-5461-baf2-7f50d94b4b20/ad8fe640-2bdc-5bd2-8dfc-4b420445a610.jpg', 'Development Community Max Turner', 21900),
        ('42f543fd-aa4b-5b36-9d83-9f0dae503523', 'guacamelee', 'ruby_navarro', 'Ruby Navarro', 'Here for bright worlds, clever combos and finding every hidden corner.', '42f543fd-aa4b-5b36-9d83-9f0dae503523/8d69806d-43ac-5ed6-94f3-7b998dc32260.jpg', 'Development Community Ruby Navarro', 16118),
        ('ccfc933b-dba2-55ef-92ee-47ab6fe85467', 'manifold-garden', 'ava_sterling', 'Ava Sterling', 'Impossible staircases and slow afternoons. I like puzzles that make me stop and look.', 'ccfc933b-dba2-55ef-92ee-47ab6fe85467/6e3df836-905a-430e-8ee6-58d91e00dc92.jpg', 'Development Community Ava Sterling', 17056),
        ('e53c8f39-87c4-5d03-b324-722c2044301c', 'manifold-garden', 'felix_quinn', 'Felix Quinn', 'Turning gravity around until something finally clicks. Puzzle recommendations welcome.', 'e53c8f39-87c4-5d03-b324-722c2044301c/bb1c80df-8fa7-51c5-9328-7c39e80a46b9.jpg', 'Development Community Felix Quinn', 40461),
        ('4db6ec84-3240-5fb7-8de6-95ad6bda6191', 'manifold-garden', 'sofia_hart', 'Sofia Hart', 'Architecture, ambient music and games with strange beautiful worlds.', '4db6ec84-3240-5fb7-8de6-95ad6bda6191/92778874-576c-5d8d-8678-bdb5c782470b.jpg', 'Development Community Sofia Hart', 50073),
        ('e7e975f1-b08a-596d-8df8-df9f5bdda8c1', 'minecraft', 'chloe_bennett', 'Chloe Bennett', 'Building cozy villages one block at a time. Share your favorite build idea.', 'e7e975f1-b08a-596d-8df8-df9f5bdda8c1/606f4552-b8b5-47ed-864c-caca7223a4ff.jpg', 'Development Community Chloe Bennett', 15392),
        ('aa182005-e481-4df2-a56f-09ee60da7f5b', 'minecraft', 'nina_vega', 'Nina Vega', 'Love a clever build and a hard boss fight. Trading game tips, sharing highlights and learning as I go.', 'aa182005-e481-4df2-a56f-09ee60da7f5b/766cf9c2-51fd-5913-89ef-d5aa65378cdf.jpg', 'Development TEST Summit', 36713),
        ('1c1594bf-d7f4-5d06-8bb9-be3507e9ea48', 'minecraft', 'owen_brooks', 'Owen Brooks', 'Tiny cabins, huge storage rooms. Always starting another survival world.', '1c1594bf-d7f4-5d06-8bb9-be3507e9ea48/d7147397-6078-5979-be79-1b4c61fe7ba1.jpg', 'Development Community Owen Brooks', 46743),
        ('1f3a575d-5ba3-5073-98ae-7b1b5af41850', 'minetest', 'aria_finch', 'Aria Finch', 'Open worlds, garden builds and a quiet mining session. Show me what you are making.', '1f3a575d-5ba3-5073-98ae-7b1b5af41850/d301f40a-c0c8-57e8-974f-8347594eeee6.jpg', 'Development Community Aria Finch', 32452),
        ('499cdd5d-28f4-58ae-befe-eb13bd0fcc31', 'minetest', 'ben_ellis', 'Ben Ellis', 'Weekend builder who keeps getting distracted underground. I enjoy tinkering with mods.', '499cdd5d-28f4-58ae-befe-eb13bd0fcc31/ba9c6987-8df6-5628-96ce-1865cbb6590e.jpg', 'Development Community Ben Ellis', 24934),
        ('919c7892-d739-581b-8df0-9ff8d75c51c7', 'minetest', 'milo_stone', 'Milo Stone', 'Digging tunnels and trying new mods. My next build is always bigger than the last.', '919c7892-d739-581b-8df0-9ff8d75c51c7/946ad430-2bd7-56b8-8d02-d94ef8617469.jpg', 'Development Community Milo Stone', 40169),
        ('ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'pubg-mobile', 'leo_brooks', 'Leo Brooks', 'One more match usually means three. PUBG MOBILE, co-op games and keeping the squad laughing.', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8/594d91f0-26d1-579c-a6dc-d95691acd81e.jpg', 'Development TEST Harbor', 37390),
        ('a6aff5c5-0e13-5a56-bf28-41685cb89100', 'pubg-mobile', 'marcus_reed', 'Marcus Reed', 'Usually the last one looting. Looking for relaxed squads and funny match clips.', 'a6aff5c5-0e13-5a56-bf28-41685cb89100/c9c9415a-4ae4-5919-b82e-a360069b9803.jpg', 'Development Community Marcus Reed', 16144),
        ('17dcccdf-50cf-5e79-ba6d-14693bcea1c0', 'pubg-mobile', 'zara_hayes', 'Zara Hayes', 'Erangel evenings with the squad. Good callouts beat a perfect score.', '17dcccdf-50cf-5e79-ba6d-14693bcea1c0/84a14183-5e60-585a-aadf-97ab829ccf7f.jpg', 'Development Community Zara Hayes', 21842),
        ('1dbb484e-a71d-51d2-832a-d568267dd417', 'push-me-pull-you', 'caleb_price', 'Caleb Price', 'I bring the enthusiasm, my teammates bring the coordination. Here for silly party games.', '1dbb484e-a71d-51d2-832a-d568267dd417/aa036291-75da-50a1-bd74-7cd7d47b5f29.jpg', 'Development Community Caleb Price', 28464),
        ('94ad5bcf-2ebf-5c3a-8f02-d8966fe5f83e', 'push-me-pull-you', 'mina_flores', 'Mina Flores', 'Local multiplayer nights and laughing until we lose. Co-op is better with friends.', '94ad5bcf-2ebf-5c3a-8f02-d8966fe5f83e/8bb0dcd4-ba03-5ffd-9359-87e195d737b5.jpg', 'Development Community Mina Flores', 22761),
        ('969d3d84-0bd4-581b-9321-05f027434932', 'push-me-pull-you', 'zoe_avery', 'Zoe Avery', 'Party games, couch co-op and clips that make the whole group laugh.', '969d3d84-0bd4-581b-9321-05f027434932/c20a5770-5828-579a-a49a-5ac447c842f4.jpg', 'Development Community Zoe Avery', 21274),
        ('54ea5a01-bbcc-5349-940c-a58264b628ed', 'supertuxkart', 'isla_fox', 'Isla Fox', 'Collecting shortcuts and laughing at my own crashes. Casual races any day.', '54ea5a01-bbcc-5349-940c-a58264b628ed/7982fd50-41b9-5bc0-a4d3-bf00d12f482b.jpg', 'Development Community Isla Fox', 46243),
        ('64626c14-0111-5c75-852d-fc569c55620e', 'supertuxkart', 'noah_wells', 'Noah Wells', 'One more lap, one more shortcut. Here for quick races and good company.', '64626c14-0111-5c75-852d-fc569c55620e/7e5f2759-50a6-4665-a0bb-3b64cc438f9f.jpg', 'Development Community Noah Wells', 19875),
        ('ab1404ba-918b-5eb8-9e65-3a280321e1c7', 'supertuxkart', 'poppy_lane', 'Poppy Lane', 'Kart races with friends and a little friendly rivalry. Corners are still my weakness.', 'ab1404ba-918b-5eb8-9e65-3a280321e1c7/91ef94e3-5791-5732-9f30-30a48247c38d.jpg', 'Development Community Poppy Lane', 26453),
        ('94c18071-e354-43e5-9596-5ab65eb6d106', 'zenless-zone-zero', 'jade_park', 'Jade Park', 'Exploring New Eridu between coffee breaks. Here for character builds, good clips and chill teammates.', '94c18071-e354-43e5-9596-5ab65eb6d106/7b37d97d-07f9-4d1e-8f9f-72e49680e166.jpg', 'Development TEST Ember', 16157),
        ('864c4d79-7101-51c3-8a47-8aee6df1155c', 'zenless-zone-zero', 'kai_lin', 'Kai Lin', 'Here for smooth dodges, new character builds and a chill chat between runs.', '864c4d79-7101-51c3-8a47-8aee6df1155c/69a8a911-67ca-53b0-996f-265a4e8a76a4.jpg', 'Development Community Kai Lin', 24678),
        ('d7d26b64-6b3d-5715-a78d-49a172682120', 'zenless-zone-zero', 'tessa_morgan', 'Tessa Morgan', 'New Eridu after work. Testing agent teams and saving every good soundtrack.', 'd7d26b64-6b3d-5715-a78d-49a172682120/cc42070d-ef3a-551f-9bff-5a7b24673ee8.jpg', 'Development Community Tessa Morgan', 25357),
        ('2a92931a-1e2a-5ba8-8149-17c2fd3dc9ed', 'zero-ad', 'adrian_vale', 'Adrian Vale', 'History nerd who spends too long planning the base. Casual strategy games after work.', '2a92931a-1e2a-5ba8-8149-17c2fd3dc9ed/7a05824c-1f71-59df-b9a5-4b6c89189c85.jpg', 'Development Community Adrian Vale', 23208),
        ('1df93ea1-76a7-5d65-8841-bc22a4cff5df', 'zero-ad', 'amara_blake', 'Amara Blake', 'Patient openings, messy battles. Learning a new civilization one match at a time.', '1df93ea1-76a7-5d65-8841-bc22a4cff5df/983fae7c-bf24-5823-a80d-5ecb957442db.jpg', 'Development Community Amara Blake', 49900),
        ('a743fd72-2c02-55d0-b5c0-16514d005e05', 'zero-ad', 'theo_grant', 'Theo Grant', 'A strategy game and a cup of tea is a good evening. Happy to swap build orders.', 'a743fd72-2c02-55d0-b5c0-16514d005e05/10d7b4ee-be93-5c90-8d9c-44185f4b3958.jpg', 'Development Community Theo Grant', 28585)
    ) as fixture (id, game_id, handle, display_name, bio, avatar_path, reservation_label, avatar_bytes);

    if pg_catalog.jsonb_array_length(expected_fixtures) <> 36
       or (select count(distinct f.id) from pg_catalog.jsonb_to_recordset(expected_fixtures) as f(id uuid)) <> 36
       or (select count(*) from (
            select f.game_id from pg_catalog.jsonb_to_recordset(expected_fixtures) as f(game_id text)
            group by f.game_id having count(*) = 3
       ) as games_with_complete_rosters) <> 12 then
        raise exception 'Expected 36 fictional players across 12 communities';
    end if;

    -- Match the selected fixture's approved display values and the exact owned
    -- image in private Storage. A changed source must be reviewed before reuse.
    perform p.id
    from pg_catalog.jsonb_to_recordset(expected_fixtures) as e(
        id uuid, game_id text, handle text, display_name text, bio text,
        avatar_path text, reservation_label text, avatar_bytes bigint
    )
    join public.profiles p on p.id = e.id and p.handle = e.handle
        and p.display_name = e.display_name and p.bio = e.bio and p.avatar_path = e.avatar_path
    join private.accounts a on a.user_id = p.id and a.cohort = 'development' and a.state = 'active'
    join private.development_accounts d on d.user_id = p.id and d.enabled and d.label = e.reservation_label
    join public.game_cards gc on gc.user_id = p.id and gc.game_id = e.game_id
    join storage.objects o on o.bucket_id = 'avatars' and o.name = e.avatar_path
        and o.owner_id = e.id::text and o.metadata->>'mimetype' = 'image/jpeg'
        and o.metadata->>'size' = e.avatar_bytes::text
    join storage.buckets b on b.id = o.bucket_id and b.public is false
    order by p.id for share of p, a, d, gc, o, b;
    get diagnostics matched_count = row_count;
    if matched_count <> 36 then
        raise exception 'Community roster, fixture ownership or private avatar baseline changed (% / 36 matched)', matched_count;
    end if;

    insert into private.curated_community_players as published
        (id, game_id, handle, display_name, bio, avatar_path)
    select id, game_id, handle, display_name, bio, avatar_path
    from pg_catalog.jsonb_to_recordset(expected_fixtures) as e(
        id uuid, game_id text, handle text, display_name text, bio text,
        avatar_path text, reservation_label text, avatar_bytes bigint
    )
    where true
    on conflict (id) do update set
        game_id = excluded.game_id, handle = excluded.handle, display_name = excluded.display_name,
        bio = excluded.bio, avatar_path = excluded.avatar_path
    where (published.game_id, published.handle, published.display_name, published.bio, published.avatar_path)
          is distinct from (excluded.game_id, excluded.handle, excluded.display_name, excluded.bio, excluded.avatar_path);

    if (select count(*) from private.curated_community_players c
        join pg_catalog.jsonb_to_recordset(expected_fixtures) as e(
            id uuid, game_id text, handle text, display_name text, bio text, avatar_path text
        ) using (id)
        where (c.game_id, c.handle, c.display_name, c.bio, c.avatar_path)
            = (e.game_id, e.handle, e.display_name, e.bio, e.avatar_path)) <> 36 then
        raise exception 'Curated community player verification failed';
    end if;
end
$publish$;

select count(*)::integer as curated_fixtures, count(distinct game_id)::integer as curated_communities
from private.curated_community_players;
commit;
