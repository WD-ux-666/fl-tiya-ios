-- Increment after core.sql. Apply once as a reviewed migration.
begin;

alter table public.wallets add column refund_debt_sparks bigint not null default 0 check (refund_debt_sparks >= 0);
alter table public.spark_packs add column reference_price_usd numeric(8,2) not null default 0 check (reference_price_usd >= 0);
alter table public.spark_packs add column sort_order integer not null default 0;
alter table public.spark_packs add constraint active_spark_pack_has_product check (not is_active or nullif(btrim(store_product_id),'') is not null);
alter table private.purchase_transactions add column app_account_token uuid;
alter table private.purchase_transactions add column is_credited boolean not null default true;
alter table private.purchase_transactions add column is_refunded boolean not null default false;
alter table private.purchase_transactions add column status_event_date bigint not null default 0;
alter table private.purchase_transactions add column last_event_id text;
alter table private.wallet_ledger add column environment text not null default 'Production' check (environment in ('Production','Sandbox'));
alter table private.wallet_ledger drop constraint wallet_ledger_reason_check;
alter table private.wallet_ledger add constraint wallet_ledger_reason_check
    check (reason in ('storekit_recharge','frame_purchase','storekit_refund','storekit_refund_reversal'));
create index wallet_ledger_user_environment_idx on private.wallet_ledger(user_id,environment,created_at desc);

create table private.payment_settings (
    singleton boolean primary key default true check(singleton),
    bundle_id text check (bundle_id is null or length(bundle_id) between 3 and 200),
    app_apple_id bigint check(app_apple_id > 0),
    store_environment text not null default 'Production' check(store_environment in ('Production','Sandbox')),
    allow_sandbox boolean not null default false,
    purchases_enabled boolean not null default false,
    check (store_environment <> 'Sandbox' or allow_sandbox),
    check (not purchases_enabled or nullif(btrim(bundle_id),'') is not null)
);
insert into private.payment_settings(singleton) values(true);
create table private.sandbox_wallets (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    sparks bigint not null default 0 check(sparks >= 0),
    refund_debt_sparks bigint not null default 0 check(refund_debt_sparks >= 0)
);
alter table private.payment_settings enable row level security;
alter table private.sandbox_wallets enable row level security;
revoke all on private.payment_settings,private.sandbox_wallets from public,anon,authenticated;
grant all on private.payment_settings,private.sandbox_wallets to service_role;

insert into public.spark_packs(id,name,sparks,reference_price_usd,sort_order) values
('sparks_400','Pocket Sparks',400,0.99,1),
('sparks_800','Spark Starter',800,1.99,2),
('sparks_2450','Spark Bundle',2450,4.99,3),
('sparks_5150','Spark Boost',5150,9.99,4),
('sparks_10800','Spark Chest',10800,19.99,5),
('sparks_16800','Spark Vault',16800,29.99,6),
('sparks_29400','Spark Galaxy',29400,49.99,7),
('sparks_42700','Spark Universe',42700,69.99,8),
('sparks_63700','Spark Supernova',63700,99.99,9);

-- Internal helpers have no direct client grant. All sensitive mutations share
-- one lock order: transaction advisory lock, account/session, then wallet.
create function private.payment_wallet_snapshot(actor uuid,env text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare w jsonb;
begin
    if env='Production' then
        select jsonb_build_object('sparks',sparks,'refund_debt_sparks',refund_debt_sparks) into w from public.wallets where user_id=actor;
    elsif env='Sandbox' then
        select jsonb_build_object('sparks',sparks,'refund_debt_sparks',refund_debt_sparks) into w from private.sandbox_wallets where user_id=actor;
    else raise exception using errcode='22023',message='invalid_payment_environment'; end if;
    return coalesce(w,jsonb_build_object('sparks',0,'refund_debt_sparks',0));
end;
$$;

create function private.adjust_payment_wallet(actor uuid,env text,amount bigint) returns void
language plpgsql volatile security definer set search_path='' as $$
declare balance bigint; debt bigint; offset_amount bigint;
begin
    if env='Production' then
        select sparks,refund_debt_sparks into strict balance,debt from public.wallets where user_id=actor for update;
    elsif env='Sandbox' then
        insert into private.sandbox_wallets(user_id) values(actor) on conflict do nothing;
        select sparks,refund_debt_sparks into strict balance,debt from private.sandbox_wallets where user_id=actor for update;
    else raise exception using errcode='22023',message='invalid_payment_environment'; end if;
    if amount > 0 then
        offset_amount := least(debt,amount);
        debt := debt-offset_amount;
        balance := balance+amount-offset_amount;
    else
        offset_amount := least(balance,-amount);
        balance := balance-offset_amount;
        debt := debt-amount-offset_amount;
    end if;
    if env='Production' then
        update public.wallets set sparks=balance,refund_debt_sparks=debt where user_id=actor;
    else
        update private.sandbox_wallets set sparks=balance,refund_debt_sparks=debt where user_id=actor;
    end if;
end;
$$;

create function private.payment_state() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid; settings private.payment_settings; packs jsonb; history jsonb;
begin
    actor := private.require_actor();
    select * into strict settings from private.payment_settings where singleton;
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'sparks',p.sparks,
        'store_product_id',p.store_product_id,'is_active',p.is_active,
        'reference_price_usd',p.reference_price_usd::text,'sort_order',p.sort_order) order by p.sort_order,p.id),'[]'::jsonb)
        into packs from public.spark_packs p;
    select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id),'[]'::jsonb) into history from
        (select l.id,l.delta,l.reason,l.created_at from private.wallet_ledger l
         where l.user_id=actor and l.environment=settings.store_environment order by l.created_at desc,l.id limit 50) h;
    return jsonb_build_object('environment',settings.store_environment,'purchases_enabled',settings.purchases_enabled,
        'wallet',private.payment_wallet_snapshot(actor,settings.store_environment),'packs',packs,'history',history);
