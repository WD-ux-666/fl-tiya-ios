-- Opt in the 36 existing fictional likes recorded in the 2026-11-09 Home fixture manifest.
-- Match the exact like and the approved clip's original publisher. No likes are created.
begin;

do $publish$
declare matched_count integer; matched_clips integer;
begin
    with fixtures(clip_id,publisher_id,liker_id) as (
        values
        ('86916319-1668-569a-8fd0-8ff991d483c4','94c18071-e354-43e5-9596-5ab65eb6d106','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('86916319-1668-569a-8fd0-8ff991d483c4','94c18071-e354-43e5-9596-5ab65eb6d106','e53c8f39-87c4-5d03-b324-722c2044301c'),
        ('d18a4edb-2345-5269-b1ea-7cb96882f31b','ceb6b030-1b86-49c7-af0d-09fc2db576d8','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('d18a4edb-2345-5269-b1ea-7cb96882f31b','ceb6b030-1b86-49c7-af0d-09fc2db576d8','19dbbc8f-5796-527c-9a2b-1bd882fab368'),
        ('084d6071-d274-52b3-8f24-62b731a741cb','aa182005-e481-4df2-a56f-09ee60da7f5b','3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0'),
        ('084d6071-d274-52b3-8f24-62b731a741cb','aa182005-e481-4df2-a56f-09ee60da7f5b','e53c8f39-87c4-5d03-b324-722c2044301c'),
        ('bc761749-e6fd-5f5f-8a1d-4d396ac3d208','94c18071-e354-43e5-9596-5ab65eb6d106','a743fd72-2c02-55d0-b5c0-16514d005e05'),
        ('bc761749-e6fd-5f5f-8a1d-4d396ac3d208','94c18071-e354-43e5-9596-5ab65eb6d106','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('bc761749-e6fd-5f5f-8a1d-4d396ac3d208','94c18071-e354-43e5-9596-5ab65eb6d106','59bc0e8f-d247-582f-856d-6f3ed13de457'),
        ('bc761749-e6fd-5f5f-8a1d-4d396ac3d208','94c18071-e354-43e5-9596-5ab65eb6d106','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('89630fe1-6fbe-5d05-aafe-6b29afb38fb5','ceb6b030-1b86-49c7-af0d-09fc2db576d8','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('89630fe1-6fbe-5d05-aafe-6b29afb38fb5','ceb6b030-1b86-49c7-af0d-09fc2db576d8','59bc0e8f-d247-582f-856d-6f3ed13de457'),
        ('89630fe1-6fbe-5d05-aafe-6b29afb38fb5','ceb6b030-1b86-49c7-af0d-09fc2db576d8','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('89630fe1-6fbe-5d05-aafe-6b29afb38fb5','ceb6b030-1b86-49c7-af0d-09fc2db576d8','42f543fd-aa4b-5b36-9d83-9f0dae503523'),
        ('89630fe1-6fbe-5d05-aafe-6b29afb38fb5','ceb6b030-1b86-49c7-af0d-09fc2db576d8','e53c8f39-87c4-5d03-b324-722c2044301c'),
        ('51628a69-1010-5201-b5bc-20346473161f','aa182005-e481-4df2-a56f-09ee60da7f5b','a743fd72-2c02-55d0-b5c0-16514d005e05'),
        ('51628a69-1010-5201-b5bc-20346473161f','aa182005-e481-4df2-a56f-09ee60da7f5b','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('51628a69-1010-5201-b5bc-20346473161f','aa182005-e481-4df2-a56f-09ee60da7f5b','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('51628a69-1010-5201-b5bc-20346473161f','aa182005-e481-4df2-a56f-09ee60da7f5b','3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0'),
        ('51628a69-1010-5201-b5bc-20346473161f','aa182005-e481-4df2-a56f-09ee60da7f5b','42f543fd-aa4b-5b36-9d83-9f0dae503523'),
        ('6920e768-4d0a-5af1-a003-10ea2eeca518','94c18071-e354-43e5-9596-5ab65eb6d106','19dbbc8f-5796-527c-9a2b-1bd882fab368'),
        ('6920e768-4d0a-5af1-a003-10ea2eeca518','94c18071-e354-43e5-9596-5ab65eb6d106','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('6920e768-4d0a-5af1-a003-10ea2eeca518','94c18071-e354-43e5-9596-5ab65eb6d106','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('6920e768-4d0a-5af1-a003-10ea2eeca518','94c18071-e354-43e5-9596-5ab65eb6d106','e53c8f39-87c4-5d03-b324-722c2044301c'),
        ('6920e768-4d0a-5af1-a003-10ea2eeca518','94c18071-e354-43e5-9596-5ab65eb6d106','59bc0e8f-d247-582f-856d-6f3ed13de457'),
        ('3f6877fa-0e13-59d4-8316-afafba965d25','ceb6b030-1b86-49c7-af0d-09fc2db576d8','19dbbc8f-5796-527c-9a2b-1bd882fab368'),
        ('3f6877fa-0e13-59d4-8316-afafba965d25','ceb6b030-1b86-49c7-af0d-09fc2db576d8','3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0'),
        ('3f6877fa-0e13-59d4-8316-afafba965d25','ceb6b030-1b86-49c7-af0d-09fc2db576d8','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('0266cd87-d7a3-53a6-8a08-6f454c48a6a5','aa182005-e481-4df2-a56f-09ee60da7f5b','19dbbc8f-5796-527c-9a2b-1bd882fab368'),
        ('0266cd87-d7a3-53a6-8a08-6f454c48a6a5','aa182005-e481-4df2-a56f-09ee60da7f5b','3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0'),
        ('0266cd87-d7a3-53a6-8a08-6f454c48a6a5','aa182005-e481-4df2-a56f-09ee60da7f5b','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('0266cd87-d7a3-53a6-8a08-6f454c48a6a5','aa182005-e481-4df2-a56f-09ee60da7f5b','ab1404ba-918b-5eb8-9e65-3a280321e1c7'),
        ('2e2427e1-3045-5770-8217-f47fe942efa1','94c18071-e354-43e5-9596-5ab65eb6d106','3660aa03-79e5-5e53-a8dc-e9e8fe0c29c0'),
        ('2e2427e1-3045-5770-8217-f47fe942efa1','94c18071-e354-43e5-9596-5ab65eb6d106','e53c8f39-87c4-5d03-b324-722c2044301c'),
        ('2e2427e1-3045-5770-8217-f47fe942efa1','94c18071-e354-43e5-9596-5ab65eb6d106','1c1594bf-d7f4-5d06-8bb9-be3507e9ea48'),
        ('2e2427e1-3045-5770-8217-f47fe942efa1','94c18071-e354-43e5-9596-5ab65eb6d106','19dbbc8f-5796-527c-9a2b-1bd882fab368')
    ), matched as (
        select l.clip_id,l.user_id
        from fixtures f
        join private.clip_likes l on l.clip_id=f.clip_id::uuid and l.user_id=f.liker_id::uuid
        join public.video_posts v on v.id=l.clip_id and v.owner_id=f.publisher_id::uuid and v.status='approved'
        join private.accounts liker on liker.user_id=l.user_id and liker.cohort='development' and liker.state='active'
        join private.accounts publisher on publisher.user_id=v.owner_id
            and publisher.cohort='development' and publisher.state='active'
    ), published as (
        insert into private.curated_clip_likes (clip_id,user_id)
        select clip_id,user_id from matched
        on conflict (clip_id,user_id) do nothing
    )
    select count(*),count(distinct clip_id) into matched_count,matched_clips from matched;

    if matched_count <> 36 or matched_clips <> 10 then
        raise exception 'Curated like import expected 36 existing likes across 10 approved clips, found % across %',
            matched_count,matched_clips;
    end if;
end $publish$;

commit;
