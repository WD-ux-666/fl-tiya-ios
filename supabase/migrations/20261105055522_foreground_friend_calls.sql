-- Foreground, friends-only calls. RTC is disabled until LiveKit Cloud secrets exist.
begin;
create table private.calls (
 id uuid primary key default gen_random_uuid(),
 caller_id uuid not null,
 callee_id uuid not null,
 cohort text not null check(cohort in ('production','development')),
 kind text not null check(kind in ('voice','video')),
 status text not null default 'ringing' check(status in ('ringing','accepted','rejected','ended','missed')),
 caller_session_id uuid not null,
 callee_session_id uuid,
 room_name text not null unique default ('fltiya_'||replace(gen_random_uuid()::text,'-','')),
 caller_identity uuid not null default gen_random_uuid(),
 callee_identity uuid not null default gen_random_uuid(),
 created_at timestamptz not null default clock_timestamp(),
 answered_at timestamptz,
 ended_at timestamptz,
 ended_reason text,
 expires_at timestamptz not null default (clock_timestamp()+interval '45 seconds'),
 caller_seen_at timestamptz not null default clock_timestamp(),
 callee_seen_at timestamptz,
 check(caller_id<>callee_id),
 check((status in ('ringing','accepted'))=(ended_at is null))
);
create index calls_active_caller on private.calls(caller_id) where status in ('ringing','accepted');
create index calls_active_callee on private.calls(callee_id) where status in ('ringing','accepted');
create table private.call_cleanup (
 call_id uuid primary key references private.calls(id),
 room_name text not null,
 identities uuid[] not null,
 -- LiveKit refreshes connected participants' tokens to ten minutes. Revoke
 -- repeatedly for twelve minutes, even if a delayed connect recreates a room.
 repeat_until timestamptz not null,
 next_attempt_at timestamptz not null default clock_timestamp(),
 lease_id uuid,
 lease_until timestamptz,
 attempts integer not null default 0,
 completed_at timestamptz,
 last_error text check(last_error is null or last_error in ('rtc_cleanup_failed','calls_unavailable'))
);
create index call_cleanup_due on private.call_cleanup(next_attempt_at) where completed_at is null;
create table private.call_worker_settings (
 singleton boolean primary key default true check(singleton),
 token_hash text not null check(token_hash ~ '^[a-f0-9]{64}$')
);
alter table private.calls enable row level security;
alter table private.call_cleanup enable row level security;
alter table private.call_worker_settings enable row level security;
revoke all on private.calls,private.call_cleanup,private.call_worker_settings from public,anon,authenticated;
-- No client policies: state is available only through the authenticated Edge
-- endpoint and its service-only, independently session-checked RPC.
do $$
declare worker_token text;
begin
 select decrypted_secret into worker_token from vault.decrypted_secrets where name='fltiya_call_worker_token';
 if worker_token is null then
  worker_token:=encode(extensions.gen_random_bytes(32),'hex');
  perform vault.create_secret(worker_token,'fltiya_call_worker_token','FL-Tiya private call cleanup worker');
 end if;
 insert into private.call_worker_settings(token_hash) values(encode(extensions.digest(worker_token,'sha256'),'hex'));
end $$;

