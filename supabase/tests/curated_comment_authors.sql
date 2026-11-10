-- Synthetic data only. Proves the comment response links to reviewed samples without exposing the underlying profile.
begin;
set local plpgsql.check_asserts = on;
set local lock_timeout = '5s';

do $test$
declare
    viewer uuid := gen_random_uuid(); peer uuid := gen_random_uuid();
    owner uuid := gen_random_uuid(); mapped_author uuid := gen_random_uuid();
    unmapped_author uuid := gen_random_uuid();
    viewer_session uuid := gen_random_uuid(); peer_session uuid := gen_random_uuid();
    owner_session uuid := gen_random_uuid();
    clip uuid := gen_random_uuid(); mapped_comment uuid := gen_random_uuid();
    unmapped_comment uuid := gen_random_uuid(); unlisted_comment uuid := gen_random_uuid();
    real_comment uuid := gen_random_uuid();
    game text := 'zenless-zone-zero';
    reviewed_handle text := 'sample_' || replace(gen_random_uuid()::text,'-','');
    reviewed_avatar text := mapped_author || '/' || gen_random_uuid() || '.jpg';
    private_avatar text := mapped_author || '/' || gen_random_uuid() || '.jpg';
    comments jsonb; item jsonb;
begin
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
    select id,'fixture-'||id||'@development.invalid','Curated comment author fixture',
        encode(extensions.digest(id::text,'sha256'),'hex'),now()+interval '1 hour'
    from unnest(array[owner,mapped_author,unmapped_author]) d(id);
    insert into auth.users(id,aud,role,is_anonymous) values
        (viewer,'authenticated','authenticated',true),(peer,'authenticated','authenticated',true);
    insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous)
    select id,'authenticated','authenticated','fixture-'||id||'@development.invalid',now(),false
    from unnest(array[owner,mapped_author,unmapped_author]) d(id);
    insert into auth.identities(provider_id,user_id,identity_data,provider)
    select id::text,id,jsonb_build_object('sub',id,'email','fixture-'||id||'@development.invalid'),'email'
    from unnest(array[owner,mapped_author,unmapped_author]) d(id);
    insert into auth.sessions(id,user_id) values
        (viewer_session,viewer),(peer_session,peer),(owner_session,owner);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),viewer_session,'anonymous',now(),now()),
        (gen_random_uuid(),peer_session,'anonymous',now(),now()),
        (gen_random_uuid(),owner_session,'password',now(),now());
    update public.profiles set display_name='Private development name',
        bio='Private development bio',avatar_path=private_avatar where id=mapped_author;
    insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at)
    values (clip,owner,game,owner||'/'||clip||'/video.mp4','approved',now());
    insert into private.clip_comments(id,clip_id,author_id,body,status,approved_at) values
        (mapped_comment,clip,mapped_author,'Reviewed comment with community profile','approved',now()),
        (unmapped_comment,clip,unmapped_author,'Reviewed comment without community profile','approved',now()),
        (unlisted_comment,clip,mapped_author,'Unreviewed for publication','approved',now()),
        (real_comment,clip,peer,'Real viewer comment','approved',now());
    insert into private.curated_clip_comment_credits(comment_id,display_name) values
        (mapped_comment,'Reviewed name'),(unmapped_comment,'Unmapped name');
    insert into private.curated_community_players(id,game_id,handle,display_name,bio,avatar_path) values
        (mapped_author,game,reviewed_handle,'Reviewed name','Reviewed bio',reviewed_avatar);

    perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated',
        'session_id',viewer_session,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.session_context()->>'is_experience'='true','Viewer is a standard one-tap account';
    comments := public.clip_comments(clip);
    select entry into strict item from jsonb_array_elements(comments) rows(entry)
        where entry->>'id'=mapped_comment::text;
    assert item->>'sample_handle'=reviewed_handle and item->>'sample_game_id'=game,
        'A curated comment links to the exact reviewed community sample';
    assert item->'is_sample'='true'::jsonb and item->'author'=jsonb_build_object(
        'id',mapped_comment,'handle','sample','display_name','Reviewed name · Sample','bio','','avatar_path',null),
        'The original author envelope remains a safe pseudonym';
    assert strpos(item::text,mapped_author::text)=0 and strpos(item::text,private_avatar)=0
        and strpos(item::text,reviewed_avatar)=0 and strpos(item::text,'Private development')=0,
        'The comment endpoint never leaks the underlying user ID, raw paths or profile';
    assert (select count(*) from public.discover_community_players(game,reviewed_handle) d
        where d.is_sample and d.sample_game_id=game and lower(d.handle)=lower(reviewed_handle)
          and d.avatar_path=reviewed_avatar)=1,
        'The exact visible sample is separately authorized and resolves to its reviewed photo';
    assert not exists(select 1 from public.profiles where id=mapped_author),
        'The account still cannot read the underlying development profile';
    assert not comments @> jsonb_build_array(jsonb_build_object('id',unlisted_comment)),
        'An unlisted comment by an otherwise reviewed author stays private';
    select entry into strict item from jsonb_array_elements(comments) rows(entry)
        where entry->>'id'=unmapped_comment::text;
    assert item->'is_sample'='true'::jsonb and not (item ?| array['sample_handle','sample_game_id']),
        'A curated comment without a reviewed community profile keeps the old fallback';
    select entry into strict item from jsonb_array_elements(comments) rows(entry)
        where entry->>'id'=real_comment::text;
    assert item#>>'{author,id}'=peer::text and not (item ?| array['sample_handle','sample_game_id','is_sample']),
        'Real viewer comments keep the normal author and no sample fields';
    assert public.clip_social_state(clip)->>'comment_count'='3','Visible count is unchanged';
    reset role;

    insert into private.curated_community_players(id,game_id,handle,display_name,bio,avatar_path) values
        (unmapped_author,game,upper(reviewed_handle),'Ambiguous name','Ambiguous bio',
        unmapped_author || '/' || gen_random_uuid() || '.jpg');
    set local role authenticated;
    select entry into strict item from jsonb_array_elements(public.clip_comments(clip)) rows(entry)
        where entry->>'id'=mapped_comment::text;
    assert not (item ?| array['sample_handle','sample_game_id']),
        'An ambiguous case-insensitive handle does not link to a different profile';
    reset role;
    delete from private.curated_community_players where id=unmapped_author;

    insert into public.blocks(owner_id,blocked_id) values(mapped_author,viewer);
    set local role authenticated;
    assert not public.clip_comments(clip) @> jsonb_build_array(jsonb_build_object('id',mapped_comment))
        and public.clip_social_state(clip)->>'comment_count'='2',
        'An existing reverse block still hides the comment and count';
    reset role;
    delete from public.blocks where owner_id=mapped_author and blocked_id=viewer;
    set local role authenticated;
    perform public.block_user(mapped_author);
    assert not public.clip_comments(clip) @> jsonb_build_array(jsonb_build_object('id',mapped_comment)),
        'Blocking a sample still hides its curated comments';
    perform public.unblock_user(mapped_author);
    assert public.submit_content_report('comment',mapped_comment,'spam'),'A visible sample can be reported';
    assert not public.clip_comments(clip) @> jsonb_build_array(jsonb_build_object('id',mapped_comment))
        and public.clip_social_state(clip)->>'comment_count'='2',
        'A report still hides only the specific comment for the reporting viewer';
    reset role;
    assert exists(select 1 from private.content_reports
        where reporter_id=viewer and target_id=mapped_comment and subject_id=mapped_author),
        'Private moderation can still identify the underlying author';

    perform set_config('request.jwt.claims',jsonb_build_object('sub',peer,'role','authenticated',
        'session_id',peer_session,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.clip_comments(clip) @> jsonb_build_array(jsonb_build_object(
        'id',mapped_comment,'sample_handle',reviewed_handle,'sample_game_id',game))
        and public.clip_social_state(clip)->>'comment_count'='3',
        'A separate viewer retains the sample after another viewer reports it';
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',owner,'role','authenticated',
        'session_id',owner_session,'is_anonymous',false)::text,true);
    set local role authenticated;
    select entry into strict item from jsonb_array_elements(public.clip_comments(clip)) rows(entry)
        where entry->>'id'=mapped_comment::text;
    assert item#>>'{author,id}'=mapped_author::text and item#>>'{author,avatar_path}'=private_avatar
        and not (item ?| array['sample_handle','sample_game_id','is_sample']),
        'Development cohort still sees its regular author profile';
    reset role;
end $test$;

rollback;
