-- Apply once after core.sql, the Storage restriction and payments.sql, only on
-- the authorized FL-Tiya project. Reservations contain hashes, never raw codes.
begin;

alter table private.accounts add column cohort text not null default 'production'
    check (cohort in ('production','development'));
alter table public.guides add column cohort text not null default 'production'
    check (cohort in ('production','development'));

-- No Auth FK: the UUID/email must be reserved BEFORE Admin Auth creates a user.
-- Keeping cohort separately on accounts prevents removal of a reservation from
-- ever promoting its existing profile into the production directory.
create table private.development_accounts (
    user_id uuid primary key check (user_id <> '00000000-0000-0000-0000-000000000000'::uuid),
    email text not null unique check (email=lower(btrim(email)) and char_length(email) between 3 and 254),
    label text not null check (char_length(btrim(label)) between 1 and 80),
    code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
    enabled boolean not null default true,
    expires_at timestamptz not null
);
alter table private.development_accounts enable row level security;
revoke all on private.development_accounts from public,anon,authenticated;
grant all on private.development_accounts to service_role;

create function private.keep_account_cohort() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    if new.cohort is distinct from old.cohort then
        raise exception using errcode='42501',message='account_cohort_is_immutable';
    end if;
    return new;
end;
$$;
create trigger fltiya_account_cohort_immutable before update of cohort on private.accounts
    for each row execute function private.keep_account_cohort();

create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$
declare assigned_cohort text := 'production'; reservation private.development_accounts;
begin
    -- Auth runs this trigger before creating identities or confirming email.
    -- A wrong UUID OR email fails the whole Auth transaction, rather than
    -- producing a transient production profile for a reserved test email.
    select * into reservation from private.development_accounts d
        where d.user_id=new.id or d.email=lower(new.email) for share;
    if found then
        if reservation.user_id is distinct from new.id
           or reservation.email is distinct from lower(new.email) then
            raise exception using errcode='42501',message='development_reservation_mismatch';
        end if;
        assigned_cohort := 'development';
    end if;
    insert into private.accounts(user_id,cohort) values(new.id,assigned_cohort);
    insert into public.profiles(id,handle,display_name) values(new.id,'player_'||replace(new.id::text,'-',''),
        case when assigned_cohort='development' then btrim(reservation.label) else 'Player' end);
    insert into public.wallets(user_id) values(new.id);
    return new;
end;
$$;

