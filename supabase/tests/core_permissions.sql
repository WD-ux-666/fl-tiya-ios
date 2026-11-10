-- Run only against the authorized FL-Tiya project after core.sql is deployed.
-- All Auth identities, sessions and business rows below are synthetic fixtures
-- in one rolled-back transaction. This does not test Apple-issued credentials.
begin;
do $test$
declare
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    c uuid := gen_random_uuid();
    sa uuid := gen_random_uuid();
    sb uuid := gen_random_uuid();
    sc uuid := gen_random_uuid();
    request_id uuid;
    conversation_id uuid;
    message_id uuid := gen_random_uuid();
    post_id uuid := gen_random_uuid();
    response jsonb;
    row_count integer;
begin
    insert into auth.users(id, aud, role) values
        (a, 'authenticated', 'authenticated'), (b, 'authenticated', 'authenticated'), (c, 'authenticated', 'authenticated');
    insert into auth.identities(provider_id, user_id, identity_data, provider) values
        ('fixture-' || a::text, a, jsonb_build_object('sub', 'fixture-' || a::text), 'apple'),
        ('fixture-' || b::text, b, jsonb_build_object('sub', 'fixture-' || b::text), 'apple'),
        ('fixture-' || c::text, c, jsonb_build_object('sub', 'fixture-' || c::text), 'apple');
    insert into auth.sessions(id, user_id) values (sa, a), (sb, b), (sc, c);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'oauth',now(),now()),
        (gen_random_uuid(),sb,'oauth',now(),now()),
        (gen_random_uuid(),sc,'oauth',now(),now());
    assert (select count(*) from public.profiles where id in (a, b, c)) = 3, 'signup profile trigger';
    assert (select count(*) from public.wallets where user_id in (a, b, c) and sparks = 0) = 3, 'zero wallet trigger';

    perform set_config('request.jwt.claims', jsonb_build_object('sub', a, 'role', 'authenticated', 'session_id', sa)::text, true);
    set local role authenticated;
    assert private.actor_is_active(), 'active Apple actor';
    update public.profiles set display_name = 'Fixture A', bio = 'Fixture only' where id = a;
    get diagnostics row_count = row_count;
    assert row_count = 1, 'own profile update';
    update public.profiles set display_name = 'Unauthorized' where id = b;
    get diagnostics row_count = row_count;
    assert row_count = 0, 'cross profile update denied';
    insert into public.game_cards(user_id, game_id, player_name, days_played, progress)
        values (a, 'zenless-zone-zero', 'Fixture', 5, 'Manual');
    insert into public.game_cards(user_id, game_id, player_name, days_played, progress)
        values (a, 'zenless-zone-zero', 'Fixture', null, 'Updated')
        on conflict (user_id, game_id) do update set days_played = excluded.days_played, progress = excluded.progress;
    assert (select days_played is null from public.game_cards where user_id = a), 'clear optional game days';
    begin
        insert into public.game_cards(user_id, game_id, player_name) values (b, 'zenless-zone-zero', 'Spoof');
        raise exception 'cross-user card insert unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    begin
        update public.wallets set sparks = 500 where user_id = a;
        raise exception 'client balance write unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    begin
        insert into public.friendships(user_low, user_high) values (least(a,b), greatest(a,b));
        raise exception 'direct friendship insert unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    assert (select count(*) from public.discover_players('Fixture A')) = 0, 'discovery excludes self';
    assert (select count(*) from public.discover_players('%')) = 0, 'search treats percent literally';
    response := public.send_friend_request(b);
    request_id := (response ->> 'id')::uuid;
    assert response ->> 'status' = 'pending', 'outgoing request pending';
    assert (public.send_friend_request(b) ->> 'id')::uuid = request_id, 'request retry idempotent';
    assert (select count(*) from public.conversations) = 0, 'no conversation before acceptance';
    begin
        perform public.respond_friend_request(request_id, true);
        raise exception 'sender accepted own request';
    exception when insufficient_privilege then null; end;
    insert into public.video_posts(id, owner_id, game_id, video_path)
        values (post_id, a, 'zenless-zone-zero', a::text || '/' || post_id::text || '/fixture.mp4');
    begin
        update public.video_posts set status = 'approved', approved_at = now() where id = post_id;
        raise exception 'client approved own post';
    exception when insufficient_privilege then null; end;

    -- SQL-only rolled-back metadata fixtures exercise the actual Storage RLS.
    -- No bytes are uploaded and no production object metadata is modified.
    perform set_config('storage.operation', 'storage.object.sign_upload_url', true);
    begin
        insert into storage.objects(bucket_id, name, owner_id)
            values ('avatars', a::text || '/fixture-signed.jpg', a::text);
        raise exception 'signed avatar upload capability unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    begin
        insert into storage.objects(bucket_id, name, owner_id)
            values ('clips', a::text || '/' || post_id::text || '/fixture.mp4', a::text);
        raise exception 'signed clip upload capability unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    perform set_config('storage.operation', 'storage.object.upload', true);
    insert into storage.objects(bucket_id, name, owner_id)
        values ('avatars', a::text || '/fixture.jpg', a::text),
               ('clips', a::text || '/' || post_id::text || '/fixture.mp4', a::text);
    update public.profiles set avatar_path = a::text || '/fixture.jpg' where id = a;
    perform set_config('storage.operation', 'storage.object.get_authenticated', true);
    assert (select count(*) from storage.objects where bucket_id = 'avatars' and name = a::text || '/fixture.jpg') = 1, 'authenticated avatar read';
    assert (select count(*) from storage.objects where bucket_id = 'clips' and name = a::text || '/' || post_id::text || '/fixture.mp4') = 1, 'owner pending clip read';
    perform set_config('storage.operation', 'storage.object.sign', true);
    assert (select count(*) from storage.objects where name = a::text || '/fixture.jpg') = 0, 'signed read capability denied';
    perform set_config('storage.operation', 'storage.object.list', true);
    assert (select count(*) from storage.objects where name = a::text || '/fixture.jpg') = 0, 'object listing denied';
    perform set_config('storage.operation', 'storage.object.get_authenticated', true);

    perform set_config('request.jwt.claims', jsonb_build_object('sub', b, 'role', 'authenticated', 'session_id', sb)::text, true);
    assert (select count(*) from public.video_posts where id = post_id) = 0, 'pending media hidden from peer';
    assert (select count(*) from storage.objects where bucket_id = 'clips' and name = a::text || '/' || post_id::text || '/fixture.mp4') = 0, 'pending clip bytes hidden from peer';
    reset role;
    update public.video_posts set status = 'approved', approved_at = now() where id = post_id;
    set local role authenticated;
    assert (select count(*) from public.video_posts where id = post_id) = 1, 'trusted approved media visible';
    assert (select count(*) from storage.objects where bucket_id = 'clips' and name = a::text || '/' || post_id::text || '/fixture.mp4') = 1, 'approved clip bytes visible';
    begin
        perform public.send_friend_request(a);
        raise exception 'reverse request silently accepted';
    exception when invalid_parameter_value then null; end;
    response := public.respond_friend_request(request_id, true);
    conversation_id := (response ->> 'conversation_id')::uuid;
    assert conversation_id is not null, 'accept creates conversation';
    assert (public.respond_friend_request(request_id, true) ->> 'conversation_id')::uuid = conversation_id, 'accept retry idempotent';
    response := public.send_message(conversation_id, message_id, 'Hello');
    assert (response ->> 'sender_id')::uuid = b, 'server assigned sender';
    assert (public.send_message(conversation_id, message_id, 'Hello') ->> 'id')::uuid = message_id, 'message retry idempotent';
    assert (select count(*) from public.messages where id = message_id) = 1, 'no duplicate message';
    begin
        perform public.send_message(conversation_id, message_id, 'Different');
        raise exception 'same message ID accepted different payload';
    exception when invalid_parameter_value then null; end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', c, 'role', 'authenticated', 'session_id', sc)::text, true);
    assert (select count(*) from public.conversations where id = conversation_id) = 0, 'third-party conversation hidden';
    assert (select count(*) from public.messages where id = message_id) = 0, 'third-party message hidden';
    begin
        perform public.send_message(conversation_id, gen_random_uuid(), 'Intrusion');
        raise exception 'nonparticipant sent message';
    exception when insufficient_privilege then null; end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', a, 'role', 'authenticated', 'session_id', sa)::text, true);
    assert (select count(*) from public.messages where id = message_id) = 1, 'friend reads message';
    perform public.block_user(b);
    assert (select count(*) from public.profiles where id = b) = 0, 'blocked peer profile hidden';
    assert (select count(*) from public.conversations where id = conversation_id) = 0, 'block hides own conversation';
    begin
        perform public.send_message(conversation_id, gen_random_uuid(), 'Blocked');
        raise exception 'blocked actor sent message';
    exception when insufficient_privilege then null; end;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', b, 'role', 'authenticated', 'session_id', sb)::text, true);
    assert (select count(*) from public.profiles where id = a) = 0, 'reverse block profile hidden';
    assert (select count(*) from public.messages where id = message_id) = 0, 'reverse block message hidden';
    assert (select count(*) from storage.objects where bucket_id = 'clips' and name = a::text || '/' || post_id::text || '/fixture.mp4') = 0, 'reverse block approved clip bytes hidden';
    begin
        perform public.send_friend_request(a);
        raise exception 'reverse blocked request allowed';
    exception when insufficient_privilege then null; end;

    reset role;
    update private.accounts set state = 'suspended' where user_id = c;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', c, 'role', 'authenticated', 'session_id', sc)::text, true);
    set local role authenticated;
    assert not private.actor_is_active(), 'suspended actor denied';
    assert (select count(*) from public.games) = 0, 'suspended catalog read denied';
    reset role;
    update private.accounts set state = 'active' where user_id = c;
    delete from auth.sessions where id = sc;
    set local role authenticated;
    assert not private.actor_is_active(), 'revoked session denied with old claims';
    assert (select count(*) from public.profiles) = 0, 'revoked session profiles denied';
    reset role;
    delete from auth.users where id = c;
    set local role authenticated;
    assert not private.actor_is_active(), 'deleted actor denied with old claims';
    assert (select count(*) from public.games) = 0, 'deleted actor catalog denied';
    reset role;

    set local role anon;
    begin
        perform count(*) from public.profiles;
        raise exception 'anonymous profile read unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    begin
        perform public.send_friend_request(a);
        raise exception 'anonymous RPC unexpectedly allowed';
    exception when insufficient_privilege then null; end;
    reset role;
end;
$test$;
rollback;
select 'core_permissions_passed_and_fixtures_rolled_back' as verification;
