-- Apply only AFTER the reviewed schema and collect-guide-candidates deployment.
-- The Edge Function must have verify_jwt=false and its own token check enabled.
begin;
update private.guide_crawl_settings set enabled=true where source_key='steam_zzz_official_rss' and cohort='development';
select cron.schedule('fltiya-guide-discovery','0 */6 * * *',$job$select private.enqueue_guide_discovery();$job$) as job_id;
-- Initial discovery is queued, not published. Returns an opaque pg_net request ID.
select private.enqueue_guide_discovery() as request_id;
commit;
