-- Correct the just-installed, unused non-relocatable pg_net extension.
-- No CASCADE: existing dependencies or queued requests prevent this change.
begin;
do $$
begin
 if exists(select 1 from net.http_request_queue) or exists(select 1 from net._http_response)
    or exists(select 1 from cron.job) then
  raise exception 'pg_net must still be unused before schema correction';
 end if;
end $$;
drop extension pg_net;
create extension pg_net with schema extensions;
revoke all on net.http_request_queue from public,anon,authenticated;
commit;