end;
$$;
create function public.payment_state() returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.payment_state(); $$;

create function private.payment_server_settings() returns jsonb
language sql stable security definer set search_path='' as $$
    select jsonb_build_object('bundle_id',bundle_id,'app_apple_id',app_apple_id,'store_environment',store_environment,
        'allow_sandbox',allow_sandbox,'purchases_enabled',purchases_enabled) from private.payment_settings where singleton;
$$;
create function public.payment_server_settings() returns jsonb
language sql stable security invoker set search_path='' as $$ select private.payment_server_settings(); $$;

create function private.credit_apple_purchase(target_user_id uuid,target_session_id uuid,apple_environment text,
    apple_transaction_id text,apple_product_id text,apple_account_token uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare purchase private.purchase_transactions; credit bigint; result text;
begin
    if target_user_id is null or target_session_id is null or apple_account_token is distinct from target_user_id
       or apple_environment not in ('Production','Sandbox') or apple_environment is null
       or apple_transaction_id is null or apple_transaction_id !~ '^[0-9]{1,100}$'
       or apple_product_id is null or length(apple_product_id) not between 1 and 200 then
        raise exception using errcode='22023',message='invalid_verified_transaction';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apple:'||apple_environment||':'||apple_transaction_id,0));
    perform 1 from private.accounts where user_id=target_user_id and state='active' for share;
    if not found then raise exception using errcode='42501',message='active_apple_session_required'; end if;
    perform 1 from auth.sessions where id=target_session_id and user_id=target_user_id for share;
    if not found or not exists(select 1 from auth.identities where user_id=target_user_id and provider='apple')
       or not exists(select 1 from auth.users where id=target_user_id and not coalesce(is_anonymous,false)) then
        raise exception using errcode='42501',message='active_apple_session_required';
    end if;
    select * into purchase from private.purchase_transactions where environment=apple_environment and transaction_id=apple_transaction_id;
    if found then
        if purchase.user_id is distinct from target_user_id or purchase.app_account_token is distinct from apple_account_token
           or purchase.store_product_id is distinct from apple_product_id then
            raise exception using errcode='22023',message='transaction_account_or_product_conflict';
        end if;
    else
        select sparks into credit from public.spark_packs where store_product_id=apple_product_id;
        if credit is null then raise exception using errcode='22023',message='unknown_store_product'; end if;
        insert into private.purchase_transactions(environment,transaction_id,user_id,store_product_id,credited_sparks,app_account_token,is_credited)
            values(apple_environment,apple_transaction_id,target_user_id,apple_product_id,credit,apple_account_token,false)
            returning * into purchase;
    end if;
    if purchase.is_refunded then result := 'refunded';
    elsif purchase.is_credited then result := 'already_credited';
    else
        perform private.adjust_payment_wallet(target_user_id,apple_environment,purchase.credited_sparks);
        insert into private.wallet_ledger(user_id,delta,reason,reference,environment)
            values(target_user_id,purchase.credited_sparks,'storekit_recharge','apple:'||apple_environment||':'||apple_transaction_id||':credit',apple_environment);
        update private.purchase_transactions set is_credited=true where environment=apple_environment and transaction_id=apple_transaction_id;
        result := 'credited';
    end if;
    return jsonb_build_object('environment',apple_environment,'transaction_id',apple_transaction_id,'disposition',result,
        'credited_sparks',purchase.credited_sparks,'wallet',private.payment_wallet_snapshot(target_user_id,apple_environment));
end;
$$;
create function public.credit_apple_purchase(target_user_id uuid,target_session_id uuid,apple_environment text,
    apple_transaction_id text,apple_product_id text,apple_account_token uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$
    select private.credit_apple_purchase(target_user_id,target_session_id,apple_environment,apple_transaction_id,apple_product_id,apple_account_token);
$$;

-- Incoming webhooks are only routing hints. The Edge Function obtains all
-- arguments below from a fresh authenticated HTTPS Apple transaction lookup.
create function private.apply_apple_refund(apple_environment text,apple_transaction_id text,apple_product_id text,
    apple_account_token uuid,apple_event_id text,apple_event_date bigint,apple_is_refunded boolean) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare purchase private.purchase_transactions; credit bigint; actor uuid; amount bigint;
begin
    if apple_environment is null or apple_environment not in ('Production','Sandbox')
       or apple_transaction_id is null or apple_transaction_id !~ '^[0-9]{1,100}$'
       or apple_product_id is null or length(apple_product_id) not between 1 and 200 or apple_account_token is null
       or apple_event_id is null or length(apple_event_id) not between 1 and 300
       or apple_event_date is null or apple_event_date <= 0 or apple_is_refunded is null then
        raise exception using errcode='22023',message='invalid_verified_refund';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apple:'||apple_environment||':'||apple_transaction_id,0));
    select * into purchase from private.purchase_transactions where environment=apple_environment and transaction_id=apple_transaction_id;
    if not found then
        select sparks into credit from public.spark_packs where store_product_id=apple_product_id;
        if credit is null then raise exception using errcode='22023',message='unknown_store_product'; end if;
        select id into actor from public.profiles where id=apple_account_token;
        insert into private.purchase_transactions(environment,transaction_id,user_id,store_product_id,credited_sparks,
            app_account_token,is_credited,is_refunded,status_event_date,last_event_id)
            values(apple_environment,apple_transaction_id,actor,apple_product_id,credit,apple_account_token,false,
                apple_is_refunded,apple_event_date,apple_event_id);
        return jsonb_build_object('status','recorded');
    end if;
    if purchase.app_account_token is distinct from apple_account_token or purchase.store_product_id is distinct from apple_product_id then
        raise exception using errcode='22023',message='transaction_account_or_product_conflict';
    end if;
    if apple_event_date < purchase.status_event_date or apple_event_id=purchase.last_event_id
       or (apple_event_date=purchase.status_event_date and not apple_is_refunded and purchase.is_refunded) then
        return jsonb_build_object('status','already_applied');
    end if;
    actor := purchase.user_id;
    if actor is not null then
        perform 1 from private.accounts where user_id=actor for share;
        if not found then actor := null; end if;
    end if;
    if purchase.is_credited and purchase.is_refunded is distinct from apple_is_refunded and actor is not null then
        amount := case when apple_is_refunded then -purchase.credited_sparks else purchase.credited_sparks end;
        perform private.adjust_payment_wallet(actor,apple_environment,amount);
        insert into private.wallet_ledger(user_id,delta,reason,reference,environment) values(actor,amount,
            case when apple_is_refunded then 'storekit_refund' else 'storekit_refund_reversal' end,
            'apple:'||apple_environment||':'||apple_transaction_id||':event:'||apple_event_id,apple_environment);
    end if;
    update private.purchase_transactions set is_refunded=apple_is_refunded,status_event_date=apple_event_date,last_event_id=apple_event_id
        where environment=apple_environment and transaction_id=apple_transaction_id;
    return jsonb_build_object('status','applied');
end;
$$;
create function public.apply_apple_refund(apple_environment text,apple_transaction_id text,apple_product_id text,
    apple_account_token uuid,apple_event_id text,apple_event_date bigint,apple_is_refunded boolean) returns jsonb
language sql volatile security invoker set search_path='' as $$
    select private.apply_apple_refund(apple_environment,apple_transaction_id,apple_product_id,apple_account_token,apple_event_id,apple_event_date,apple_is_refunded);
$$;

revoke all on function private.payment_wallet_snapshot(uuid,text),private.adjust_payment_wallet(uuid,text,bigint),
    private.payment_state(),public.payment_state(),private.payment_server_settings(),public.payment_server_settings(),
    private.credit_apple_purchase(uuid,uuid,text,text,text,uuid),public.credit_apple_purchase(uuid,uuid,text,text,text,uuid),
    private.apply_apple_refund(text,text,text,uuid,text,bigint,boolean),public.apply_apple_refund(text,text,text,uuid,text,bigint,boolean)
    from public,anon,authenticated;
grant execute on function private.payment_state(),public.payment_state() to authenticated;
grant execute on function private.payment_server_settings(),public.payment_server_settings(),
    private.credit_apple_purchase(uuid,uuid,text,text,text,uuid),public.credit_apple_purchase(uuid,uuid,text,text,text,uuid),
    private.apply_apple_refund(text,text,text,uuid,text,bigint,boolean),public.apply_apple_refund(text,text,text,uuid,text,bigint,boolean) to service_role;

comment on table private.payment_settings is 'Non-secret payment routing. Disabled until real Apple app, key and products are configured. Apple private key is Edge secret only.';
comment on table private.sandbox_wallets is 'Sandbox units never affect production balances or future production entitlements.';
comment on function public.credit_apple_purchase(uuid,uuid,text,text,text,uuid) is 'Service-only. Arguments must come from an authenticated Apple HTTPS transaction lookup, not decoded client claims.';
commit;
