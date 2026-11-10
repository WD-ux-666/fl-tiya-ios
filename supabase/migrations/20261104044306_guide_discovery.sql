-- FL-Tiya guide discovery. Canonical migration source; apply after independent review.
-- The scheduler stays disabled here. Enable only after deploying its Edge Function.
begin;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create table private.guide_crawl_settings (
 source_key text primary key check (source_key='steam_zzz_official_rss'),
 game_id text not null references public.games(id) check (game_id='zenless-zone-zero'),
 cohort text not null check (cohort='development'),
 enabled boolean not null default false,
 token_hash text not null check (token_hash ~ '^[a-f0-9]{64}$'),
 next_allowed_at timestamptz not null default '-infinity',
 created_at timestamptz not null default now()
);
create table private.guide_crawl_runs (
 id uuid primary key default gen_random_uuid(),
 source_key text not null references private.guide_crawl_settings(source_key),
 cohort text not null check (cohort='development'),
 game_id text not null references public.games(id),
 state text not null default 'running' check (state in ('running','completed','failed')),
 started_at timestamptz not null default now(),
 finished_at timestamptz,
 inserted_count integer not null default 0 check (inserted_count between 0 and 20),
 errors jsonb not null default '[]'::jsonb check (jsonb_typeof(errors)='array' and jsonb_array_length(errors)<=20),
 check ((state='running' and finished_at is null) or (state<>'running' and finished_at is not null))
);
create index guide_crawl_runs_source_started_idx on private.guide_crawl_runs(source_key,started_at desc);
create unique index guide_crawl_runs_one_active_idx on private.guide_crawl_runs(source_key) where state='running';
create table private.guide_candidates (
 id uuid primary key default gen_random_uuid(),
 source_key text not null references private.guide_crawl_settings(source_key),
 run_id uuid not null references private.guide_crawl_runs(id),
 cohort text not null check (cohort='development'),
 game_id text not null references public.games(id),
 source_guid text not null check (char_length(source_guid) between 1 and 300),
 source_url text not null check (source_url ~ '^https://steamcommunity[.]com/games/4162040/announcements/detail/[0-9]{1,24}$'),
 title text not null check (char_length(btrim(title)) between 1 and 200 and title !~ '[[:cntrl:]<>]'),
 source_name text not null default 'HoYoverse / COGNOSPHERE via Steam',
 source_author text check (source_author is null or (char_length(btrim(source_author)) between 1 and 120 and source_author !~ '[[:cntrl:]<>]')),
 source_published_at timestamptz not null,
 content_kind text not null check (content_kind in ('guide','reference','news','support')),
 summary text not null default '' check (char_length(summary)<=1000),
 review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
 discovered_at timestamptz not null default now(),
 unique (cohort,game_id,source_url),
 unique (cohort,source_key,source_guid),
 check (source_guid=source_url)
);
create index guide_candidates_pending_idx on private.guide_candidates(discovered_at desc) where review_status='pending';
create table private.guide_reviews (
 id uuid primary key default gen_random_uuid(),
 guide_id uuid references public.guides(id) on delete restrict,
 candidate_id uuid references private.guide_candidates(id) on delete restrict,
 decision text not null check (decision in ('pending','approved','rejected')),
 reviewed_by text not null check (char_length(btrim(reviewed_by)) between 1 and 120),
 note text not null default '' check (char_length(note)<=2000),
 created_at timestamptz not null default now(),
 check (guide_id is not null or candidate_id is not null)
);
create index guide_reviews_guide_idx on private.guide_reviews(guide_id,created_at desc);
create index guide_reviews_candidate_idx on private.guide_reviews(candidate_id,created_at desc);
create unique index if not exists guides_cohort_game_source_unique on public.guides(cohort,game_id,source_url);

alter table private.guide_crawl_settings enable row level security;
alter table private.guide_crawl_runs enable row level security;
alter table private.guide_candidates enable row level security;
alter table private.guide_reviews enable row level security;
revoke all on private.guide_crawl_settings,private.guide_crawl_runs,private.guide_candidates,private.guide_reviews from public,anon,authenticated;
grant select,insert,update,delete on private.guide_crawl_settings,private.guide_crawl_runs,private.guide_candidates,private.guide_reviews to service_role;
-- pg_net queues plaintext request headers briefly. Clients must not read them.
revoke all on net.http_request_queue from public,anon,authenticated;

