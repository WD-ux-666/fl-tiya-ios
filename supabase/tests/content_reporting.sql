-- Exercise the actual RPC and authorization predicates with disposable identities.
begin;
set local plpgsql.check_asserts = on;

do $test$
declare
    a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); d uuid:=gen_random_uuid();
    sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid();
    own_video uuid:=gen_random_uuid(); peer_video uuid:=gen_random_uuid();
    editorial_video uuid:=gen_random_uuid(); hidden_video uuid:=gen_random_uuid(); blocked_video uuid:=gen_random_uuid();
    own_comment uuid:=gen_random_uuid(); peer_comment uuid:=gen_random_uuid();
    pending_comment uuid:=gen_random_uuid(); editorial_comment uuid:=gen_random_uuid(); blocked_comment uuid:=gen_random_uuid();
    target_kind text;
begin
    assert to_regprocedure('public.submit_content_report(text,uuid,text,text)') is not null,
        'Reporting RPC is missing';
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
        values(d,'fixture-'||d||'@development.invalid','Reporting fixture',
            encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
    insert into auth.users(id,aud,role,is_anonymous) values
        (a,'authenticated','authenticated',true),(b,'authenticated','authenticated',true),(c,'authenticated','authenticated',true);
    insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous)
        values(d,'authenticated','authenticated','fixture-'||d||'@development.invalid',now(),false);
    insert into auth.identities(provider_id,user_id,identity_data,provider)
        values(d::text,d,jsonb_build_object('sub',d),'email');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'anonymous',now(),now()),(gen_random_uuid(),sb,'anonymous',now(),now());
    insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at) values
        (own_video,a,'zenless-zone-zero',a||'/'||own_video||'/video.mp4','approved',now()),
        (peer_video,b,'zenless-zone-zero',b||'/'||peer_video||'/video.mp4','approved',now()),
        (editorial_video,d,'zenless-zone-zero',d||'/'||editorial_video||'/video.mp4','approved',now()),
        (hidden_video,b,'zenless-zone-zero',b||'/'||hidden_video||'/video.mp4','pending',null),
        (blocked_video,c,'zenless-zone-zero',c||'/'||blocked_video||'/video.mp4','approved',now());
    insert into private.clip_comments(id,clip_id,author_id,body,status,approved_at) values
        (own_comment,peer_video,a,'My own comment','approved',now()),
        (peer_comment,own_video,b,'Approved peer comment','approved',now()),
        (pending_comment,own_video,b,'Pending peer comment','pending',null),
        (editorial_comment,editorial_video,d,'Development-only comment','approved',now()),
        (blocked_comment,own_video,c,'Reverse-block fixture comment','approved',now());

    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.submit_content_report('video',peer_video,'spam',E' \tToo many links\n'),
        'Visible peer video accepted';
    assert not public.submit_content_report('video',peer_video,'other','Changed on retry'),
        'Duplicate report acknowledged without a second write';
    assert public.submit_content_report('comment',peer_comment,'harassment'),
        'Visible approved peer comment accepted';
    assert public.submit_content_report('conversation',b,'other','   '),
        'Peer can be reported before friendship or conversation creation';
    assert public.submit_content_report('video',editorial_video,'inappropriate'),
        'Experience user can report the editorial video they can see';
    begin
        perform public.submit_content_report('comment',editorial_comment,'spam');
        raise exception 'Hidden cross-cohort comment was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('conversation',d,'spam');
        raise exception 'Hidden cross-cohort peer was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('comment',pending_comment,'spam');
        raise exception 'Pending peer comment was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('video',hidden_video,'spam');
        raise exception 'Pending peer video was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('video',own_video,'spam');
        raise exception 'Own video was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('comment',own_comment,'spam');
        raise exception 'Own comment was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('conversation',a,'spam');
        raise exception 'Own profile was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    foreach target_kind in array array['video','comment','conversation'] loop
        begin
            perform public.submit_content_report(target_kind,gen_random_uuid(),'spam');
            raise exception 'Nonexistent target was reportable';
        exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    end loop;
    begin
        perform public.submit_content_report('video',peer_video,null);
        raise exception 'Null reason accepted';
    exception when invalid_parameter_value then assert sqlerrm='invalid_report'; end;
    begin
        perform public.submit_content_report('profile',b,'spam');
        raise exception 'Unsupported target kind accepted';
    exception when invalid_parameter_value then assert sqlerrm='invalid_report'; end;
    begin
        perform public.submit_content_report('video',peer_video,'spam',repeat('x',501));
        raise exception 'Oversized details accepted';
    exception when invalid_parameter_value then assert sqlerrm='invalid_report'; end;
    begin
        perform count(*) from private.content_reports;
        raise exception 'Client can read private reports';
    exception when insufficient_privilege then null; end;
    reset role;

    assert (select count(*) from private.content_reports where reporter_id=a)=4,
        'Exactly one stored report per valid target';
    assert exists(select 1 from private.content_reports where reporter_id=a and subject_id=b
        and target_type='video' and target_id=peer_video and reason='spam'
        and details='Too many links' and reviewed_at is null),
        'Reporter and subject derived by server; duplicate retains original report';
    assert exists(select 1 from private.content_reports where reporter_id=a and subject_id=b
        and target_type='conversation' and target_id=b and details is null),
        'Conversation report stores peer reference and blank details are discarded';
    assert not exists(select 1 from public.conversations where a in (user_low,user_high)),
        'Reporting did not create a conversation';
    assert not has_table_privilege('authenticated','private.content_reports','insert,update,delete'),
        'Clients cannot bypass the RPC or alter reports';
    assert not has_function_privilege('anon','public.submit_content_report(text,uuid,text,text)','execute'),
        'Unauthenticated role cannot invoke the RPC';

    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',b,'role','authenticated','session_id',sb,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.submit_content_report('conversation',a,'harassment'),
        'The other peer may submit an independent conversation report';
    reset role;

    -- A different peer's never-reported items must still respect blocks.
    insert into public.blocks(owner_id,blocked_id) values(c,a);
    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    begin
        perform public.submit_content_report('video',blocked_video,'spam');
        raise exception 'Reverse-blocked video was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('comment',blocked_comment,'spam');
        raise exception 'Reverse-blocked comment was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    begin
        perform public.submit_content_report('conversation',c,'spam');
        raise exception 'Reverse-blocked peer was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    reset role;

    update auth.sessions set not_after=now()-interval '1 second' where id=sa;
    set local role authenticated;
    begin
        perform public.submit_content_report('video',editorial_video,'spam');
        raise exception 'Expired session was able to report';
    exception when insufficient_privilege then assert sqlerrm='active_session_required'; end;
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',b,'role','authenticated','session_id',sb,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert public.submit_content_report('video',editorial_video,'spam'),
        'Another active account can report the same video independently';
    reset role;
    assert (select count(*) from private.content_reports where target_id=editorial_video)=2,
        'Both reporters have a separate record';
    assert exists(select 1 from private.content_reports where reporter_id=b and subject_id=a),
        'Deleting the subject will remove a report made by another account';
    delete from auth.users where id=a;
    assert not exists(select 1 from private.content_reports where reporter_id=a or subject_id=a),
        'Account deletion removes associated report identities';
    assert exists(select 1 from private.content_reports where reporter_id=b and subject_id=d),
        'Unrelated report survives account deletion';
end $test$;
rollback;
