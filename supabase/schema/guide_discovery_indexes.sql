begin;
create index guide_candidates_game_idx on private.guide_candidates(game_id);
create index guide_candidates_run_idx on private.guide_candidates(run_id);
create index guide_candidates_source_idx on private.guide_candidates(source_key);
create index guide_crawl_runs_game_idx on private.guide_crawl_runs(game_id);
create index guide_crawl_settings_game_idx on private.guide_crawl_settings(game_id);
commit;