-- Generate 256 bits in Postgres, place the token only in Vault, and retain its
-- SHA-256 digest in configuration. No token is emitted in a result or notice.
do $$
declare crawl_token text;
begin
 select decrypted_secret into crawl_token from vault.decrypted_secrets where name='fltiya_guide_crawl_token';
 if crawl_token is null then
  crawl_token := encode(extensions.gen_random_bytes(32),'hex');
  perform vault.create_secret(crawl_token,'fltiya_guide_crawl_token','FL-Tiya private scheduled guide discovery');
 end if;
 if crawl_token !~ '^[a-f0-9]{64}$' then raise exception 'invalid_guide_crawl_secret'; end if;
 insert into private.guide_crawl_settings(source_key,game_id,cohort,enabled,token_hash)
 values('steam_zzz_official_rss','zenless-zone-zero','development',false,encode(extensions.digest(crawl_token,'sha256'),'hex'));
end $$;

-- Both RPCs are deliberate service-only entry points to an unexposed schema.
-- Lock the single source row to serialize claims and enforce an atomic cooldown.
create function public.claim_guide_crawl(p_token_hash text) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare cfg private.guide_crawl_settings; run_id uuid;
begin
 select * into cfg from private.guide_crawl_settings where source_key='steam_zzz_official_rss' for update;
 if not found or p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' or p_token_hash<>cfg.token_hash then
  return jsonb_build_object('status','unauthorized');
 end if;
 if not cfg.enabled then return jsonb_build_object('status','disabled'); end if;
 if cfg.next_allowed_at>clock_timestamp() or exists(
  select 1 from private.guide_crawl_runs where source_key=cfg.source_key and state='running' and started_at>clock_timestamp()-interval '5 minutes'
 ) then return jsonb_build_object('status','rate_limited'); end if;
 update private.guide_crawl_runs set state='failed',finished_at=clock_timestamp(),errors='[{"code":"lease_expired"}]'::jsonb
 where source_key=cfg.source_key and state='running';
 insert into private.guide_crawl_runs(source_key,cohort,game_id) values(cfg.source_key,cfg.cohort,cfg.game_id) returning id into run_id;
 update private.guide_crawl_settings set next_allowed_at=clock_timestamp()+interval '5 minutes' where source_key=cfg.source_key;
 return jsonb_build_object('status','claimed','run_id',run_id);
end $$;

create function public.finish_guide_crawl(p_run_id uuid,p_candidates jsonb,p_errors jsonb) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare run private.guide_crawl_runs; candidate jsonb; pub_date timestamptz; added integer:=0; affected integer;
 safe_errors jsonb:='[]'::jsonb; error_code text;
