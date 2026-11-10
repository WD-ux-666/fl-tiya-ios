-- Synthetic accounts, clips and likes. Nothing persists after this test.
begin;
set local plpgsql.check_asserts = on;

do $test$
declare
    viewer uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); verified uuid:=gen_random_uuid();
    owner uuid:=gen_random_uuid(); liker uuid:=gen_random_uuid();
    viewer_session uuid:=gen_random_uuid(); peer_session uuid:=gen_random_uuid();
    verified_session uuid:=gen_random_uuid(); owner_session uuid:=gen_random_uuid();
    shared_clip uuid:=gen_random_uuid(); unlisted_clip uuid:=gen_random_uuid();
    pending_clip uuid:=gen_random_uuid();
    state jsonb;
begin
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
    select id,'fixture-'||id||'@development.invalid','Curated likes fixture',
        encode(extensions.digest(id::text,'sha256'),'hex'),now()+interval '1 hour'
    from unnest(array[owner,liker]) d(id);
    insert into auth.users(id,aud,role,is_anonymous) values
        (viewer,'authenticated','authenticated',true),(peer,'authenticated','authenticated',true),
        (verified,'authenticated','authenticated',false);
    insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous)
    select id,'authenticated','authenticated','fixture-'||id||'@development.invalid',now(),false
    from unnest(array[owner,liker]) d(id);
    insert into auth.identities(provider_id,user_id,identity_data,provider) values
        (owner::text,owner,jsonb_build_object('sub',owner),'email'),
        (liker::text,liker,jsonb_build_object('sub',liker),'email'),
        (verified::text,verified,jsonb_build_object('sub',verified),'apple');
    insert into auth.sessions(id,user_id) values
        (viewer_session,viewer),(peer_session,peer),(verified_session,verified),(owner_session,owner);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),viewer_session,'anonymous',now(),now()),
        (gen_random_uuid(),peer_session,'anonymous',now(),now()),
        (gen_random_uuid(),verified_session,'oauth',now(),now()),
        (gen_random_uuid(),owner_session,'password',now(),now());
    insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at) values
        (shared_clip,owner,'zenless-zone-zero',owner||'/'||shared_clip||'/video.mp4','approved',now()),
        (unlisted_clip,owner,'zenless-zone-zero',owner||'/'||unlisted_clip||'/video.mp4','approved',now()),
        (pending_clip,owner,'zenless-zone-zero',owner||'/'||pending_clip||'/video.mp4','pending',null);
    insert into private.clip_likes(clip_id,user_id) values
        (shared_clip,liker),(shared_clip,owner),(unlisted_clip,liker),(pending_clip,liker);
    insert into private.curated_clip_likes(clip_id,user_id) values (shared_clip,liker),(pending_clip,liker);

    perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated',
        'session_id',viewer_session,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.session_context()->>'is_experience'='true','Viewer is a standard one-tap account';
    state:=public.clip_social_state(shared_clip);
    assert state=jsonb_build_object('uploader',null,'is_following',false,'is_liked',false,
        'like_count',1,'comment_count',0),'One opted-in count, no identities or viewer like';
    assert not exists(select 1 from public.profiles where id in (owner,liker)),
        'Like does not expose development profiles';
    assert not has_table_privilege('authenticated','private.curated_clip_likes','select')
        and not has_table_privilege('authenticated','private.curated_clip_likes','insert')
        and not has_table_privilege('anon','private.curated_clip_likes','select')
        and not has_table_privilege('service_role','private.curated_clip_likes','select'),
        'Opt-in pairs have no direct API grants';
    assert public.clip_social_state(unlisted_clip)->>'like_count'='0',
        'Opt-in applies only to an exact clip and liker pair';
    begin
        perform public.clip_social_state(pending_clip);
        raise exception 'Pending clip accepted interaction';
    exception when insufficient_privilege then
        assert sqlerrm='clip_unavailable';
    end;
    state:=public.set_clip_liked(shared_clip,true);
    assert state->>'like_count'='2' and state->>'is_liked'='true','The real like is added once';
    assert public.set_clip_liked(shared_clip,true)->>'like_count'='2','Like retry does not double count';
    state:=public.set_clip_liked(shared_clip,false);
    assert state->>'like_count'='1' and state->>'is_liked'='false','Unlike removes only the real like';
    reset role;

    insert into public.blocks(owner_id,blocked_id) values(liker,viewer);
    set local role authenticated;
    assert public.clip_social_state(shared_clip)->>'like_count'='0','A block suppresses the opted-in like';
    reset role;
    delete from public.blocks where owner_id=liker and blocked_id=viewer;
    insert into private.content_report_hides(viewer_id,target_type,target_id)
        values(viewer,'conversation',liker);
    set local role authenticated;
    assert public.clip_social_state(shared_clip)->>'like_count'='0','A player report suppresses the opted-in like';
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',verified,'role','authenticated',
        'session_id',verified_session,'is_anonymous',false)::text,true);
    set local role authenticated;
    assert public.session_context()->>'is_experience'='false','Verified account is not a one-tap account';
    begin
        perform public.clip_social_state(shared_clip);
        raise exception 'Opt-in granted verified accounts access to a development clip';
    exception when insufficient_privilege then
        assert sqlerrm='clip_unavailable';
    end;
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',owner,'role','authenticated',
        'session_id',owner_session,'is_anonymous',false)::text,true);
    set local role authenticated;
    state:=public.clip_social_state(shared_clip);
    assert state->>'like_count'='2' and state->>'is_liked'='true','Existing development count is unchanged';
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',peer,'role','authenticated',
        'session_id',peer_session,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.clip_social_state(shared_clip)->>'like_count'='1','A second viewer keeps the sample count';
    reset role;
    delete from private.clip_likes where clip_id=shared_clip and user_id=liker;
    assert not exists(select 1 from private.curated_clip_likes where clip_id=shared_clip),
        'Deleting an opted-in like clears its publication permission';
    insert into private.clip_likes(clip_id,user_id) values(shared_clip,liker);
    set local role authenticated;
    assert public.clip_social_state(shared_clip)->>'like_count'='0','A replacement like needs new opt-in';
    reset role;
end $test$;

rollback;
