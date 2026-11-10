-- Synthetic authorization and relationship fixtures. Run after the live
-- development and remove_friend migrations. Everything is rolled back.
begin;
do $test$
declare
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    c uuid := gen_random_uuid();
    development_user uuid := gen_random_uuid();
    missing_user uuid := gen_random_uuid();
    sa uuid := gen_random_uuid();
    sb uuid := gen_random_uuid();
    sc uuid := gen_random_uuid();
    sd uuid := gen_random_uuid();
    development_email text := 'fixture-' || development_user::text || '@development.invalid';
    request_id uuid;
    next_request uuid;
    pending_request uuid;
    conversation_id uuid;
    message_id uuid := gen_random_uuid();
    response jsonb;
begin
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
    values(development_user,development_email,'Remove friend fixture',
        replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),now()+interval '1 hour');
    insert into auth.users(id,aud,role) values
        (a,'authenticated','authenticated'),(b,'authenticated','authenticated'),(c,'authenticated','authenticated');
    insert into auth.users(id,aud,role,email,email_confirmed_at)
        values(development_user,'authenticated','authenticated',development_email,now());
    insert into auth.identities(provider_id,user_id,identity_data,provider) values
        (a::text,a,jsonb_build_object('sub',a),'apple'),
        (b::text,b,jsonb_build_object('sub',b),'apple'),
        (c::text,c,jsonb_build_object('sub',c),'apple'),
        (development_user::text,development_user,jsonb_build_object('sub',development_user,'email',development_email),'email');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b),(sc,c),(sd,development_user);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'oauth',now(),now()),
        (gen_random_uuid(),sb,'oauth',now(),now()),
        (gen_random_uuid(),sc,'oauth',now(),now());

    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    request_id := (public.send_friend_request(b)->>'id')::uuid;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    response := public.respond_friend_request(request_id,true);
    conversation_id := (response->>'conversation_id')::uuid;
    perform public.send_message(conversation_id,message_id,'Before removal');

    -- A third user can only mutate their own pair, never this friendship.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id',sc)::text,true);
    response := public.remove_friend(a);
    assert response->>'removed_user_id'=a::text, 'eligible nonfriend removal is an idempotent no-op';
    reset role;
    assert exists(select 1 from public.friendships where user_low=least(a,b) and user_high=greatest(a,b)), 'third user cannot remove another pair';
    set local role authenticated;

    -- Either participant can remove the pair. No block is created.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    response := public.remove_friend(b);
    assert response->>'removed_user_id'=b::text, 'removal response identifies only the requested peer';
    assert not exists(select 1 from public.friendships where user_low=least(a,b) and user_high=greatest(a,b)), 'friendship removed';
    assert (select status from public.friend_requests where id=request_id)='cancelled', 'accepted request retired';
    assert exists(select 1 from public.profiles where id=b), 'removed peer remains discoverable';
    assert not exists(select 1 from public.blocks where owner_id=a and blocked_id=b), 'removal does not block';
    assert public.remove_friend(b)=response, 'removal retry idempotent';
    perform public.send_message(conversation_id,gen_random_uuid(),'One introduction after removal');
    begin
        perform public.send_message(conversation_id,gen_random_uuid(),'Second message after removal');
        raise exception 'former friend sent more than one introduction';
    exception when raise_exception then assert sqlerrm='stranger_message_limit'; end;

    -- Old accepted requests cannot revive the pair. A fresh request must be
    -- accepted explicitly and reuses existing conversation history.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    begin
        perform public.respond_friend_request(request_id,true);
        raise exception 'old accepted request revived friendship';
    exception when invalid_parameter_value then null; end;
    next_request := (public.send_friend_request(a)->>'id')::uuid;
    assert next_request<>request_id, 'fresh request after removal';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    response := public.respond_friend_request(next_request,true);
    assert (response->>'conversation_id')::uuid=conversation_id, 'refriending preserves existing conversation';
    perform public.send_message(conversation_id,gen_random_uuid(),'Friends again');
    assert exists(select 1 from public.messages where id=message_id), 'old history remains available after refriending';

    -- Pending state is also retired, including when the friendship is absent.
    perform public.remove_friend(b);
    pending_request := (public.send_friend_request(b)->>'id')::uuid;
    perform public.remove_friend(b);
    assert (select status from public.friend_requests where id=pending_request)='cancelled', 'pending request cancelled';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    begin
        perform public.respond_friend_request(pending_request,true);
        raise exception 'retired pending request accepted';
    exception when invalid_parameter_value then null; end;

    -- Blocked, unknown, and cross-cohort targets share the same unavailable
    -- response; unfriend never removes either participant's block.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    perform public.block_user(b);
    begin
        perform public.remove_friend(b);
        raise exception 'blocked removal unexpectedly succeeded';
    exception when insufficient_privilege then
        assert sqlerrm='user_unavailable', 'blocked target unavailable';
    end;
    assert exists(select 1 from public.blocks where owner_id=a and blocked_id=b), 'own block preserved';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    begin
        perform public.remove_friend(a);
        raise exception 'reverse blocked removal unexpectedly succeeded';
    exception when insufficient_privilege then
        assert sqlerrm='user_unavailable', 'reverse blocked target unavailable';
    end;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    begin
        perform public.remove_friend(missing_user);
        raise exception 'unknown target removal succeeded';
    exception when insufficient_privilege then
        assert sqlerrm='user_unavailable', 'unknown target unavailable';
    end;
    begin
        perform public.remove_friend(development_user);
        raise exception 'cross-cohort target removal succeeded';
    exception when insufficient_privilege then
        assert sqlerrm='user_unavailable', 'cross-cohort target unavailable';
    end;
    begin
        perform public.remove_friend(a);
        raise exception 'self removal succeeded';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.remove_friend(null);
        raise exception 'null target removal succeeded';
    exception when invalid_parameter_value then null; end;

    reset role;
    update private.accounts set state='suspended' where user_id=c;
    set local role authenticated;
    begin
        perform public.remove_friend(c);
        raise exception 'suspended target removal succeeded';
    exception when insufficient_privilege then
        assert sqlerrm='user_unavailable', 'ineligible target unavailable';
    end;
    reset role;
    delete from auth.sessions where id=sa;
    set local role authenticated;
    begin
        perform public.remove_friend(c);
        raise exception 'revoked session removed friend';
    exception when insufficient_privilege then
        assert sqlerrm='active_session_required', 'revoked actor session denied';
    end;
    reset role;

    set local role anon;
    begin
        perform public.remove_friend(a);
        raise exception 'anonymous removal succeeded';
    exception when insufficient_privilege then null; end;
    reset role;
end;
$test$;
rollback;
