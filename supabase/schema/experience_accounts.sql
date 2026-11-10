-- Real anonymous Auth users receive a server-attested, immutable production
-- account. Editable email metadata never resolves identity or authorization.
begin;
alter table private.accounts add column is_experience boolean not null default false;
alter table private.accounts add constraint experience_production_only check(not is_experience or cohort='production');
create function private.keep_account_experience() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if new.is_experience is distinct from old.is_experience then raise exception using errcode='42501',message='account_experience_is_immutable';end if;
 return new;
end $$;
create trigger fltiya_account_experience_immutable before update of is_experience on private.accounts for each row execute function private.keep_account_experience();
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
    if coalesce(new.is_anonymous,false) and assigned_cohort<>'production' then
        raise exception using errcode='42501',message='development_reservation_mismatch';
    end if;
    insert into private.accounts(user_id,cohort,is_experience) values(new.id,assigned_cohort,coalesce(new.is_anonymous,false));
    insert into public.profiles(id,handle,display_name) values(new.id,'player_'||replace(new.id::text,'-',''),
        case when assigned_cohort='development' then btrim(reservation.label) else 'Player' end);
    insert into public.wallets(user_id) values(new.id);
    return new;
end;
$$;


create or replace function private.account_is_eligible(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.accounts a join auth.users u on u.id=a.user_id
 where a.user_id=target_user_id and a.state='active' and u.deleted_at is null
 and (u.banned_until is null or u.banned_until<=statement_timestamp()) and (
  (a.cohort='production' and a.is_experience and u.is_anonymous is true)
  or (not a.is_experience and not coalesce(u.is_anonymous,false) and (
   (a.cohort='production' and exists(select 1 from auth.identities i where i.user_id=a.user_id and i.provider='apple'))
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
   or exists(select 1 from auth.mfa_amr_claims m where m.session_id=s.id
    and m.authentication_method=case when a.is_experience then 'anonymous' else 'oauth' end))
 );
$$;
create or replace function private.actor_is_active() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null
 and exists(select 1 from private.accounts a where a.user_id=auth.uid()
  and a.is_experience=coalesce((auth.jwt()->>'is_anonymous')::boolean,false))
 and private.call_session_active(auth.uid(),nullif(auth.jwt()->>'session_id','')::uuid);
$$;
create function private.actor_is_experience() returns boolean
language sql stable security definer set search_path='' as $$
 select private.actor_is_active() and exists(select 1 from private.accounts a where a.user_id=auth.uid() and a.is_experience and a.cohort='production');
$$;
create or replace function private.require_actor() returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=auth.uid(); actor_cohort text;
begin
 if not private.actor_is_active() then raise exception using errcode='42501',message='active_session_required';end if;
 -- Auth parent first: deleting an Auth user cascades into accounts/session.
 perform 1 from auth.users where id=actor for share;
 select a.cohort into actor_cohort from private.accounts a where a.user_id=actor and a.state='active' for share;
 if not found then raise exception using errcode='42501',message='active_account_required';end if;
 if actor_cohort='development' then
  perform 1 from private.development_accounts d where d.user_id=actor and d.enabled and d.expires_at>statement_timestamp() for share;
  if not found then raise exception using errcode='42501',message='active_session_required';end if;
 end if;
 perform 1 from auth.sessions s where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=actor for share;
 if not found or not private.actor_is_active() then raise exception using errcode='42501',message='active_session_required';end if;
 return actor;
end $$;
create or replace function private.session_context() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();result jsonb;
begin
 select jsonb_build_object('user_id',p.id,'display_name',p.display_name,'cohort',a.cohort,'is_experience',a.is_experience)
 into result from public.profiles p join private.accounts a on a.user_id=p.id where p.id=actor;
 if result is null then raise exception using errcode='42501',message='active_session_required';end if;
 return result;
end $$;
-- This exception grants approved content only. can_view_user and all social,
-- profile, card and avatar policies retain their existing cohort boundaries.
create function private.experience_can_read_post(target_post uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.actor_is_experience() and exists(select 1 from public.video_posts v
 join private.accounts owner_account on owner_account.user_id=v.owner_id
 where v.id=target_post and v.status='approved' and owner_account.cohort='development');
$$;
drop policy video_posts_read on public.video_posts;
create policy video_posts_read on public.video_posts for select to authenticated using(
 (select private.actor_is_active()) and (owner_id=(select auth.uid())
 or (status='approved' and private.can_view_user(owner_id)) or private.experience_can_read_post(id))
);
-- Published editorial references are content, independent of author profiles.
-- Existing publication validation, source constraints and trusted writes remain.
drop policy guides_read on public.guides;
create policy guides_read on public.guides for select to authenticated using(
 (select private.actor_is_active()) and status='published'
 and (cohort=(select private.current_cohort()) or (cohort='development' and (select private.actor_is_experience())))
);
drop policy fltiya_clip_read on storage.objects;
create policy fltiya_clip_read on storage.objects for select to authenticated using(
 bucket_id='clips' and (select private.actor_is_active())
 and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info'])
 and exists(select 1 from public.video_posts v where (v.video_path=name or v.thumbnail_path=name)
  and (v.owner_id=(select auth.uid()) or (v.status='approved' and private.can_view_user(v.owner_id)) or private.experience_can_read_post(v.id)))
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
    return jsonb_build_object('environment',effective_environment,'purchases_enabled',not development and not private.actor_is_experience() and settings.purchases_enabled,
        'purchase_unavailable_reason',case when private.actor_is_experience() then 'experience_account' else null end,
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
    select cohort into target_cohort from private.accounts where user_id=target_user_id and state='active' and not is_experience for share;
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


-- Serialize app-bucket object admission against account deletion. Otherwise a
-- concurrent upload could pass an earlier RLS snapshot and add a new owned
-- object after the deletion manifest/final emptiness check.
create function private.guard_app_object_account() returns trigger
language plpgsql security definer set search_path='' as $$
declare actor uuid;
begin
 if new.bucket_id not in ('avatars','clips') then return new;end if;
 if new.owner_id is null or new.owner_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
  raise exception using errcode='42501',message='active_account_required';
 end if;
 actor:=new.owner_id::uuid;
 perform 1 from auth.users where id=actor for share;
 if not found then raise exception using errcode='42501',message='active_account_required';end if;
 perform 1 from private.accounts where user_id=actor and state='active' for share;
 if not found then raise exception using errcode='42501',message='active_account_required';end if;
 return new;
end $$;
create trigger fltiya_object_active_account before insert on storage.objects for each row execute function private.guard_app_object_account();
-- Service-only deletion RPCs receive IDs exclusively from verified Auth /user
-- and JWT session claims in the Edge handler. No client-provided target exists.
create function private.require_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $$
begin
 -- Lock parent before cascaded rows and before calls/relationship locks.
 perform 1 from auth.users u where u.id=actor_user_id and u.is_anonymous is true
  and u.deleted_at is null and (u.banned_until is null or u.banned_until<=statement_timestamp()) for update;
 if not found then raise exception using errcode='42501',message='experience_session_required';end if;
 perform 1 from private.accounts a where a.user_id=actor_user_id and a.is_experience and a.cohort='production' and a.state in ('active','deleting') for update;
 if not found then raise exception using errcode='42501',message='experience_session_required';end if;
 perform 1 from auth.sessions s where s.id=actor_session_id and s.user_id=actor_user_id
  and (s.not_after is null or s.not_after>statement_timestamp()) and exists(
   select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='anonymous') for share;
 if not found then raise exception using errcode='42501',message='experience_session_required';end if;
end $$;
create function private.prepare_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare objects jsonb;
begin
 perform private.require_experience_deletion(actor_user_id,actor_session_id);
 update private.accounts set state='deleting' where user_id=actor_user_id and state='active';
 -- Retain this one live session so a failed external Storage deletion can be
 -- retried; actor_is_active already rejects every app operation while deleting.
 delete from auth.sessions where user_id=actor_user_id and id<>actor_session_id;
 select coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) into objects from (
  select bucket_id,name from storage.objects where bucket_id in ('avatars','clips')
   and owner_id=actor_user_id::text and (storage.foldername(name))[1]=actor_user_id::text order by bucket_id,name limit 500
 ) o;
 return jsonb_build_object('user_id',actor_user_id,'objects',objects);
end $$;
create function private.finish_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 perform private.require_experience_deletion(actor_user_id,actor_session_id);
 if not exists(select 1 from private.accounts where user_id=actor_user_id and state='deleting') then raise exception using errcode='42501',message='experience_session_required';end if;
 if exists(select 1 from storage.objects where owner_id=actor_user_id::text or owner=actor_user_id) then
  raise exception using errcode='55000',message='experience_objects_remaining';
 end if;
 -- Official anonymous Auth cleanup supports deleting auth.users. An atomic
 -- checked delete prevents linking/revocation races between check and removal.
 -- Existing FK cascades remove profile/cards/social/messages and Auth sessions;
 -- call cleanup deliberately has no Auth FK and survives for worker retries.
 delete from auth.users where id=actor_user_id;
 return jsonb_build_object('deleted',true);
end $$;
create function public.prepare_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.prepare_experience_deletion($1,$2); $$;
create function public.finish_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.finish_experience_deletion($1,$2); $$;
revoke all on function private.guard_app_object_account(),private.keep_account_experience(),private.actor_is_experience(),private.experience_can_read_post(uuid),
 private.require_experience_deletion(uuid,uuid),private.prepare_experience_deletion(uuid,uuid),private.finish_experience_deletion(uuid,uuid),
 public.prepare_experience_deletion(uuid,uuid),public.finish_experience_deletion(uuid,uuid) from public,anon,authenticated;
grant execute on function private.actor_is_experience(),private.experience_can_read_post(uuid) to authenticated;
grant execute on function private.prepare_experience_deletion(uuid,uuid),private.finish_experience_deletion(uuid,uuid),public.prepare_experience_deletion(uuid,uuid),public.finish_experience_deletion(uuid,uuid) to service_role;
comment on column private.accounts.is_experience is 'Immutable server attestation set only at real anonymous Auth creation. No metadata/email identity lookup.';
comment on function private.experience_can_read_post(uuid) is 'Approved development clips only; never permits development profiles/social data or Storage listing.';
commit;