begin
 if jsonb_typeof(p_candidates) is distinct from 'array' or jsonb_array_length(p_candidates)>20 or pg_column_size(p_candidates)>65536
  or jsonb_typeof(p_errors) is distinct from 'array' or jsonb_array_length(p_errors)>20 or pg_column_size(p_errors)>8192 then
  raise exception using errcode='22023',message='invalid_guide_crawl_payload';
 end if;
 select * into run from private.guide_crawl_runs where id=p_run_id for update;
 if not found then raise exception using errcode='22023',message='unknown_guide_crawl_run'; end if;
 if run.state<>'running' then return jsonb_build_object('status','already_finished','inserted_count',run.inserted_count); end if;
 if run.started_at<clock_timestamp()-interval '5 minutes' then
  update private.guide_crawl_runs set state='failed',finished_at=clock_timestamp(),errors='[{"code":"lease_expired"}]'::jsonb where id=run.id;
  return jsonb_build_object('status','failed','inserted_count',0);
 end if;
 -- Persist only allowlisted error codes, never exception messages or headers.
 for candidate in select value from jsonb_array_elements(p_errors) loop
  error_code:=candidate->>'code';
  if error_code is null or error_code not in ('source_too_large','source_invalid_encoding','source_timeout','source_http_error','source_redirect','source_invalid_xml','robots_disallowed','source_unavailable') then error_code:='source_unavailable'; end if;
  safe_errors:=safe_errors||jsonb_build_array(jsonb_build_object('code',error_code));
 end loop;
 if jsonb_array_length(safe_errors)=0 then
  for candidate in select value from jsonb_array_elements(p_candidates) loop
   if jsonb_typeof(candidate) is distinct from 'object' or candidate->>'source_key' is distinct from run.source_key
    or jsonb_typeof(candidate->'title') is distinct from 'string' or char_length(btrim(candidate->>'title')) not between 1 and 200
    or candidate->>'title' ~ '[[:cntrl:]<>]'
    or jsonb_typeof(candidate->'source_url') is distinct from 'string'
    or candidate->>'source_url' !~ '^https://steamcommunity[.]com/games/4162040/announcements/detail/[0-9]{1,24}$'
    or candidate->>'source_guid' is distinct from candidate->>'source_url'
    or candidate->>'content_kind' is null or candidate->>'content_kind' not in ('guide','reference','news','support')
    or jsonb_typeof(candidate->'source_published_at') is distinct from 'string'
    or candidate->>'source_published_at' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,3})?Z$'
    or (candidate->'source_author' is not null and candidate->'source_author'<>'null'::jsonb and
     (jsonb_typeof(candidate->'source_author') is distinct from 'string' or char_length(btrim(candidate->>'source_author')) not between 1 and 120 or candidate->>'source_author' ~ '[[:cntrl:]<>]'))
   then continue; end if;
   begin pub_date:=(candidate->>'source_published_at')::timestamptz;
   exception when invalid_datetime_format or datetime_field_overflow then continue; end;
   if pub_date<'2000-01-01 00:00:00+00'::timestamptz or pub_date>='2101-01-01 00:00:00+00'::timestamptz then continue; end if;
   -- Existing reviewed publications are never overwritten or republished.
   if exists(select 1 from public.guides g where g.cohort=run.cohort and g.game_id=run.game_id and g.source_url=candidate->>'source_url') then continue; end if;
   insert into private.guide_candidates(source_key,run_id,cohort,game_id,source_guid,source_url,title,source_author,source_published_at,content_kind,review_status)
   values(run.source_key,run.id,run.cohort,run.game_id,candidate->>'source_guid',candidate->>'source_url',btrim(candidate->>'title'),
    candidate->>'source_author',pub_date,candidate->>'content_kind','pending') on conflict do nothing;
   get diagnostics affected=row_count;added:=added+affected;
  end loop;
 end if;
 update private.guide_crawl_runs set state=case when jsonb_array_length(safe_errors)=0 then 'completed' else 'failed' end,
  inserted_count=added,errors=safe_errors,finished_at=clock_timestamp() where id=run.id;
 return jsonb_build_object('status',case when jsonb_array_length(safe_errors)=0 then 'completed' else 'failed' end,'inserted_count',added);
end $$;

-- No key is embedded in a cron command; only this private function can decrypt it.
create function private.enqueue_guide_discovery() returns bigint
language plpgsql security definer set search_path=''
as $$
declare crawl_token text; expected_hash text; request_id bigint;
begin
 select token_hash into expected_hash from private.guide_crawl_settings where source_key='steam_zzz_official_rss' and enabled;
 if expected_hash is null then return null; end if;
 select decrypted_secret into crawl_token from vault.decrypted_secrets where name='fltiya_guide_crawl_token';
 if crawl_token is null or crawl_token !~ '^[a-f0-9]{64}$' or encode(extensions.digest(crawl_token,'sha256'),'hex')<>expected_hash then
  raise exception 'guide_crawl_secret_unavailable';
 end if;
 select net.http_post(
  url:='https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/collect-guide-candidates',
  headers:=jsonb_build_object('Content-Type','application/json','x-fltiya-crawl-token',crawl_token),
  body:='{}'::jsonb,timeout_milliseconds:=60000
 ) into request_id;
 return request_id;
end $$;
revoke all on function public.claim_guide_crawl(text),public.finish_guide_crawl(uuid,jsonb,jsonb),private.enqueue_guide_discovery() from public,anon,authenticated;
grant execute on function public.claim_guide_crawl(text),public.finish_guide_crawl(uuid,jsonb,jsonb),private.enqueue_guide_discovery() to service_role;
comment on table private.guide_candidates is 'Unpublished metadata only. Discovery never inserts or changes public.guides.';
comment on table private.guide_reviews is 'Server-only editorial decision record for manually reviewed guides or crawl candidates.';
-- Existing published, same-cohort guide SELECT policy is deliberately unchanged.
commit;