-- Target eligibility does not require the target to be online. It does require
-- a legitimate server-owned identity, so ordinary email signups and fabricated
-- user_metadata cannot populate the production player directory.
create function private.account_is_eligible(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select exists (
        select 1 from private.accounts a join auth.users u on u.id=a.user_id
        where a.user_id=target_user_id and a.state='active' and not coalesce(u.is_anonymous,false)
        and (
            (a.cohort='production' and exists (
                select 1 from auth.identities i where i.user_id=a.user_id and i.provider='apple'))
            or (a.cohort='development' and u.email_confirmed_at is not null
                and exists (select 1 from auth.identities i where i.user_id=a.user_id and i.provider='email')
                and exists (select 1 from private.development_accounts d
                    where d.user_id=a.user_id and d.email=lower(u.email)
                      and d.enabled and d.expires_at>statement_timestamp()))
        )
    );
$$;

create function private.current_cohort() returns text
language sql stable security definer set search_path='' as $$
    select a.cohort from private.accounts a where a.user_id=auth.uid();
$$;

create or replace function private.actor_is_active() returns boolean
language sql stable security definer set search_path='' as $$
    select auth.uid() is not null
       and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
       and private.account_is_eligible(auth.uid())
       and exists (select 1 from auth.sessions s
           where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=auth.uid()
             and (private.current_cohort()='development' or exists (
                 select 1 from auth.mfa_amr_claims amr
                 where amr.session_id=s.id and amr.authentication_method='oauth')));
$$;

-- This predicate deliberately excludes block state so repeat block mutations
-- remain idempotent. The caller must also possess an active session.
create function private.same_cohort_target(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_active() and private.account_is_eligible(target_user_id) and exists (
        select 1 from private.accounts actor join private.accounts target on target.cohort=actor.cohort
        where actor.user_id=auth.uid() and target.user_id=target_user_id
    );
$$;

create or replace function private.can_view_user(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_active() and private.same_cohort_target(target_user_id)
       and not exists (
           select 1 from public.blocks b
           where (b.owner_id=auth.uid() and b.blocked_id=target_user_id)
              or (b.owner_id=target_user_id and b.blocked_id=auth.uid())
       );
$$;

-- Existing friend request/accept/send helpers and conversation/Storage policies
-- all call can_view_user. Cohorts cannot change while those rows are in use.
create or replace function private.require_actor() returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid := auth.uid(); actor_cohort text;
begin
    if not private.actor_is_active() then
        raise exception using errcode='42501',message='active_session_required';
    end if;
    select a.cohort into actor_cohort from private.accounts a
        where a.user_id=actor and a.state='active' for share;
    if not found then raise exception using errcode='42501',message='active_account_required'; end if;
    perform 1 from auth.sessions s
        where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=actor for share;
    if not found then raise exception using errcode='42501',message='active_session_required'; end if;
    if actor_cohort='development' then
        perform 1 from private.development_accounts d where d.user_id=actor
            and d.enabled and d.expires_at>statement_timestamp() for share;
        if not found then raise exception using errcode='42501',message='active_session_required'; end if;
    end if;
    if not private.actor_is_active() then
        raise exception using errcode='42501',message='active_session_required';
    end if;
    return actor;
end;
$$;

create or replace function private.block_user(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid := private.require_actor();
begin
    if target_user_id is null or target_user_id=actor then
        raise exception using errcode='22023',message='invalid_target_user';
    end if;
    perform private.lock_pair(actor,target_user_id);
    if not private.same_cohort_target(target_user_id) then
        raise exception using errcode='42501',message='user_unavailable';
    end if;
    insert into public.blocks(owner_id,blocked_id) values(actor,target_user_id) on conflict do nothing;
    update public.friend_requests r set status='cancelled' where r.status='pending'
        and least(r.sender_id,r.recipient_id)=least(actor,target_user_id)
        and greatest(r.sender_id,r.recipient_id)=greatest(actor,target_user_id);
    delete from public.friendships f where f.user_low=least(actor,target_user_id) and f.user_high=greatest(actor,target_user_id);
    return jsonb_build_object('blocked_user_id',target_user_id);
end;
$$;

create function private.session_context() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid := private.require_actor(); result jsonb;
begin
    select jsonb_build_object('user_id',p.id,'display_name',p.display_name,'cohort',a.cohort)
        into result from public.profiles p join private.accounts a on a.user_id=p.id where p.id=actor;
    if result is null then raise exception using errcode='42501',message='active_session_required'; end if;
    return result;
end;
$$;
create function public.session_context() returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.session_context(); $$;

-- Only the server Edge function may resolve hashes. A reservation is useful
-- before provisioning, but an existing Auth user must match exactly and still
-- be an eligible development account. All invalid cases have the same null.
create function private.development_login_context(code_hash text) returns jsonb
language sql stable security definer set search_path='' as $$
    select jsonb_build_object('user_id',d.user_id,'email',d.email,'label',d.label,
        'exists',exists(select 1 from auth.users u where u.id=d.user_id and lower(u.email)=d.email))
    from private.development_accounts d
    where $1 ~ '^[0-9a-f]{64}$' and d.code_hash=$1 and d.enabled and d.expires_at>statement_timestamp()
      and not exists (select 1 from auth.users u where (u.id=d.user_id or lower(u.email)=d.email)
          and (u.id is distinct from d.user_id or lower(u.email) is distinct from d.email))
      and (not exists(select 1 from auth.users u where u.id=d.user_id)
           or (private.account_is_eligible(d.user_id) and exists(
               select 1 from private.accounts a where a.user_id=d.user_id and a.cohort='development')));
$$;
create function public.development_login_context(code_hash text) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.development_login_context($1); $$;

drop policy guides_read on public.guides;
create policy guides_read on public.guides for select to authenticated using (
    (select private.actor_is_active()) and status='published' and cohort=(select private.current_cohort())
);
drop policy blocks_read on public.blocks;
create policy blocks_read on public.blocks for select to authenticated using (
    owner_id=(select auth.uid()) and private.same_cohort_target(blocked_id)
);
drop policy wallets_read on public.wallets;
create policy wallets_read on public.wallets for select to authenticated using (
    (select private.actor_is_active()) and (select private.current_cohort())='production' and user_id=(select auth.uid())
);

create or replace function private.payment_state() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid; settings private.payment_settings; packs jsonb; history jsonb; effective_environment text; development boolean;
begin
    actor := private.require_actor();
    development := private.current_cohort()='development';
    select * into strict settings from private.payment_settings where singleton;
    effective_environment := case when development then 'Sandbox' else settings.store_environment end;
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'sparks',p.sparks,
        'store_product_id',p.store_product_id,'is_active',p.is_active,
        'reference_price_usd',p.reference_price_usd::text,'sort_order',p.sort_order) order by p.sort_order,p.id),'[]'::jsonb)
        into packs from public.spark_packs p;
    select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id),'[]'::jsonb) into history from
        (select l.id,l.delta,l.reason,l.created_at from private.wallet_ledger l
         where l.user_id=actor and l.environment=effective_environment order by l.created_at desc,l.id limit 50) h;
    return jsonb_build_object('environment',effective_environment,'purchases_enabled',not development and settings.purchases_enabled,
        'wallet',private.payment_wallet_snapshot(actor,effective_environment),'packs',packs,'history',history);
