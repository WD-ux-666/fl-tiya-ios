-- Synthetic authorization fixtures only; run after live_development.sql on the
-- authorized FL-Tiya project. No real password, access code or media is used.
-- Every fixture, Auth row and Storage metadata row is rolled back.
begin;
do $test$
declare
    p uuid := gen_random_uuid();
    q uuid := gen_random_uuid();
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    unknown_user uuid := gen_random_uuid();
    mismatched uuid := gen_random_uuid();
    sp uuid := gen_random_uuid();
    sp_password uuid := gen_random_uuid();
    sp_missing_amr uuid := gen_random_uuid();
    sq uuid := gen_random_uuid();
    sa uuid := gen_random_uuid();
    sb uuid := gen_random_uuid();
    su uuid := gen_random_uuid();
    email_a text := 'fixture-' || a::text || '@development.invalid';
    email_b text := 'fixture-' || b::text || '@development.invalid';
    hash_a text := replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
    hash_b text := replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
    request_id uuid;
    conversation_id uuid;
    cross_request uuid := gen_random_uuid();
    cross_conversation uuid := gen_random_uuid();
    message_id uuid := gen_random_uuid();
    pa uuid := gen_random_uuid();
    pp uuid := gen_random_uuid();
    ga uuid := gen_random_uuid();
    gp uuid := gen_random_uuid();
    pack_id text := 'fixture-dev-' || gen_random_uuid()::text;
    transaction_id text := '8' || floor(random() * 1000000000000000)::bigint::text;
    result jsonb;
    affected integer;
