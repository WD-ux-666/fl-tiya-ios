-- People/creator clips are content, not fabricated games. Existing game rows,
-- grants, moderation status and cohort/Storage policies retain their meaning.
begin;
alter table public.video_posts alter column game_id drop not null;
alter table public.video_posts add column content_category text not null default 'gaming';
alter table public.video_posts add constraint video_posts_category_game_check check (
 (content_category='gaming' and game_id is not null)
 or (content_category='lifestyle' and game_id is null)
);
grant insert (content_category) on public.video_posts to authenticated;
comment on column public.video_posts.content_category is 'gaming requires a real game FK; lifestyle creator clips have no game. Moderation and ownership apply to both.';
comment on column public.video_posts.game_id is 'Real game reference for gaming posts only; NULL for lifestyle. Never create a fake game to label people clips.';
commit;
