-- Regression against the catalog in development-community-comments-2026-11-06.json.
-- All test users, the negative control comment, and the report are rolled back.
begin;
set local plpgsql.check_asserts = on;
set local lock_timeout = '5s';

do $test$
declare
    viewer_a uuid := gen_random_uuid();
    viewer_b uuid := gen_random_uuid();
    session_a uuid := gen_random_uuid();
    session_b uuid := gen_random_uuid();
    curated_clips uuid[] := array[
        '86916319-1668-569a-8fd0-8ff991d483c4',
        'd18a4edb-2345-5269-b1ea-7cb96882f31b',
        '084d6071-d274-52b3-8f24-62b731a741cb',
        'bc761749-e6fd-5f5f-8a1d-4d396ac3d208',
        '89630fe1-6fbe-5d05-aafe-6b29afb38fb5',
        '51628a69-1010-5201-b5bc-20346473161f',
        '6920e768-4d0a-5af1-a003-10ea2eeca518',
        '3f6877fa-0e13-59d4-8316-afafba965d25',
        '0266cd87-d7a3-53a6-8a08-6f454c48a6a5',
        '2e2427e1-3045-5770-8217-f47fe942efa1'
    ]::uuid[];
    curated_clip uuid;
    report_clip uuid := curated_clips[1];
    report_comment uuid := 'cee1820a-de53-5ebf-9392-e5f35e854d0c';
    unlisted_comment uuid := gen_random_uuid();
    real_author uuid;
    comments jsonb;
    state jsonb;
    count_before bigint;
begin
    select c.author_id into strict real_author from private.clip_comments c
    where c.clip_id=report_clip and c.id=report_comment and c.status='approved';
    insert into auth.users(id,aud,role,is_anonymous) values
        (viewer_a,'authenticated','authenticated',true),(viewer_b,'authenticated','authenticated',true);
    insert into auth.sessions(id,user_id) values(session_a,viewer_a),(session_b,viewer_b);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),session_a,'anonymous',now(),now()),(gen_random_uuid(),session_b,'anonymous',now(),now());
    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',viewer_a,'role','authenticated','session_id',session_a,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.session_context()->>'is_experience'='true','A is a standard one-tap experience account';
    assert not exists(select 1 from public.profiles where id=real_author),'Private development profile remains hidden';

    foreach curated_clip in array curated_clips loop
        comments := public.clip_comments(curated_clip);
        state := public.clip_social_state(curated_clip);
        assert state->'uploader'='null'::jsonb,'Curated media still does not expose the uploader profile';
        assert (select count(*) from jsonb_array_elements(comments) c where c->'is_sample'='true'::jsonb)=6,
            format('Expected six approved sample comments on %s',curated_clip);
        assert not exists(
            select 1 from jsonb_array_elements(comments) c where c->'is_sample'='true'::jsonb
            and (c->>'status' is distinct from 'approved' or c->>'clip_id' is distinct from curated_clip::text
              or c#>>'{author,id}' is distinct from c->>'id' or c#>>'{author,handle}' is distinct from 'sample'
              or c#>>'{author,bio}' is distinct from '' or c#>'{author,avatar_path}' is distinct from 'null'::jsonb
              or right(c#>>'{author,display_name}',9) is distinct from ' · Sample')
        ),'Sample comments only expose the display credit and their own comment ID';
        assert (state->>'comment_count')::bigint>=6,'Social count includes the approved samples';
    end loop;

    count_before := (public.clip_social_state(report_clip)->>'comment_count')::bigint;
    reset role;
    insert into private.clip_comments(id,clip_id,author_id,body,status,approved_at) values
        (unlisted_comment,report_clip,real_author,'Unlisted development comment','approved',now());
    set local role authenticated;

    comments := public.clip_comments(report_clip);
    assert comments @> jsonb_build_array(jsonb_build_object('id',report_comment,'is_sample',true)),
        'Known approved sample is visible';
    assert not comments @> jsonb_build_array(jsonb_build_object('id',unlisted_comment)),
        'An unlisted approved comment from the same development author stays private';
    assert (public.clip_social_state(report_clip)->>'comment_count')::bigint=count_before,
        'An unlisted development comment does not change the public count';
    begin
        perform public.submit_content_report('comment',unlisted_comment,'spam');
        raise exception 'Hidden unlisted comment was reportable';
    exception when insufficient_privilege then
        assert sqlerrm='report_target_unavailable';
    end;
    assert public.submit_content_report('comment',report_comment,'spam'),'Visible sample can be reported';
    assert not public.submit_content_report('comment',report_comment,'spam'),'Report retry is deduplicated';
    assert not public.clip_comments(report_clip) @> jsonb_build_array(jsonb_build_object('id',report_comment)),
        'Reported sample disappears for the reporter';
    assert (public.clip_social_state(report_clip)->>'comment_count')::bigint=count_before-1,
        'Only the reported item is removed from the reporter count';
    reset role;

    assert exists(select 1 from private.content_reports where reporter_id=viewer_a
        and target_type='comment' and target_id=report_comment and subject_id=real_author),
        'The private review queue links the report to the real author';
    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',viewer_b,'role','authenticated','session_id',session_b,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.clip_comments(report_clip) @> jsonb_build_array(jsonb_build_object('id',report_comment,'is_sample',true)),
        'A second experience account still sees the sample';
    assert (public.clip_social_state(report_clip)->>'comment_count')::bigint=count_before,
        'A second experience account keeps its original count';
    reset role;
end $test$;

rollback;