begin
    insert into private.development_accounts(user_id,email,label,code_hash,enabled,expires_at) values
        (a,email_a,'Development fixture A',hash_a,true,now()+interval '1 hour'),
        (b,email_b,'Development fixture B',hash_b,true,now()+interval '1 hour');
    set local role service_role;
    result := public.development_login_context(hash_a);
    assert result->>'user_id'=a::text and result->>'email'=email_a and result->>'exists'='false', 'reserved identity before Auth provisioning';
    assert public.development_login_context(repeat('0',64)) is null, 'unknown access-code hash fails closed';
    assert public.development_login_context('invalid') is null, 'malformed access-code hash fails closed';
    reset role;

    -- A provider which ignores a supplied UUID must not create the reserved
    -- email as a production profile, even momentarily.
    begin
        insert into auth.users(id,aud,role,email) values(mismatched,'authenticated','authenticated',email_a);
        raise exception 'reserved email accepted a different UUID';
    exception when insufficient_privilege then null; end;
    begin
        insert into auth.users(id,aud,role,email) values(a,'authenticated','authenticated','wrong-'||email_a);
        raise exception 'reserved UUID accepted a different email';
    exception when insufficient_privilege then null; end;

    insert into auth.users(id,aud,role) values(p,'authenticated','authenticated'),(q,'authenticated','authenticated');
    insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data) values
        (a,'authenticated','authenticated',email_a,now(),'{}'),
        (b,'authenticated','authenticated',email_b,now(),'{}'),
        (unknown_user,'authenticated','authenticated','fixture-'||unknown_user::text||'@development.invalid',now(),'{"cohort":"development","admin":true}');
    insert into auth.identities(provider_id,user_id,identity_data,provider) values
        (p::text,p,jsonb_build_object('sub',p),'apple'),
        (q::text,q,jsonb_build_object('sub',q),'apple'),
        (a::text,a,jsonb_build_object('sub',a,'email',email_a),'email'),
        (b::text,b,jsonb_build_object('sub',b,'email',email_b),'email'),
        (unknown_user::text,unknown_user,jsonb_build_object('sub',unknown_user),'email');
    insert into auth.sessions(id,user_id) values(sp,p),(sp_password,p),(sp_missing_amr,p),(sq,q),(sa,a),(sb,b),(su,unknown_user);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sp,'oauth',now(),now()),(gen_random_uuid(),sq,'oauth',now(),now()),
        (gen_random_uuid(),sp_password,'password',now(),now()),
        (gen_random_uuid(),sa,'password',now(),now()),(gen_random_uuid(),sb,'password',now(),now()),
        (gen_random_uuid(),su,'password',now(),now());
    assert (select cohort from private.accounts where user_id=a)='development', 'reserved Auth creation classifies atomically';
    assert (select display_name from public.profiles where id=a)='Development fixture A', 'reserved label supplies the initial test display name';
    assert (select cohort from private.accounts where user_id=p)='production', 'existing Apple creation remains production';
    begin
        update private.accounts set cohort='production' where user_id=a;
        raise exception 'development identity promoted to production';
    exception when insufficient_privilege then null; end;

    update public.profiles set display_name='Fixture development A',avatar_path=a::text||'/fixture.jpg' where id=a;
    update public.profiles set display_name='Fixture development B' where id=b;
    update public.profiles set display_name='Fixture production P',avatar_path=p::text||'/fixture.jpg' where id=p;
    insert into public.game_cards(user_id,game_id,player_name) values(a,'zenless-zone-zero','Development card'),(p,'zenless-zone-zero','Production card');
    insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at) values
        (pa,a,'zenless-zone-zero',a::text||'/'||pa::text||'/fixture.mp4','approved',now()),
        (pp,p,'zenless-zone-zero',p::text||'/'||pp::text||'/fixture.mp4','approved',now());
    insert into storage.objects(bucket_id,name,owner_id) values
        ('avatars',a::text||'/fixture.jpg',a::text),('avatars',p::text||'/fixture.jpg',p::text),
        ('clips',a::text||'/'||pa::text||'/fixture.mp4',a::text),('clips',p::text||'/'||pp::text||'/fixture.mp4',p::text);
    insert into public.guides(id,game_id,title,source_url,source_name,attribution,status,published_at,cohort) values
        (ga,'zenless-zone-zero','Development fixture','https://example.invalid/dev','Fixture','Fixture','published',now(),'development'),
        (gp,'zenless-zone-zero','Production fixture','https://example.invalid/prod','Fixture','Fixture','published',now(),'production');
    -- Cross-cohort fixtures model stale/imported rows, not allowed client writes.
    insert into public.friend_requests(id,sender_id,recipient_id) values(cross_request,p,a);
    insert into public.friendships(user_low,user_high) values(least(a,p),greatest(a,p));
    insert into public.blocks(owner_id,blocked_id) values(a,q);
    insert into public.conversations(id,user_low,user_high) values(cross_conversation,least(a,p),greatest(a,p));
    insert into public.messages(id,conversation_id,sender_id,body) values(gen_random_uuid(),cross_conversation,p,'Cross-cohort fixture');
    update public.wallets set sparks=901 where user_id=a;
    insert into private.sandbox_wallets(user_id,sparks) values(a,17);
    insert into private.wallet_ledger(user_id,delta,reason,reference,environment) values
        (a,901,'storekit_recharge','fixture-production-'||a::text,'Production'),
        (a,17,'storekit_recharge','fixture-sandbox-'||a::text,'Sandbox');
    update private.payment_settings set purchases_enabled=true,bundle_id='fixture.development.boundary',store_environment='Production';
    insert into public.spark_packs(id,name,sparks,store_product_id) values(pack_id,'Fixture',23,pack_id);

    -- Having an Apple identity does not mean this particular session used it.
    -- A forged JWT AMR and another real OAuth session must not authorize a
    -- password-created or AMR-less production session.
    perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated','session_id',sp_password,
        'amr',jsonb_build_array(jsonb_build_object('method','oauth','timestamp',extract(epoch from now())::bigint)))::text,true);
    set local role authenticated;
    assert not private.actor_is_active(), 'Apple identity password session denied despite forged OAuth JWT AMR';
    assert (select count(*) from public.profiles)=0, 'password session cannot read production profiles';
    begin perform public.session_context(); raise exception 'production password session restored'; exception when insufficient_privilege then null; end;
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated','session_id',sp_missing_amr,
        'amr',jsonb_build_array(jsonb_build_object('method','oauth')))::text,true);
    set local role authenticated;
    assert not private.actor_is_active(), 'production session missing server AMR denied';
    reset role;
    set local role service_role;
    begin
        perform public.credit_apple_purchase(p,sp_password,'Production',transaction_id||'1',pack_id,p);
        raise exception 'production password session credited Apple purchase';
    exception when insufficient_privilege then null; end;
    begin
        perform public.credit_apple_purchase(p,sp_missing_amr,'Production',transaction_id||'2',pack_id,p);
        raise exception 'production AMR-less session credited Apple purchase';
    exception when insufficient_privilege then null; end;
    reset role;
    assert (select sparks from public.wallets where user_id=p)=0, 'denied non-OAuth deliveries leave production balance untouched';

    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    assert private.actor_is_active(), 'reserved email password session is an active development actor';
    result := public.session_context();
    assert result->>'user_id'=a::text and result->>'cohort'='development' and result->>'display_name'='Fixture development A', 'server session context';
    assert (select count(*) from public.profiles where id in(a,b,p,q,unknown_user))=2, 'development sees only eligible development profiles';
    assert (select count(*) from public.discover_players('Fixture production'))=0, 'development discovery excludes production';
    assert (select count(*) from public.discover_players('Fixture development B'))=1, 'development discovery finds eligible peer';
    assert (select count(*) from public.game_cards where user_id=p)=0, 'production game card hidden';
    assert (select count(*) from public.guides where id=ga)=1 and (select count(*) from public.guides where id=gp)=0, 'guides respect cohort';
    assert (select count(*) from public.video_posts where id=pp)=0, 'approved production media metadata hidden';
    assert (select count(*) from public.conversations c where c.id=cross_conversation)=0, 'stale cross-cohort conversation hidden';
    assert (select count(*) from public.messages m where m.conversation_id=cross_conversation)=0, 'stale cross-cohort messages hidden';
    assert (select count(*) from public.friendships where user_low=least(a,p) and user_high=greatest(a,p))=0, 'stale cross-cohort friendship hidden';
    assert (select count(*) from public.blocks where owner_id=a and blocked_id=q)=0, 'stale cross-cohort block target hidden';
    perform set_config('storage.operation','storage.object.get_authenticated',true);
    assert (select count(*) from storage.objects where name=p::text||'/fixture.jpg')=0, 'production avatar bytes hidden';
    assert (select count(*) from storage.objects where name=p::text||'/'||pp::text||'/fixture.mp4')=0, 'production clip bytes hidden';
    assert (select count(*) from storage.objects where name=a::text||'/fixture.jpg')=1, 'own development avatar readable';
    begin perform public.send_friend_request(p); raise exception 'cross-cohort request allowed'; exception when insufficient_privilege then null; end;
    begin perform public.respond_friend_request(cross_request,true); raise exception 'cross-cohort accept allowed'; exception when insufficient_privilege then null; end;
    begin perform public.send_message(cross_conversation,gen_random_uuid(),'Intrusion'); raise exception 'cross-cohort message allowed'; exception when insufficient_privilege then null; end;
    begin perform public.block_user(p); raise exception 'cross-cohort block allowed'; exception when insufficient_privilege then null; end;
    update public.profiles set display_name='Development updated' where id=a;
    get diagnostics affected=row_count;
    assert affected=1, 'development can update own profile';
    begin
        insert into public.game_cards(user_id,game_id,player_name) values(b,'zenless-zone-zero','Spoof');
        raise exception 'cross-user game card insert allowed';
    exception when insufficient_privilege then null; end;
    assert (select count(*) from public.wallets where user_id=a)=0, 'development cannot read production wallet directly';
    result := public.payment_state();
    assert result->>'environment'='Sandbox' and result->>'purchases_enabled'='false', 'development forces Sandbox and disables checkout';
    assert result#>>'{wallet,sparks}'='17' and jsonb_array_length(result->'history')=1
        and result#>>'{history,0,delta}'='17', 'development wallet and ledger exclude production';
    begin perform public.development_login_context(hash_a); raise exception 'client queried access-code hashes'; exception when insufficient_privilege then null; end;
    begin update private.accounts set cohort='production' where user_id=a; raise exception 'client changed cohort'; exception when insufficient_privilege then null; end;
    begin update public.guides set cohort='production' where id=ga; raise exception 'client changed guide cohort'; exception when insufficient_privilege then null; end;
    request_id := (public.send_friend_request(b)->>'id')::uuid;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    conversation_id := (public.respond_friend_request(request_id,true)->>'conversation_id')::uuid;
    assert conversation_id is not null, 'development peers can accept and create conversation';
    perform public.send_message(conversation_id,message_id,'Development fixture message');
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    assert (select count(*) from public.messages m where m.id=message_id)=1, 'development peers share persistent message';
    perform public.block_user(b);
    perform public.block_user(b);
    assert (select count(*) from public.profiles where id=b)=0, 'repeat block is idempotent and hides peer';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    assert (select count(*) from public.messages m where m.id=message_id)=0, 'development block applies in reverse';
    reset role;

    set local role service_role;
    result := public.development_login_context(hash_a);
    assert result->>'user_id'=a::text and result->>'exists'='true', 'provisioned context binds the exact Auth identity';
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated','session_id',sp)::text,true);
    set local role authenticated;
    assert private.actor_is_active(), 'Apple fixture remains active without an email';
    assert public.session_context()->>'cohort'='production', 'Apple session has production context';
    assert (select count(*) from public.profiles where id in(p,q,a,b,unknown_user))=2, 'production sees only eligible production profiles';
    assert (select count(*) from public.discover_players('Fixture development'))=0, 'production discovery excludes development';
    assert (select count(*) from public.game_cards where user_id=a)=0, 'development card hidden from production';
    assert (select count(*) from public.guides where id=gp)=1 and (select count(*) from public.guides where id=ga)=0, 'production guide isolation';
    assert (select count(*) from public.video_posts where id=pa)=0, 'development approved post hidden from production';
    assert (select count(*) from storage.objects where name=a::text||'/fixture.jpg')=0, 'development avatar hidden from production';
    assert (select count(*) from storage.objects where name=a::text||'/'||pa::text||'/fixture.mp4')=0, 'development clip hidden from production';
    assert (select count(*) from public.conversations c where c.id=cross_conversation)=0, 'production cannot read imported cross-cohort conversation';
    begin perform public.send_friend_request(a); raise exception 'production sent development request'; exception when insufficient_privilege then null; end;
    begin perform public.block_user(a); raise exception 'production blocked development user'; exception when insufficient_privilege then null; end;
    result := public.payment_state();
    assert result->>'environment'='Production' and result->>'purchases_enabled'='true', 'production retains configured payment environment';
    assert (select count(*) from public.wallets where user_id=p)=1, 'production retains own wallet read';
    reset role;
    assert not exists(select 1 from public.blocks where (owner_id=a and blocked_id=p) or (owner_id=p and blocked_id=a)), 'denied cross-cohort blocks have no side effect';
    assert (select fr.status from public.friend_requests fr where fr.id=cross_request)='pending', 'denied accept leaves request unchanged';

    perform set_config('request.jwt.claims',jsonb_build_object('sub',unknown_user,'role','authenticated','session_id',su,
        'user_metadata',jsonb_build_object('cohort','development','admin',true))::text,true);
    set local role authenticated;
    assert not private.actor_is_active(), 'ordinary email and forged metadata do not authorize an actor';
    assert (select count(*) from public.games)=0, 'unreserved email cannot read catalogs';
    begin perform public.session_context(); raise exception 'unreserved email received session context'; exception when insufficient_privilege then null; end;
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert not private.actor_is_active(), 'anonymous JWT cannot use a reservation';
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    update auth.users set is_anonymous=true where id=a;
    set local role authenticated;
    assert not private.actor_is_active(), 'server anonymous user cannot forge nonanonymous JWT';
    reset role;
    update auth.users set is_anonymous=false,email_confirmed_at=null where id=a;
    set local role authenticated;
    assert not private.actor_is_active(), 'unconfirmed reserved email denied';
    reset role;
    update auth.users set email_confirmed_at=now() where id=a;
    update private.development_accounts set enabled=false where user_id=a;
    set local role authenticated;
    assert not private.actor_is_active(), 'disabled reservation denies existing session immediately';
    reset role;
    set local role service_role;
    assert public.development_login_context(hash_a) is null, 'disabled reservation denies new login';
    reset role;
    update private.development_accounts set enabled=true,expires_at=now()-interval '1 second' where user_id=a;
    set local role authenticated;
    assert not private.actor_is_active(), 'expired reservation denies old session';
    reset role;
    set local role service_role;
    assert public.development_login_context(hash_a) is null, 'expired reservation denies new login';
    reset role;
    update private.development_accounts set expires_at=now()+interval '1 hour' where user_id=a;
    -- Even a linked Apple identity cannot turn a development account into a
    -- production payer or make it visible to production peers.
    insert into auth.identities(provider_id,user_id,identity_data,provider) values(a::text,a,jsonb_build_object('sub',a),'apple');
    set local role service_role;
    begin
        perform public.credit_apple_purchase(a,sa,'Production',transaction_id,pack_id,a);
        raise exception 'development Apple-linked account received production credit';
    exception when insufficient_privilege then null; end;
    reset role;
    assert (select sparks from public.wallets where user_id=a)=901, 'denied credit leaves production wallet untouched';
    delete from private.development_accounts where user_id=a;
    assert (select cohort from private.accounts where user_id=a)='development', 'removing reservation preserves durable cohort';
    set local role authenticated;
    assert not private.actor_is_active(), 'removed reservation cannot fall through to Apple production authorization';
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated','session_id',sp)::text,true);
    set local role authenticated;
    assert (select count(*) from public.profiles where id=a)=0, 'removed reservation never exposes its profile to production';
    reset role;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
    delete from auth.sessions where id=sb;
    set local role authenticated;
    assert not private.actor_is_active(), 'revoked development session denied';
    begin perform public.session_context(); raise exception 'revoked development session restored'; exception when insufficient_privilege then null; end;
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    assert not private.actor_is_active(), 'another user session cannot authorize reserved identity';
    reset role;
    set local role anon;
    begin perform public.session_context(); raise exception 'anonymous session context allowed'; exception when insufficient_privilege then null; end;
    begin perform public.development_login_context(hash_b); raise exception 'anonymous reservation query allowed'; exception when insufficient_privilege then null; end;
    reset role;
end;
$test$;
rollback;
select 'live_development_permissions_passed_and_fixtures_rolled_back' as verification;
