-- Add verified email/password alongside the existing Apple and isolated
-- development/experience paths. Does not change provider settings, account
-- cohorts, existing content visibility, or StoreKit transaction credit rules.
begin;

-- Supabase owns the Auth user and identity records. A matching email identity
-- and confirmed address are required; app-editable metadata is not consulted.
-- Keep Supabase Confirm email enabled for ownership verification on signup.
create function private.has_confirmed_email_identity(target_user uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(
  select 1 from auth.users u join auth.identities i on i.user_id=u.id and i.provider='email'
  where u.id=target_user and not coalesce(u.is_anonymous,false)
   and u.email_confirmed_at is not null and nullif(u.email,'') is not null and i.email=lower(u.email)
 );
$$;
revoke all on function private.has_confirmed_email_identity(uuid) from public,anon,authenticated,service_role;

create or replace function private.account_is_eligible(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.accounts a join auth.users u on u.id=a.user_id
 where a.user_id=target_user_id and a.state='active' and u.deleted_at is null
 and (u.banned_until is null or u.banned_until<=statement_timestamp()) and (
  (a.cohort='production' and a.is_experience and u.is_anonymous is true)
  or (not a.is_experience and not coalesce(u.is_anonymous,false) and (
   (a.cohort='production' and (
    exists(select 1 from auth.identities i where i.user_id=a.user_id and i.provider='apple')
    or private.has_confirmed_email_identity(a.user_id)))
   or (a.cohort='development' and u.email_confirmed_at is not null
    and exists(select 1 from auth.identities i where i.user_id=a.user_id and i.provider='email')
    and exists(select 1 from private.development_accounts d where d.user_id=a.user_id and d.email=lower(u.email) and d.enabled and d.expires_at>statement_timestamp()))
  ))
 ));
$$;

create or replace function private.call_session_active(target_user uuid,target_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.call_user_eligible(target_user) and exists(
  select 1 from auth.sessions s join private.accounts a on a.user_id=s.user_id
  where s.id=target_session and s.user_id=target_user and (s.not_after is null or s.not_after>statement_timestamp())
  and ((a.cohort='development' and not a.is_experience)
   or (a.cohort='production' and exists(
    select 1 from auth.mfa_amr_claims m where m.session_id=s.id and (
     (a.is_experience and m.authentication_method='anonymous')
     or (not a.is_experience and (
      (m.authentication_method='oauth'
       and exists(select 1 from auth.identities i where i.user_id=s.user_id and i.provider='apple'))
      or (m.authentication_method='password' and private.has_confirmed_email_identity(s.user_id))
     ))
    )
   )))
 );
$$;

create or replace function private.payment_state() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid; settings private.payment_settings; packs jsonb; history jsonb; effective_environment text; development boolean; experience boolean; apple_session boolean;
begin
    actor := private.require_actor();
    development := private.current_cohort()='development';
    experience := private.actor_is_experience();
    -- Transaction credit still requires an Apple identity and OAuth session.
    apple_session := not development and not experience and exists(
        select 1 from auth.identities i where i.user_id=actor and i.provider='apple'
    ) and exists(
        select 1 from auth.mfa_amr_claims m
        where m.session_id=nullif(auth.jwt()->>'session_id','')::uuid and m.authentication_method='oauth'
    );
    select * into strict settings from private.payment_settings where singleton;
    effective_environment := case when development then 'Sandbox' else settings.store_environment end;
    select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'sparks',p.sparks,
        'store_product_id',p.store_product_id,'is_active',p.is_active,
        'reference_price_usd',p.reference_price_usd::text,'sort_order',p.sort_order) order by p.sort_order,p.id),'[]'::jsonb)
        into packs from public.spark_packs p;
    select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id),'[]'::jsonb) into history from
        (select l.id,l.delta,l.reason,l.created_at from private.wallet_ledger l
         where l.user_id=actor and l.environment=effective_environment order by l.created_at desc,l.id limit 50) h;
    return jsonb_build_object('environment',effective_environment,'purchases_enabled',apple_session and settings.purchases_enabled,
        'purchase_unavailable_reason',case when experience then 'experience_account' when not development and not apple_session then 'apple_sign_in_required' else null end,
        'wallet',private.payment_wallet_snapshot(actor,effective_environment),'packs',packs,'history',history);
end;
$$;

create or replace function private.require_account_deletion(actor_user_id uuid,actor_session_id uuid) returns text
language plpgsql volatile security definer set search_path='' as $$
declare actor auth.users; account private.accounts;
begin
 select * into actor from auth.users u where u.id=actor_user_id and u.deleted_at is null
  and (u.banned_until is null or u.banned_until<=statement_timestamp()) for update;
 if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 select * into account from private.accounts a where a.user_id=actor_user_id and a.state in ('active','deleting') for update;
 if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 -- Never destroy a linked Apple account without revoking its authorization.
 -- This applies to password sessions for linked accounts as well.
 if exists(select 1 from auth.identities where user_id=actor_user_id and provider='apple') then
  raise exception using errcode='42501',message='apple_revocation_configuration_required';
 end if;
 if account.cohort='production' and account.is_experience and actor.is_anonymous is true then
  perform 1 from auth.sessions s where s.id=actor_session_id and s.user_id=actor_user_id
   and (s.not_after is null or s.not_after>statement_timestamp()) and exists(
    select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='anonymous') for share;
  if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 elsif account.cohort='production' and not account.is_experience and private.has_confirmed_email_identity(actor_user_id) then
  perform 1 from auth.sessions s where s.id=actor_session_id and s.user_id=actor_user_id
   and (s.not_after is null or s.not_after>statement_timestamp()) and exists(
    select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='password') for share;
  if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 elsif account.cohort='development' and not account.is_experience and not coalesce(actor.is_anonymous,false)
  and actor.email_confirmed_at is not null
  and exists(select 1 from auth.identities where user_id=actor_user_id and provider='email') then
  -- Prepare disables this reservation. The same live session may retry while
  -- deleting, but a disabled/expired active account cannot start deletion.
  perform 1 from private.development_accounts d where d.user_id=actor_user_id and d.email=lower(actor.email)
   and (account.state='deleting' or (d.enabled and d.expires_at>statement_timestamp())) for update;
  if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
  perform 1 from auth.sessions s where s.id=actor_session_id and s.user_id=actor_user_id
   and (s.not_after is null or s.not_after>statement_timestamp()) for share;
  if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 else
  raise exception using errcode='42501',message='account_deletion_session_required';
 end if;
 return account.cohort;
end $$;

comment on function public.prepare_account_deletion(uuid,uuid) is
 'Service-only verified current experience, password or development self-delete. Linked Apple identities require Apple revocation before mutation.';
commit;
