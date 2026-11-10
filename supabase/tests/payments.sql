-- Synthetic service-boundary fixtures only; never evidence of Apple verification.
-- One transaction; no real Auth account, purchase or wallet change survives.
begin;
do $test$
declare
    a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
    sa uuid := gen_random_uuid(); sb uuid := gen_random_uuid();
    p text := 'fixture.' || replace(gen_random_uuid()::text, '-', '');
    t text := '9' || floor(random()*1000000000000000)::bigint::text;
    r jsonb;
begin
    insert into auth.users(id,aud,role) values (a,'authenticated','authenticated'),(b,'authenticated','authenticated');
    insert into auth.identities(provider_id,user_id,identity_data,provider) values
        (a::text,a,jsonb_build_object('sub',a),'apple'),(b::text,b,jsonb_build_object('sub',b),'apple');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'oauth',now(),now()),(gen_random_uuid(),sb,'oauth',now(),now());
    insert into public.spark_packs(id,name,sparks,store_product_id,is_active,reference_price_usd,sort_order)
        values(p,'Fixture',400,p,true,'0.99',999);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
    set local role authenticated;
    r := public.payment_state();
    assert r#>>'{wallet,sparks}' = '0', 'real zero wallet';
    assert jsonb_array_length(r->'packs') >= 9, 'draft catalog readable through checked RPC';
    begin perform public.credit_apple_purchase(a,sa,'Production',t,p,a); raise exception 'client credited wallet';
        exception when insufficient_privilege then null; end;
    begin perform public.payment_server_settings(); raise exception 'client read private settings';
        exception when insufficient_privilege then null; end;
    reset role;
    set local role service_role;
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r->>'disposition' = 'credited' and r#>>'{wallet,sparks}' = '400', 'first durable delivery';
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r->>'disposition' = 'already_credited' and r#>>'{wallet,sparks}' = '400', 'retry does not double credit';
    begin perform public.credit_apple_purchase(b,sb,'Production',t,p,b); raise exception 'transaction moved accounts';
        exception when invalid_parameter_value then null; end;
    begin perform public.credit_apple_purchase(a,sa,'Production',t||'1',p,b); raise exception 'token mismatch';
        exception when invalid_parameter_value then null; end;
    r := public.credit_apple_purchase(a,sa,'Sandbox',t,p,a);
    assert r->>'environment' = 'Sandbox' and r#>>'{wallet,sparks}' = '400', 'sandbox separate wallet';
    reset role;
    assert (select sparks from public.wallets where user_id=a) = 400, 'sandbox did not change production';
    assert (select count(*) from private.wallet_ledger where user_id=a and reason='storekit_recharge') = 2, 'one credit per environment';
    update public.spark_packs set is_active=false where id=p;
    set local role service_role;
    r := public.credit_apple_purchase(a,sa,'Production',t||'2',p,a);
    assert r#>>'{wallet,sparks}' = '800', 'paid retired product still delivered';

    perform public.apply_apple_refund('Production',t,p,a,'fixture-refund',1000,true);
    perform public.apply_apple_refund('Production',t,p,a,'fixture-refund',1000,true);
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r->>'disposition' = 'refunded' and r#>>'{wallet,sparks}' = '400', 'refund exactly once';
    perform public.apply_apple_refund('Production',t,p,a,'fixture-old',999,false);
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r->>'disposition' = 'refunded', 'stale reversal ignored';
    perform public.apply_apple_refund('Production',t,p,a,'fixture-reversal',1001,false);
    perform public.apply_apple_refund('Production',t,p,a,'fixture-reversal',1001,false);
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r->>'disposition' = 'already_credited' and r#>>'{wallet,sparks}' = '800', 'reversal restored exactly once';

    perform public.apply_apple_refund('Production',t||'3',p,a,'fixture-early',1002,true);
    r := public.credit_apple_purchase(a,sa,'Production',t||'3',p,a);
    assert r->>'disposition' = 'refunded' and r#>>'{wallet,sparks}' = '800', 'refund before delivery leaves tombstone';
    perform public.apply_apple_refund('Production',t||'3',p,a,'fixture-early-reversed',1003,false);
    r := public.credit_apple_purchase(a,sa,'Production',t||'3',p,a);
    assert r->>'disposition' = 'credited' and r#>>'{wallet,sparks}' = '1200', 'reversal before delivery does not precredit';
    reset role;
    update public.wallets set sparks=100 where user_id=a; -- Simulate future already-spent funds.
    set local role service_role;
    perform public.apply_apple_refund('Production',t,p,a,'fixture-refund-again',1004,true);
    r := public.credit_apple_purchase(a,sa,'Production',t,p,a);
    assert r#>>'{wallet,sparks}'='0' and r#>>'{wallet,refund_debt_sparks}'='300', 'spent refund becomes separate adjustment';
    r := public.credit_apple_purchase(a,sa,'Production',t||'4',p,a);
    assert r#>>'{wallet,sparks}'='100' and r#>>'{wallet,refund_debt_sparks}'='0', 'new credit first offsets adjustment';
    reset role;
    delete from auth.sessions where id=sa;
    set local role service_role;
    begin perform public.credit_apple_purchase(a,sa,'Production',t||'5',p,a); raise exception 'revoked session delivered';
        exception when insufficient_privilege then null; end;
    reset role;
    set local role authenticated;
    begin perform public.payment_state(); raise exception 'revoked actor read wallet';
        exception when insufficient_privilege then null; end;
    reset role;
    delete from auth.users where id=a;
    set local role service_role;
    begin perform public.credit_apple_purchase(b,sb,'Production',t,p,b); raise exception 'deleted transaction replay';
        exception when invalid_parameter_value then null; end;
    reset role;
    assert exists(select 1 from private.purchase_transactions where environment='Production' and transaction_id=t and user_id is null), 'uniqueness survives deletion';
    set local role anon;
    begin perform public.payment_state(); raise exception 'anonymous wallet access';
        exception when insufficient_privilege then null; end;
    reset role;
end;
$test$;
rollback;