create function private.call_user_eligible(target_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.account_is_eligible(target_user) and exists(select 1 from auth.users u where u.id=target_user
  and u.deleted_at is null and (u.banned_until is null or u.banned_until<=statement_timestamp()));
$$;
create function private.call_session_active(target_user uuid,target_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.call_user_eligible(target_user) and exists(
  select 1 from auth.sessions s join private.accounts a on a.user_id=s.user_id
  where s.id=target_session and s.user_id=target_user and (s.not_after is null or s.not_after>statement_timestamp())
   and (a.cohort='development' or exists(select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='oauth'))
 );
$$;
create function private.call_pair_allowed(first_user uuid,second_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.call_user_eligible(first_user) and private.call_user_eligible(second_user)
 and exists(select 1 from private.accounts a join private.accounts b on b.cohort=a.cohort where a.user_id=first_user and b.user_id=second_user)
 and exists(select 1 from public.friendships f where f.user_low=least(first_user,second_user) and f.user_high=greatest(first_user,second_user))
 and not exists(select 1 from public.blocks b where (b.owner_id=first_user and b.blocked_id=second_user) or (b.owner_id=second_user and b.blocked_id=first_user));
$$;
create function private.enqueue_call_worker() returns bigint
language plpgsql security definer set search_path='' as $$
declare worker_token text; request_id bigint;
begin
 if not exists(select 1 from private.call_cleanup where completed_at is null and next_attempt_at<=clock_timestamp() and (lease_until is null or lease_until<clock_timestamp())) then return null; end if;
 select decrypted_secret into worker_token from vault.decrypted_secrets where name='fltiya_call_worker_token';
 if worker_token is null then return null; end if;
 select net.http_post(url:='https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/call-service',
  headers:=jsonb_build_object('Content-Type','application/json','x-fltiya-call-worker',worker_token),
  body:='{"action":"cleanup"}'::jsonb,timeout_milliseconds:=60000) into request_id;
 return request_id;
end $$;
create function private.call_closed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.ended_at is null and new.ended_at is not null then
  insert into private.call_cleanup(call_id,room_name,identities,repeat_until)
   values(new.id,new.room_name,array[new.caller_identity,new.callee_identity],clock_timestamp()+interval '12 minutes') on conflict do nothing;
  perform private.enqueue_call_worker();
 end if;
 return new;
end $$;
create trigger fltiya_call_closed after update of status on private.calls for each row execute function private.call_closed();

create function private.sweep_calls(target_users uuid[] default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 update private.calls c set status=case when c.status='ringing' then 'missed' else 'ended' end,
  ended_at=clock_timestamp(),ended_reason=case
   when not private.call_pair_allowed(c.caller_id,c.callee_id) then 'relationship_unavailable'
   when not private.call_session_active(c.caller_id,c.caller_session_id) or (c.status='accepted' and not private.call_session_active(c.callee_id,c.callee_session_id)) then 'session_unavailable'
   when c.status='ringing' then 'unanswered' else 'heartbeat_expired' end
 where c.status in ('ringing','accepted') and (target_users is null or c.caller_id=any(target_users) or c.callee_id=any(target_users)) and (
  c.expires_at<=clock_timestamp() or not private.call_pair_allowed(c.caller_id,c.callee_id)
  or not private.call_session_active(c.caller_id,c.caller_session_id)
  or (c.status='accepted' and not private.call_session_active(c.callee_id,c.callee_session_id)));
end $$;
create function private.call_json(c private.calls,actor uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'caller_id',c.caller_id,'callee_id',c.callee_id,'kind',c.kind,'status',c.status,
  'created_at',c.created_at,'answered_at',c.answered_at,'ended_at',c.ended_at,'expires_at',c.expires_at,'ended_reason',c.ended_reason,
  'peer_id',p.id,'peer_display_name',p.display_name,'peer_avatar_path',p.avatar_path)
 from public.profiles p where p.id=case when c.caller_id=actor then c.callee_id else c.caller_id end;
$$;
create function private.call_action(actor_user_id uuid,actor_session_id uuid,action text,target_call_id uuid default null,target_user_id uuid default null,call_kind text default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare c private.calls; actor_cohort text; operation_time timestamptz:=clock_timestamp(); lock_users uuid[];
begin
 if not private.call_session_active(actor_user_id,actor_session_id) then raise exception using errcode='42501',message='invalid_session'; end if;
 if action is null or action not in ('create','state','accept','reject','end','heartbeat','token') then raise exception using errcode='22023',message='invalid_request'; end if;
 if action='create' and (target_user_id is null or actor_user_id=target_user_id or call_kind not in ('voice','video') or call_kind is null) then raise exception using errcode='22023',message='invalid_request'; end if;
 lock_users:=case when action='create' then array[actor_user_id,target_user_id] else array[actor_user_id] end;
 -- Auth deletion starts at auth.users and cascades through accounts and
 -- friendships. Use that same order for both participants, before pair/call
 -- locks, so account deletion cannot form a row-lock/pair-lock cycle.
 perform 1 from auth.users where id=any(lock_users) order by id for share;
 perform 1 from private.accounts where user_id=any(lock_users) order by user_id for share;
 perform 1 from auth.identities where user_id=any(lock_users) order by user_id,id for share;
 perform 1 from private.development_accounts where user_id=any(lock_users) order by user_id for share;
 perform 1 from auth.sessions where id=actor_session_id and user_id=actor_user_id for share;
 if not found or not private.call_session_active(actor_user_id,actor_session_id) then raise exception using errcode='42501',message='invalid_session'; end if;
 if action<>'create' then perform private.sweep_calls(array[actor_user_id]); end if;
 if action='create' then
  -- Sorted participant locks cover simultaneous A->B / C->B and opposite calls.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(least(actor_user_id,target_user_id)::text,8326));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(greatest(actor_user_id,target_user_id)::text,8326));
  perform private.lock_pair(actor_user_id,target_user_id);
  -- Match relationship mutation lock order before touching expired call rows.
  perform private.sweep_calls(array[actor_user_id,target_user_id]);
  if not private.call_pair_allowed(actor_user_id,target_user_id) then raise exception using errcode='42501',message='call_unavailable'; end if;
  if exists(select 1 from private.calls where status in ('ringing','accepted') and (caller_id in (actor_user_id,target_user_id) or callee_id in (actor_user_id,target_user_id))) then raise exception using errcode='23505',message='call_busy'; end if;
  if (select count(*) from private.calls where caller_id=actor_user_id and created_at>operation_time-interval '1 minute')>=6 then raise exception using errcode='P0001',message='call_rate_limited'; end if;
  select cohort into actor_cohort from private.accounts where user_id=actor_user_id;
  insert into private.calls(caller_id,callee_id,cohort,kind,caller_session_id) values(actor_user_id,target_user_id,actor_cohort,call_kind,actor_session_id) returning * into c;
 else
  if action='state' and target_call_id is null then
   -- A second device can ring, but cannot adopt a call already selected on
   -- another session and accidentally terminate that device's active room.
   select * into c from private.calls where status in ('ringing','accepted') and (
    (caller_id=actor_user_id and caller_session_id=actor_session_id)
    or (callee_id=actor_user_id and (status='ringing' or callee_session_id=actor_session_id))
   ) order by created_at desc limit 1;
   return jsonb_build_object('call',case when c.id is null then null else private.call_json(c,actor_user_id) end);
  end if;
  select * into c from private.calls where id=target_call_id and actor_user_id in (caller_id,callee_id) for update;
  if not found then raise exception using errcode='42501',message='call_unavailable'; end if;
  if action='state' and (
   (c.caller_id=actor_user_id and c.caller_session_id is distinct from actor_session_id)
   or (c.callee_id=actor_user_id and c.status<>'ringing' and c.callee_session_id is distinct from actor_session_id)
  ) then return jsonb_build_object('call',null); end if;
  if action='accept' then
   if c.callee_id<>actor_user_id then raise exception using errcode='42501',message='call_unavailable'; end if;
   if c.status='accepted' and c.callee_session_id=actor_session_id then return jsonb_build_object('call',private.call_json(c,actor_user_id)); end if;
   if c.status<>'ringing' then raise exception using errcode='P0001',message='call_not_ringing'; end if;
   if not private.call_pair_allowed(c.caller_id,c.callee_id) then raise exception using errcode='42501',message='call_unavailable'; end if;
   update private.calls set status='accepted',callee_session_id=actor_session_id,answered_at=operation_time,
    caller_seen_at=operation_time,callee_seen_at=operation_time,expires_at=operation_time+interval '45 seconds' where id=c.id returning * into c;
  elsif action='reject' then
   if c.callee_id<>actor_user_id then raise exception using errcode='42501',message='call_unavailable'; end if;
   if c.status='ringing' then update private.calls set status='rejected',ended_at=operation_time,ended_reason='rejected' where id=c.id returning * into c;
   elsif c.status<>'rejected' then raise exception using errcode='P0001',message='call_not_ringing'; end if;
  elsif action='end' then
   -- A stale device may still show ringing after another callee session
   -- accepts. Only the selected sessions may terminate an accepted call;
   -- outgoing cancellation also belongs to its creating caller session.
   if c.status in ('ringing','accepted') and (
    (c.caller_id=actor_user_id and c.caller_session_id is distinct from actor_session_id)
    or (c.callee_id=actor_user_id and c.status='accepted' and c.callee_session_id is distinct from actor_session_id)
   ) then raise exception using errcode='42501',message='call_unavailable'; end if;
   if c.status in ('ringing','accepted') then update private.calls set status='ended',ended_at=operation_time,ended_reason=case when c.status='ringing' then 'cancelled' else 'hangup' end where id=c.id returning * into c; end if;
  elsif action in ('heartbeat','token') then
   if c.status<>'accepted' then raise exception using errcode='P0001',message='call_not_accepted'; end if;
   if actor_session_id is distinct from (case when c.caller_id=actor_user_id then c.caller_session_id else c.callee_session_id end) then raise exception using errcode='42501',message='call_unavailable'; end if;
   if not private.call_pair_allowed(c.caller_id,c.callee_id) then raise exception using errcode='42501',message='call_unavailable'; end if;
   update private.calls set caller_seen_at=case when caller_id=actor_user_id then operation_time else caller_seen_at end,
    callee_seen_at=case when callee_id=actor_user_id then operation_time else callee_seen_at end,
    expires_at=least(case when caller_id=actor_user_id then operation_time else caller_seen_at end,
     case when callee_id=actor_user_id then operation_time else callee_seen_at end)+interval '45 seconds'
    where id=c.id returning * into c;
  end if;
 end if;
 if action='token' then
  return jsonb_build_object('call',private.call_json(c,actor_user_id),'room_name',c.room_name,
   'identity',case when c.caller_id=actor_user_id then c.caller_identity else c.callee_identity end);
 end if;
 return jsonb_build_object('call',private.call_json(c,actor_user_id));
end $$;
create function public.call_action(actor_user_id uuid,actor_session_id uuid,action text,target_call_id uuid default null,target_user_id uuid default null,call_kind text default null) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.call_action(actor_user_id,actor_session_id,action,target_call_id,target_user_id,call_kind); $$;

-- Relationship/account/session writes close database state in their transaction;
-- the durable outbox survives a failed/offline Edge/LiveKit request.
create function private.invalidate_calls() returns trigger
language plpgsql security definer set search_path='' as $$
declare first_user uuid; second_user uuid; session_to_revoke uuid;
begin
 if tg_table_schema='public' and tg_table_name='friendships' then first_user:=old.user_low;second_user:=old.user_high;
 elsif tg_table_schema='public' and tg_table_name='blocks' then first_user:=new.owner_id;second_user:=new.blocked_id;
 elsif tg_table_schema='auth' and tg_table_name='sessions' then
  -- Extending an active Auth session must not interrupt a foreground call.
  if tg_op='UPDATE' and (new.not_after is null or new.not_after>clock_timestamp()) then return null; end if;
  first_user:=old.user_id;session_to_revoke:=old.id;
 elsif tg_table_schema='auth' and tg_table_name='users' then first_user:=old.id;
 else first_user:=old.user_id; end if;
 if second_user is not null then perform private.lock_pair(first_user,second_user); end if;
 update private.calls set status='ended',ended_at=clock_timestamp(),ended_reason=case when second_user is null then 'session_unavailable' else 'relationship_unavailable' end
 where status in ('ringing','accepted') and first_user in (caller_id,callee_id)
  and (second_user is null or second_user in (caller_id,callee_id))
  and (session_to_revoke is null or session_to_revoke in (caller_session_id,callee_session_id));
 return null;
end $$;
create trigger fltiya_calls_friendship_removed after delete on public.friendships for each row execute function private.invalidate_calls();
create trigger fltiya_calls_blocked after insert on public.blocks for each row execute function private.invalidate_calls();
create trigger fltiya_calls_account_changed after update of state or delete on private.accounts for each row execute function private.invalidate_calls();
create trigger fltiya_calls_session_revoked after delete or update of not_after on auth.sessions for each row execute function private.invalidate_calls();
create trigger fltiya_calls_identity_changed after delete or update of user_id,provider on auth.identities for each row execute function private.invalidate_calls();
create trigger fltiya_calls_development_changed after update or delete on private.development_accounts for each row execute function private.invalidate_calls();
create trigger fltiya_calls_auth_user_changed after update of email,email_confirmed_at,is_anonymous,banned_until,deleted_at or delete on auth.users for each row execute function private.invalidate_calls();

create function private.claim_call_cleanup(worker_token text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 if worker_token is null or worker_token !~ '^[a-f0-9]{64}$' or not exists(select 1 from private.call_worker_settings where token_hash=encode(extensions.digest(worker_token,'sha256'),'hex')) then raise exception using errcode='42501',message='invalid_worker'; end if;
 perform private.sweep_calls();
 with due as (select call_id from private.call_cleanup where completed_at is null and next_attempt_at<=clock_timestamp()
  and (lease_until is null or lease_until<clock_timestamp()) order by next_attempt_at for update skip locked limit 8),
 claimed as (update private.call_cleanup c set lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '90 seconds',attempts=attempts+1
  from due where c.call_id=due.call_id returning c.*)
 select coalesce(jsonb_agg(jsonb_build_object('call_id',call_id,'lease_id',lease_id,'room_name',room_name,'identities',identities)),'[]'::jsonb) into result from claimed;
 return result;
end $$;
create function public.claim_call_cleanup(worker_token text) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.claim_call_cleanup(worker_token); $$;
create function private.finish_call_cleanup(target_call_id uuid,target_lease_id uuid,succeeded boolean,error_code text default null) returns void
language plpgsql volatile security definer set search_path='' as $$
begin
 update private.call_cleanup set lease_id=null,lease_until=null,
  completed_at=case when succeeded and repeat_until<clock_timestamp() then clock_timestamp() else null end,
  next_attempt_at=clock_timestamp()+case when succeeded then interval '45 seconds' else interval '30 seconds' end,
  last_error=case when succeeded then null when error_code='calls_unavailable' then 'calls_unavailable' else 'rtc_cleanup_failed' end
 where call_id=target_call_id and lease_id=target_lease_id;
end $$;
create function public.finish_call_cleanup(target_call_id uuid,target_lease_id uuid,succeeded boolean,error_code text default null) returns void
language sql volatile security invoker set search_path='' as $$ select private.finish_call_cleanup(target_call_id,target_lease_id,succeeded,error_code); $$;
create function private.maintain_calls() returns void
language plpgsql security definer set search_path='' as $$ begin perform private.sweep_calls();perform private.enqueue_call_worker();end $$;

revoke all on function private.call_user_eligible(uuid),private.call_session_active(uuid,uuid),private.call_pair_allowed(uuid,uuid),private.enqueue_call_worker(),private.call_closed(),private.sweep_calls(uuid[]),private.call_json(private.calls,uuid),
 private.call_action(uuid,uuid,text,uuid,uuid,text),public.call_action(uuid,uuid,text,uuid,uuid,text),private.invalidate_calls(),private.claim_call_cleanup(text),public.claim_call_cleanup(text),
 private.finish_call_cleanup(uuid,uuid,boolean,text),public.finish_call_cleanup(uuid,uuid,boolean,text),private.maintain_calls() from public,anon,authenticated;
grant execute on function private.call_action(uuid,uuid,text,uuid,uuid,text),public.call_action(uuid,uuid,text,uuid,uuid,text),private.claim_call_cleanup(text),public.claim_call_cleanup(text),
 private.finish_call_cleanup(uuid,uuid,boolean,text),public.finish_call_cleanup(uuid,uuid,boolean,text) to service_role;
-- Always safe to maintain/expire DB calls, including while RTC configuration is absent.
select cron.schedule('fltiya-call-maintenance','* * * * *','select private.maintain_calls()');
comment on table private.call_cleanup is 'Durable closed-room tombstones. Retry Cloud token revocation and DeleteRoom for 12 minutes; never delete on an HTTP enqueue alone.';
commit;
