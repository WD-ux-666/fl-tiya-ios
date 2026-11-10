-- Opt in the 60 existing moderated fictional comments from the two 2026-11-06 manifests.
-- Match the original post, author and body as well as the ID before publishing a display credit.
-- Running the seed again is safe. It does not create any comments or auth accounts.
begin;
do $$
declare matched_count integer;
begin
    with fixtures(comment_id,clip_id,author_id,body,display_name) as (
        values
        ('c8e8a2df-3dcb-5ca9-9d31-239a2afe504d', '86916319-1668-569a-8fd0-8ff991d483c4', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'Erangel always makes me want to queue for another match.', 'Nina Vega'),
        ('966598e7-dfdc-57ab-962a-ef76dcfd528d', '86916319-1668-569a-8fd0-8ff991d483c4', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'Would you drop at the plaza or play the edge of the zone?', 'Leo Brooks'),
        ('aa1277bb-ee62-5b11-95c5-247133ac13a2', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', '94c18071-e354-43e5-9596-5ab65eb6d106', 'The caption made me laugh.', 'Jade Park'),
        ('089134ab-6f61-51a8-bd2c-ee327055bcfe', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'Short clips like this are an easy mood boost.', 'Nina Vega'),
        ('bf57bfa5-bf94-5e91-a6e2-93eaf1b6510d', '084d6071-d274-52b3-8f24-62b731a741cb', '94c18071-e354-43e5-9596-5ab65eb6d106', 'Minecraft always gives me a new idea for a build.', 'Jade Park'),
        ('4bea5188-a3e8-55ff-8c77-ce01984eda8f', '084d6071-d274-52b3-8f24-62b731a741cb', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'Survival run or creative build next?', 'Leo Brooks'),
        ('79314773-964c-58a4-bb64-63c17cf1ce89', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'That banana split caption is the best part.', 'Nina Vega'),
        ('41e41b68-c02f-5142-a722-afff8ccc7aa8', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'The hat has officially become the main character.', 'Leo Brooks'),
        ('8181d4e9-2fc5-5a1a-a7f7-b98ee14b16f1', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', '94c18071-e354-43e5-9596-5ab65eb6d106', 'The impossible architecture makes this game so intriguing.', 'Jade Park'),
        ('881b0fa9-4f4f-5649-930c-ed2df049b63e', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'I would happily get lost exploring a place like this.', 'Nina Vega'),
        ('1baf695d-33fb-5297-8649-fc7690946469', '51628a69-1010-5201-b5bc-20346473161f', '94c18071-e354-43e5-9596-5ab65eb6d106', 'The ''which one is best'' question is harder than it sounds.', 'Jade Park'),
        ('c55d3de5-3543-5723-8cab-8adcd047e788', '51628a69-1010-5201-b5bc-20346473161f', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'Fun idea for a quick style comparison.', 'Leo Brooks'),
        ('418cde10-78eb-5c5c-b5bf-ba6e247c3773', '6920e768-4d0a-5af1-a003-10ea2eeca518', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'Combat and platforming make such a good combo.', 'Nina Vega'),
        ('81e51ba2-4ea0-5999-be77-7d9f8bc67120', '6920e768-4d0a-5af1-a003-10ea2eeca518', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'Guacamelee has such a distinctive art style.', 'Leo Brooks'),
        ('68d11a94-4c3f-5323-b2f6-d352f691e466', '3f6877fa-0e13-59d4-8316-afafba965d25', '94c18071-e354-43e5-9596-5ab65eb6d106', 'Keeping this one for a quick scrolling break.', 'Jade Park'),
        ('fe97c24a-2ac8-5b44-b609-7f03a46101bf', '3f6877fa-0e13-59d4-8316-afafba965d25', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'More short clips from this creator would be fun.', 'Nina Vega'),
        ('b76d9635-09cc-57e9-b76a-d9a82e8ffa84', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', '94c18071-e354-43e5-9596-5ab65eb6d106', 'Kart races are better with a little friendly rivalry.', 'Jade Park'),
        ('ce5c4d44-18de-5872-ac8e-3c92d93cbdfd', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'Who would you challenge to a race?', 'Leo Brooks'),
        ('b4b54da9-5e29-5c8d-913e-8dea9fc0c23b', '2e2427e1-3045-5770-8217-f47fe942efa1', 'aa182005-e481-4df2-a56f-09ee60da7f5b', 'The ''unforgettable'' caption says it all.', 'Nina Vega'),
        ('b793b85e-7b03-5dee-a10e-00323f9cdb05', '2e2427e1-3045-5770-8217-f47fe942efa1', 'ceb6b030-1b86-49c7-af0d-09fc2db576d8', 'A little change of pace between gaming clips.', 'Leo Brooks'),
        ('cee1820a-de53-5ebf-9392-e5f35e854d0c', '86916319-1668-569a-8fd0-8ff991d483c4', 'd7d26b64-6b3d-5715-a78d-49a172682120', 'The plaza looks like a fun place for the squad to land.', 'Tessa Morgan'),
        ('5e16856f-1966-5f31-ac39-efc5e4b66225', '86916319-1668-569a-8fd0-8ff991d483c4', '864c4d79-7101-51c3-8a47-8aee6df1155c', 'I would probably spend the whole match checking out the new area.', 'Kai Lin'),
        ('e216ac5f-af00-5c38-a0e4-59232a1009b3', '86916319-1668-569a-8fd0-8ff991d483c4', '17dcccdf-50cf-5e79-ba6d-14693bcea1c0', 'Saving this for our next Erangel session.', 'Zara Hayes'),
        ('4f86ab53-5b09-5f25-aec3-c27d91ae58b0', '86916319-1668-569a-8fd0-8ff991d483c4', 'a6aff5c5-0e13-5a56-bf28-41685cb89100', 'Do you prefer a busy drop or a quiet start?', 'Marcus Reed'),
        ('9c00a510-5e5f-5686-8193-6c00ff91b6dd', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', '1c1594bf-d7f4-5d06-8bb9-be3507e9ea48', 'The caption is way too relatable.', 'Owen Brooks'),
        ('435fe433-9233-55f0-b351-c1684b3e4f06', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', 'e7e975f1-b08a-596d-8df8-df9f5bdda8c1', 'A little change of pace between game clips.', 'Chloe Bennett'),
        ('bb261c21-728b-528f-8583-366a5b288229', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', 'ccfc933b-dba2-55ef-92ee-47ab6fe85467', 'This has such a relaxed vibe.', 'Ava Sterling'),
        ('5895ed50-b101-58d9-92cb-6d5dcccf0b5f', 'd18a4edb-2345-5269-b1ea-7cb96882f31b', 'e53c8f39-87c4-5d03-b324-722c2044301c', 'I was not expecting this in my scrolling break.', 'Felix Quinn'),
        ('59ed960f-b5a1-5de4-861f-4d7e3a3dcb17', '084d6071-d274-52b3-8f24-62b731a741cb', '4db6ec84-3240-5fb7-8de6-95ad6bda6191', 'This makes me want to start a fresh survival world.', 'Sofia Hart'),
        ('d22ddf7b-f24f-5ba2-96ef-6144133a6b2c', '084d6071-d274-52b3-8f24-62b731a741cb', '256e3201-3934-5ae7-804a-02186ad08eec', 'A small cabin by the water would be my first project.', 'Diego Cruz'),
        ('892be7a4-cef3-5153-95dd-4ad76ff5ad19', '084d6071-d274-52b3-8f24-62b731a741cb', '42f543fd-aa4b-5b36-9d83-9f0dae503523', 'Every Minecraft clip adds another idea to my build list.', 'Ruby Navarro'),
        ('a133c90b-c92d-592b-8c40-ab8bbe301076', '084d6071-d274-52b3-8f24-62b731a741cb', '64428a1b-6ad1-5461-baf2-7f50d94b4b20', 'Exploring with a friend is still my favorite way to play.', 'Max Turner'),
        ('2289085a-e993-5744-8ad6-ec546009a29a', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', '2a92931a-1e2a-5ba8-8149-17c2fd3dc9ed', 'The hat really got its own storyline.', 'Adrian Vale'),
        ('75e193ed-7b8c-5269-a615-d83280360c01', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', '1df93ea1-76a7-5d65-8841-bc22a4cff5df', 'Now I am thinking about a banana split.', 'Amara Blake'),
        ('c1e6f346-6402-5e59-a625-b6877e221bc1', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', 'a743fd72-2c02-55d0-b5c0-16514d005e05', 'That caption made me stop scrolling.', 'Theo Grant'),
        ('30fcfd71-dc69-5894-9c01-4510f959443f', 'bc761749-e6fd-5f5f-8a1d-4d396ac3d208', 'ab1404ba-918b-5eb8-9e65-3a280321e1c7', 'A good reminder to keep things playful.', 'Poppy Lane'),
        ('9710c0ec-26e7-531d-b071-934338ae38d0', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', '64626c14-0111-5c75-852d-fc569c55620e', 'I keep trying to work out which way is up.', 'Noah Wells'),
        ('a8f85cba-7e58-5cd9-b9dd-4c43c349b497', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', '54ea5a01-bbcc-5349-940c-a58264b628ed', 'The architecture is such a good reason to take your time.', 'Isla Fox'),
        ('bc01217b-2e00-5729-92bc-aa439bc3c0b6', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', '919c7892-d739-581b-8df0-9ff8d75c51c7', 'This belongs on my next puzzle-game night list.', 'Milo Stone'),
        ('d52717e7-08a6-5bfe-bb5d-4057bba002d4', '89630fe1-6fbe-5d05-aafe-6b29afb38fb5', '1f3a575d-5ba3-5073-98ae-7b1b5af41850', 'I would love to explore this world without rushing.', 'Aria Finch'),
        ('e17b1329-af6f-55d4-bb68-a579fed4b64d', '51628a69-1010-5201-b5bc-20346473161f', '499cdd5d-28f4-58ae-befe-eb13bd0fcc31', 'I would need to watch twice before picking a favorite.', 'Ben Ellis'),
        ('121b6ddc-fdd9-5a2d-a4f4-0ec36bb4d2cc', '51628a69-1010-5201-b5bc-20346473161f', 'dc7e5f57-b1ed-5c06-bf84-5fec2ce9635a', 'The outfit question is harder than I expected.', 'Luca West'),
        ('9be7bcd7-f4c7-53f0-84a9-949fa2e4b96e', '51628a69-1010-5201-b5bc-20346473161f', '5b0dc3ad-4518-55d0-8488-3628d86cacdf', 'Sending this to the friend who always helps me choose.', 'Emma Rowan'),
        ('bcf537cc-3d80-597b-ac48-51af1fb31135', '51628a69-1010-5201-b5bc-20346473161f', '59bc0e8f-d247-582f-856d-6f3ed13de457', 'A quick style break before the next match.', 'Ezra Cole'),
        ('99195166-01db-5f07-b29b-98a587ed3918', '6920e768-4d0a-5af1-a003-10ea2eeca518', '3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0', 'The colors make this stand out while scrolling.', 'Iris Shaw'),
        ('9f236639-2b34-5189-bc37-7c7ae6745b88', '6920e768-4d0a-5af1-a003-10ea2eeca518', '73942806-20d7-54c8-bc77-1419d1bd9d7c', 'Looks like a great pick for a platforming evening.', 'Sam Archer'),
        ('b64669d0-69ca-5d05-9aba-8af949686cf3', '6920e768-4d0a-5af1-a003-10ea2eeca518', '19dbbc8f-5796-527c-9a2b-1bd882fab368', 'Those movement combos seem fun to learn.', 'Leah Quinn'),
        ('83ed8fcd-56e1-50d5-8975-0d868065d6f5', '6920e768-4d0a-5af1-a003-10ea2eeca518', '97dd6a5a-0881-51ae-b6f7-e2aee09754a8', 'Adding this to the list for our next co-op session.', 'Dante Knox'),
        ('d1612f90-cdad-5bff-9dc5-f686274a0433', '3f6877fa-0e13-59d4-8316-afafba965d25', '786fc76d-1070-55b4-81ef-30a08dcdae4e', 'This is the kind of clip I share with the group chat.', 'Naomi Chase'),
        ('093759fe-1e95-5039-8557-afd306604241', '3f6877fa-0e13-59d4-8316-afafba965d25', '52ae9afd-9819-5727-bd73-3b20c9d21168', 'A cheerful little break in the feed.', 'Alex Rivers'),
        ('1a8a1f57-5274-5fc5-8727-2e8c0dd19736', '3f6877fa-0e13-59d4-8316-afafba965d25', '94ad5bcf-2ebf-5c3a-8f02-d8966fe5f83e', 'Keeping this one for when I need a quick smile.', 'Mina Flores'),
        ('bcc78755-0960-5f84-8d9b-f60385861c4a', '3f6877fa-0e13-59d4-8316-afafba965d25', '1dbb484e-a71d-51d2-832a-d568267dd417', 'Back to gaming after one more scroll, probably.', 'Caleb Price'),
        ('16584752-4079-5a33-b508-35063af1432d', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', '969d3d84-0bd4-581b-9321-05f027434932', 'This is exactly the kind of game our group gets too competitive about.', 'Zoe Avery'),
        ('d4eb5352-4f0c-5220-80f1-2beb86ede573', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', 'd7d26b64-6b3d-5715-a78d-49a172682120', 'A quick kart race always turns into a whole evening.', 'Tessa Morgan'),
        ('57b896a3-9442-5ce7-89e7-0e66a6ed01a4', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', '864c4d79-7101-51c3-8a47-8aee6df1155c', 'Who is your favorite racer to pick?', 'Kai Lin'),
        ('1d2a263b-25b1-5ef0-85d8-bce5a442ba90', '0266cd87-d7a3-53a6-8a08-6f454c48a6a5', '17dcccdf-50cf-5e79-ba6d-14693bcea1c0', 'The perfect excuse for one more lap.', 'Zara Hayes'),
        ('d89e5bb2-15c0-545c-acfe-e821a306f6a3', '2e2427e1-3045-5770-8217-f47fe942efa1', 'a6aff5c5-0e13-5a56-bf28-41685cb89100', 'The caption has me curious now.', 'Marcus Reed'),
        ('7b7ded3d-adf0-564f-8db6-3a87af573add', '2e2427e1-3045-5770-8217-f47fe942efa1', '1c1594bf-d7f4-5d06-8bb9-be3507e9ea48', 'A nice switch from all the match highlights.', 'Owen Brooks'),
        ('7d2ccbfc-0b58-514f-b420-05f60652bace', '2e2427e1-3045-5770-8217-f47fe942efa1', 'e7e975f1-b08a-596d-8df8-df9f5bdda8c1', 'This is easy to watch on a short break.', 'Chloe Bennett'),
        ('4be087ad-379b-5ad2-a290-b5ab7e8fbc69', '2e2427e1-3045-5770-8217-f47fe942efa1', 'ccfc933b-dba2-55ef-92ee-47ab6fe85467', 'My feed needed a little variety today.', 'Ava Sterling')
    ), matched as (
        select c.id, f.display_name
        from fixtures f
        join private.clip_comments c on c.id=f.comment_id::uuid and c.clip_id=f.clip_id::uuid
            and c.author_id=f.author_id::uuid and c.body=f.body and c.status='approved'
        join public.video_posts v on v.id=c.clip_id and v.status='approved'
        join private.accounts author on author.user_id=c.author_id and author.cohort='development' and author.state='active'
        join private.accounts publisher on publisher.user_id=v.owner_id and publisher.cohort='development' and publisher.state='active'
    ), published as (
        insert into private.curated_clip_comment_credits as credits (comment_id,display_name)
        select id, display_name from matched
        on conflict (comment_id) do update set display_name=excluded.display_name
        where credits.display_name is distinct from excluded.display_name
    )
    select count(*) into matched_count from matched;
    if matched_count <> 60 then
        raise exception 'Curated comment import expected 60 matching approved comments, found %',matched_count;
    end if;
end $$;
commit;