end;
$$;

create or replace function private.credit_apple_purchase(target_user_id uuid,target_session_id uuid,apple_environment text,
    apple_transaction_id text,apple_product_id text,apple_account_token uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare purchase private.purchase_transactions; credit bigint; result text; target_cohort text;
begin
    if target_user_id is null or target_session_id is null or apple_account_token is distinct from target_user_id
       or apple_environment not in ('Production','Sandbox') or apple_environment is null
       or apple_transaction_id is null or apple_transaction_id !~ '^[0-9]{1,100}$'
       or apple_product_id is null or length(apple_product_id) not between 1 and 200 then
        raise exception using errcode='22023',message='invalid_verified_transaction';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apple:'||apple_environment||':'||apple_transaction_id,0));
    select cohort into target_cohort from private.accounts where user_id=target_user_id and state='active' for share;
    if not found or (target_cohort='development' and apple_environment='Production') then
        raise exception using errcode='42501',message='active_apple_session_required';
    end if;
    perform 1 from auth.sessions where id=target_session_id and user_id=target_user_id for share;
    if not found or not exists(select 1 from auth.identities where user_id=target_user_id and provider='apple')
       or not private.account_is_eligible(target_user_id)
       or (target_cohort='production' and not exists (
           select 1 from auth.mfa_amr_claims amr
           where amr.session_id=target_session_id and amr.authentication_method='oauth')) then
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

-- CREATE OR REPLACE preserves existing ACLs. Explicitly bound all new helpers;
-- service-only hash lookup is never executable by anon/authenticated/PUBLIC.
revoke all on function private.keep_account_cohort(),private.account_is_eligible(uuid),private.current_cohort(),
    private.same_cohort_target(uuid),private.session_context(),public.session_context(),
    private.development_login_context(text),public.development_login_context(text) from public,anon,authenticated;
grant execute on function private.current_cohort(),private.same_cohort_target(uuid),private.session_context(),public.session_context() to authenticated;
grant execute on function private.development_login_context(text),public.development_login_context(text) to service_role;

comment on column private.accounts.cohort is 'Immutable server-assigned data realm. Reservation revocation never promotes a development identity to production.';
comment on table private.development_accounts is 'Server-only pre-provisioning reservations. UUID has no Auth FK; only SHA256 access-code hashes are retained.';
comment on function public.session_context() is 'Current active Auth session and server cohort, never derived from editable user metadata.';
comment on function public.development_login_context(text) is 'Service-role only. Returns an eligible exact reserved Auth identity or null; no raw access codes.';
commit;
