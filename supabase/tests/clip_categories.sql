-- Category constraints only; synthetic rows always rolled back.
begin;
do $test$
declare actor uuid:=gen_random_uuid();gaming uuid:=gen_random_uuid();lifestyle uuid:=gen_random_uuid();
begin
 insert into auth.users(id,aud,role,is_anonymous) values(actor,'authenticated','authenticated',true);
 insert into public.video_posts(id,owner_id,game_id,video_path) values(gaming,actor,'minecraft',actor||'/'||gaming||'/video.mp4');
 assert (select content_category='gaming' from public.video_posts where id=gaming),'legacy insert defaults gaming';
 insert into public.video_posts(id,owner_id,game_id,content_category,video_path) values(lifestyle,actor,null,'lifestyle',actor||'/'||lifestyle||'/video.mp4');
 assert (select game_id is null and content_category='lifestyle' from public.video_posts where id=lifestyle),'lifestyle does not invent game';
 begin update public.video_posts set game_id='minecraft' where id=lifestyle;raise exception 'lifestyle accepted game';exception when check_violation then null;end;
 begin update public.video_posts set game_id=null where id=gaming;raise exception 'gaming accepted null game';exception when check_violation then null;end;
 begin update public.video_posts set content_category='unknown' where id=gaming;raise exception 'unknown category accepted';exception when check_violation then null;end;
 assert (select count(*) from public.games where id='lifestyle')=0,'no fake game created';
 assert has_column_privilege('authenticated','public.video_posts','content_category','insert'),'own pending upload can select valid category';
 assert not has_column_privilege('authenticated','public.video_posts','content_category','update'),'clients cannot reclassify existing posts';
end $test$;
rollback;
