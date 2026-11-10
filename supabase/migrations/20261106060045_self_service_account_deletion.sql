-- Apply through the selected FL-Tiya project's migration tool, then save its
-- exact returned migration version. No existing account is deleted by this DDL.
begin;

-- A retired test reservation is a permanent tombstone. This also closes an
-- in-flight development-login lookup racing with a completed account deletion.
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path='' as $$
declare assigned_cohort text := 'production'; reservation private.development_accounts;
begin
 select * into reservation from private.development_accounts d
  where d.user_id=new.id or d.email=lower(new.email) for share;
 if found then
  if reservation.user_id is distinct from new.id or reservation.email is distinct from lower(new.email)
   or not reservation.enabled or reservation.expires_at<=statement_timestamp() then
   raise exception using errcode='42501',message='development_reservation_mismatch';
  end if;
  assigned_cohort:='development';
 end if;
 if coalesce(new.is_anonymous,false) and assigned_cohort<>'production' then
  raise exception using errcode='42501',message='development_reservation_mismatch';
 end if;
 insert into private.accounts(user_id,cohort,is_experience) values(new.id,assigned_cohort,coalesce(new.is_anonymous,false));
 insert into public.profiles(id,handle,display_name) values(new.id,'player_'||replace(new.id::text,'-',''),
  case when assigned_cohort='development' then btrim(reservation.label) else 'Player' end);
 insert into public.wallets(user_id) values(new.id);
 return new;
end $$;

-- IDs come only from the Edge function's verified /user and JWT session_id.
-- Auth parent -> account -> reservation -> session is the existing lock order.
create function private.require_account_deletion(actor_user_id uuid,actor_session_id uuid) returns text
language plpgsql volatile security definer set search_path='' as $$
declare actor auth.users; account private.accounts;
begin
 select * into actor from auth.users u where u.id=actor_user_id and u.deleted_at is null
  and (u.banned_until is null or u.banned_until<=statement_timestamp()) for update;
 if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 select * into account from private.accounts a where a.user_id=actor_user_id and a.state in ('active','deleting') for update;
 if not found then raise exception using errcode='42501',message='account_deletion_session_required';end if;
 -- Never destroy a linked Apple account without revoking its authorization.
 -- Apple is disabled in this project; no grant/token exchange is configured.
 if exists(select 1 from auth.identities where user_id=actor_user_id and provider='apple') then
  raise exception using errcode='42501',message='apple_revocation_configuration_required';
 end if;
 if account.cohort='production' and account.is_experience and actor.is_anonymous is true then
  perform 1 from auth.sessions s where s.id=actor_session_id and s.user_id=actor_user_id
   and (s.not_after is null or s.not_after>statement_timestamp()) and exists(
    select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='anonymous') for share;
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

-- Older clients keep the anonymous-only endpoint, with the same Apple guard.
-- Its prepare/finish orchestration and grants remain unchanged.
create or replace function private.require_experience_deletion(actor_user_id uuid,actor_session_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $$
begin
 perform private.require_account_deletion(actor_user_id,actor_session_id);
 if not exists(select 1 from private.accounts a join auth.users u on u.id=a.user_id
  where a.user_id=actor_user_id and a.cohort='production' and a.is_experience and u.is_anonymous is true) then
  raise exception using errcode='42501',message='experience_session_required';
 end if;
end $$;

create function private.prepare_account_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor_cohort text; objects jsonb;
begin
 actor_cohort:=private.require_account_deletion(actor_user_id,actor_session_id);
 update private.accounts set state='deleting' where user_id=actor_user_id and state='active';
 if actor_cohort='development' then
  update private.development_accounts set enabled=false where user_id=actor_user_id and enabled;
 end if;
 -- Keep only the verified deletion driver to resume Storage/transport failures.
 -- Every app data operation and upload is already denied by deleting state.
 delete from auth.sessions where user_id=actor_user_id and id<>actor_session_id;
 select coalesce(jsonb_agg(to_jsonb(o)),'[]'::jsonb) into objects from (
  select bucket_id,name from storage.objects where bucket_id in ('avatars','clips')
   and owner_id=actor_user_id::text and (storage.foldername(name))[1]=actor_user_id::text
  order by bucket_id,name limit 500
 ) o;
 return jsonb_build_object('user_id',actor_user_id,'objects',objects);
end $$;

create function private.finish_account_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
begin
 perform private.require_account_deletion(actor_user_id,actor_session_id);
 if not exists(select 1 from private.accounts where user_id=actor_user_id and state='deleting') then
  raise exception using errcode='42501',message='account_deletion_session_required';
 end if;
 if exists(select 1 from storage.objects where owner_id=actor_user_id::text or owner=actor_user_id) then
  raise exception using errcode='55000',message='account_objects_remaining';
 end if;
 -- Auth parents/identities and the current deletion session are locked in this
 -- transaction. Cascades remove profile, uploads, social rows and Auth sessions.
 -- Financial audit rows, test reservation tombstones and external call cleanup
 -- records intentionally survive according to their existing FK/retention rules.
 delete from auth.users where id=actor_user_id;
 return jsonb_build_object('deleted',true);
end $$;
create function public.prepare_account_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.prepare_account_deletion($1,$2); $$;
create function public.finish_account_deletion(actor_user_id uuid,actor_session_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.finish_account_deletion($1,$2); $$;
revoke all on function private.require_account_deletion(uuid,uuid),private.prepare_account_deletion(uuid,uuid),private.finish_account_deletion(uuid,uuid),
 public.prepare_account_deletion(uuid,uuid),public.finish_account_deletion(uuid,uuid) from public,anon,authenticated;
grant execute on function private.prepare_account_deletion(uuid,uuid),private.finish_account_deletion(uuid,uuid),
 public.prepare_account_deletion(uuid,uuid),public.finish_account_deletion(uuid,uuid) to service_role;
comment on function public.prepare_account_deletion(uuid,uuid) is 'Service-only verified current experience/development self-delete. Linked Apple identities fail before mutation until revocation is configured.';
commit;
