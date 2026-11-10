-- Synthetic account/community/relationship fixtures for Phase 17. No real
-- account, media or secret is used. Run after community_blocklist migration.
-- Every Auth user, session, game card, request and block is rolled back.
begin;
do $test$
declare
    a uuid:=gen_random_uuid();
    b uuid:=gen_random_uuid();
    c uuid:=gen_random_uuid();
    d uuid:=gen_random_uuid();
    e uuid:=gen_random_uuid();
    unknown_user uuid:=gen_random_uuid();
    sa uuid:=gen_random_uuid();
    sb uuid:=gen_random_uuid();
    sc uuid:=gen_random_uuid();
    sd uuid:=gen_random_uuid();
    se uuid:=gen_random_uuid();
    development_email text:='fixture-'||d::text||'@development.invalid';
    other_game text:='fixture-community-'||gen_random_uuid()::text;
    request_id uuid;
    conversation_id uuid;
    response jsonb;
    paging_users uuid[];
    first_page uuid[];
    second_page uuid[];
    cursor_time timestamptz;
    cursor_user uuid;
    removed_user uuid;
    tie_time timestamptz:=now()-interval '1 day';
    fixtures uuid[]:=array[a,b,c,d,e];
begin
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
    values(d,development_email,'Community development fixture',
        replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),now()+interval '1 hour');
    insert into auth.users(id,aud,role) values
        (a,'authenticated','authenticated'),(b,'authenticated','authenticated'),(c,'authenticated','authenticated');
    insert into auth.users(id,aud,role,email,email_confirmed_at)
        values(d,'authenticated','authenticated',development_email,now());
    insert into auth.users(id,aud,role,is_anonymous)
        values(e,'authenticated','authenticated',true);
    insert into auth.identities(provider_id,user_id,identity_data,provider) values
        (a::text,a,jsonb_build_object('sub',a),'apple'),
        (b::text,b,jsonb_build_object('sub',b),'apple'),
        (c::text,c,jsonb_build_object('sub',c),'apple'),
        (d::text,d,jsonb_build_object('sub',d,'email',development_email),'email');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b),(sc,c),(sd,d),(se,e);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'oauth',now(),now()),
        (gen_random_uuid(),sb,'oauth',now(),now()),
        (gen_random_uuid(),sc,'oauth',now(),now()),
        (gen_random_uuid(),se,'anonymous',now(),now());
    insert into public.games(id,name) values(other_game,'Community fixture game');
    update public.profiles set display_name='Community 50% Crew '||b::text where id=b;
    insert into public.game_cards(user_id,game_id,player_name) values
        (a,'zenless-zone-zero','Actor card'),
        (b,'zenless-zone-zero','Member B'),(b,other_game,'Second game B'),
        (c,other_game,'Member C'),
        (d,'zenless-zone-zero','Other cohort D'),
        (e,'zenless-zone-zero','Experience E');

    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    assert private.actor_is_active(),'Apple fixture session active';
    assert (select count(*) from public.discover_community_players('zenless-zone-zero','') p where p.id=any(fixtures))=2,
        'selected-game community includes actual B and experience E cards, excludes self/C/different cohort D';
    assert (select count(*) from public.discover_community_players(other_game,'') p where p.id=any(fixtures))=2,
        'switching game returns actual B and C members';
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=any(fixtures))=3,
        'All players includes same-cohort B/C/E without requiring a selected game';
    assert (select count(*) from public.discover_community_players() p where p.id=any(fixtures))=3,
        'default RPC arguments mean All players and empty literal search';
    assert (select count(*) from public.discover_community_players('missing-community','') p where p.id=any(fixtures))=0,
        'unknown game never falls back to an unfiltered directory';
    assert (select count(*) from public.discover_community_players(null,'COMMUNITY 50% CREW '||upper(b::text)) p where p.id=b)=1,
        'display-name search is case-insensitive';
    assert (select count(*) from public.discover_community_players(null,'%') p where p.id=any(fixtures))=1,
        'percent is a literal substring, not a SQL wildcard';
    assert (select count(*) from public.discover_community_players(null,'not_a_real_*') p where p.id=any(fixtures))=0,
        'empty literal result remains empty';
    assert (select count(*) from public.discover_community_players(other_game,'') p where p.id=b)=1,
        'multiple game cards never duplicate a member';
    assert (select p.relationship from public.discover_community_players('zenless-zone-zero','') p where p.id=b)='none',
        'no fabricated friendship or pending state';

    request_id:=(public.send_friend_request(b)->>'id')::uuid;
    assert request_id is not null,'friend request mutation returns actual row';
    assert (select p.relationship from public.discover_community_players('zenless-zone-zero','') p where p.id=b)='outgoing',
        'sender sees outgoing request';
    assert (select p.request_id from public.discover_community_players('zenless-zone-zero','') p where p.id=b)=request_id,
        'outgoing state identifies the persisted request';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    assert (select p.relationship from public.discover_community_players('zenless-zone-zero','') p where p.id=a)='incoming',
        'recipient sees incoming request';
    assert (select p.request_id from public.discover_community_players('zenless-zone-zero','') p where p.id=a)=request_id,
        'recipient action uses the persisted request ID';
    response:=public.respond_friend_request(request_id,true);
    conversation_id:=(response->>'conversation_id')::uuid;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    assert (select p.relationship from public.discover_community_players('zenless-zone-zero','') p where p.id=b)='friends',
        'accepted relationship reads true friendship row';
    assert (select p.request_id from public.discover_community_players('zenless-zone-zero','') p where p.id=b) is null,
        'friend state exposes no stale actionable request';

    perform public.block_user(b);
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=b)=0,
        'own block hides community member';
    assert (select count(*) from public.profiles p where p.id=b)=0,
        'normal blocked profile remains inaccessible';
    assert (select count(*) from public.list_blocked_players() p where p.id=b)=1,
        'owner-only blocklist can identify blocked peer despite normal profile RLS';
    assert (select p.display_name from public.list_blocked_players() p where p.id=b)='Community 50% Crew '||b::text,
        'blocklist uses real saved display name';
    assert (select count(*) from public.list_blocked_players() p where p.id=a)=0,
        'own list does not invent a reverse block';
    assert not exists(select 1 from public.friendships f where f.user_low=least(a,b) and f.user_high=greatest(a,b)),
        'blocking removed friendship';
    begin
        perform public.send_friend_request(b);
        raise exception 'blocked peer accepted a new friend request';
    exception when insufficient_privilege then null; end;

    -- Another actor has no owner parameter to override, and an unblock of the
    -- same target only affects that actor's own pair.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id',sc)::text,true);
    assert (select count(*) from public.list_blocked_players() p where p.id=any(fixtures))=0,
        'third user cannot enumerate someone else blocklist';
    perform public.unblock_user(b);
    reset role;
    assert exists(select 1 from public.blocks where owner_id=a and blocked_id=b),
        'third user cannot unblock A to B';
    set local role authenticated;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=a)=0,
        'a reverse-side block hides directory member as well';
    assert (select count(*) from public.list_blocked_players() p where p.id=a)=0,
        'being blocked does not expose the blocker through blocklist';
    perform public.block_user(a);
    assert (select count(*) from public.list_blocked_players() p where p.id=a)=1,
        'a real reverse block is listed only for its owner';

    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    response:=public.unblock_user(b);
    assert response->>'unblocked_user_id'=b::text,'unblock identifies requested peer';
    assert public.unblock_user(b)=response,'repeated unblock is an idempotent no-op';
    assert (select count(*) from public.list_blocked_players() p where p.id=b)=0,
        'own entry is removed after unblocking';
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=b)=0,
        'reverse block continues to hide the peer after own unblock';
    reset role;
    assert exists(select 1 from public.blocks where owner_id=b and blocked_id=a),'reverse block not deleted';
    assert not exists(select 1 from public.friendships f where f.user_low=least(a,b) and f.user_high=greatest(a,b)),
        'unblock never restores friendship';
    set local role authenticated;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    perform public.unblock_user(a);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    assert (select p.relationship from public.discover_community_players('zenless-zone-zero','') p where p.id=b)='none',
        'both blocks removed restores visibility without friendship';
    perform public.send_message(conversation_id,gen_random_uuid(),'One unused introduction after unblock');
    begin
        perform public.send_message(conversation_id,gen_random_uuid(),'No second introduction after unblock');
        raise exception 'unblock allowed unlimited nonfriend messages';
    exception when raise_exception then assert sqlerrm='stranger_message_limit'; end;
    begin
        perform public.unblock_user(a);
        raise exception 'self unblock accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.unblock_user(null);
        raise exception 'null unblock accepted';
    exception when invalid_parameter_value then null; end;
    -- Guessing an ID can only remove the caller's own nonexistent block.
    perform public.unblock_user(unknown_user);

    perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated','session_id',sd)::text,true);
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=any(fixtures))=0,
        'development fixture cannot read production community people';
    assert (select count(*) from public.list_blocked_players() p where p.id=any(fixtures))=0,
        'development fixture cannot read production block identities';
    reset role;

    -- Authenticated anonymous experience accounts are deliberately supported.
    -- They are different from the unauthenticated Data API anon role below.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','session_id',se,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert private.actor_is_active(),'real anonymous experience session is active';
    assert (select count(*) from public.discover_community_players('zenless-zone-zero','') p where p.id=any(fixtures))=2,
        'experience account can discover same-cohort actual A/B members';
    assert (select count(*) from public.discover_community_players(null,'') p where p.id=d)=0,
        'experience account cannot cross into private development directory';
    reset role;

    -- An existing JWT must not outlive its server-side session authorization.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    perform public.block_user(b);
    assert (select count(*) from public.list_blocked_players() p where p.id=b)=1,'active actor can read own existing block before revocation';
    reset role;
    delete from auth.sessions where id=sa;
    set local role authenticated;
    assert (select count(*) from public.discover_community_players(null,''))=0,'revoked actor cannot discover community people';
    assert (select count(*) from public.list_blocked_players())=0,'revoked actor cannot read block identities';
    begin
        perform public.unblock_user(b);
        raise exception 'revoked actor unblocked peer';
    exception when insufficient_privilege then null; end;
    reset role;

    set local role anon;
    begin
        perform public.discover_community_players(null,'');
        raise exception 'unauthenticated anon role read directory';
    exception when insufficient_privilege then null; end;
    begin
        perform public.list_blocked_players();
        raise exception 'unauthenticated anon role read blocklist';
    exception when insufficient_privilege then null; end;
    begin
        perform public.unblock_user(b);
        raise exception 'unauthenticated anon role unblocked peer';
    exception when insufficient_privilege then null; end;
    reset role;

    -- More than one page of actual synthetic profiles, all blocked at the
    -- exact same timestamp. The UUID descending tie-breaker must preserve
    -- every older entry without requiring any unrelated unblock.
    select array_agg(gen_random_uuid()) into paging_users from generate_series(1,55);
    insert into auth.users(id,aud,role)
        select u,'authenticated','authenticated' from unnest(paging_users) u;
    insert into auth.identities(provider_id,user_id,identity_data,provider)
        select u::text,u,jsonb_build_object('sub',u),'apple' from unnest(paging_users) u;
    insert into public.blocks(owner_id,blocked_id,created_at)
        select c,u,tie_time from unnest(paging_users) u;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id',sc)::text,true);
    set local role authenticated;
    select array_agg(p.id order by p.blocked_at desc,p.id desc) into first_page from public.list_blocked_players() p;
    assert cardinality(first_page)=50,'blocklist first page is bounded to 50';
    assert first_page=array(select u from unnest(paging_users) u order by u desc limit 50),
        'equal-timestamp first page orders UUID descending';
    select p.blocked_at,p.id into cursor_time,cursor_user from public.list_blocked_players() p
        order by p.blocked_at desc,p.id desc offset 49 limit 1;
    select array_agg(p.id order by p.blocked_at desc,p.id desc) into second_page
        from public.list_blocked_players(cursor_time,cursor_user) p;
    assert cardinality(second_page)=5,'keyset continuation reaches the five older blocks';
    assert not (first_page && second_page),'keyset pages never repeat their boundary or another entry';
    assert array(select u from unnest(first_page||second_page) u order by u desc)
        =array(select u from unnest(paging_users) u order by u desc),
        'all 55 blocked players are reachable without unblocking anyone';
    select p.blocked_at,p.id into cursor_time,cursor_user from public.list_blocked_players(cursor_time,cursor_user) p
        order by p.blocked_at,p.id limit 1;
    assert (select count(*) from public.list_blocked_players(cursor_time,cursor_user))=0,
        'cursor after oldest block produces an empty final page';
    begin
        perform public.list_blocked_players(tie_time,null);
        raise exception 'timestamp-only block cursor accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.list_blocked_players(null,c);
        raise exception 'user-only block cursor accepted';
    exception when invalid_parameter_value then null; end;

    -- A successful unblock invalidates old page boundaries. Reloading from
    -- page one, as the client does, still visits every remaining block.
    removed_user:=first_page[1];
    perform public.unblock_user(removed_user);
    select array_agg(p.id order by p.blocked_at desc,p.id desc) into first_page from public.list_blocked_players() p;
    select p.blocked_at,p.id into cursor_time,cursor_user from public.list_blocked_players() p
        order by p.blocked_at desc,p.id desc offset 49 limit 1;
    select array_agg(p.id order by p.blocked_at desc,p.id desc) into second_page
        from public.list_blocked_players(cursor_time,cursor_user) p;
    assert cardinality(first_page)=50 and cardinality(second_page)=4,'refresh after unblock repaginates all remaining 54';
    assert not (first_page && second_page),'refresh pages do not repeat entries';
    assert not (removed_user=any(first_page||second_page)),'unblocked target disappears after refresh';
    assert array(select u from unnest(first_page||second_page) u order by u desc)
        =array(select u from unnest(paging_users) u where u<>removed_user order by u desc),
        'refresh after unblock skips no remaining target';
    reset role;
end;
$test$;
rollback;
