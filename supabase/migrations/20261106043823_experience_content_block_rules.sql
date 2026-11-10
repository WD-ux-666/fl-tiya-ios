-- Keep the existing experience/editorial exception limited to active authors
-- and honor either-direction blocks in feed and private Storage reads.
begin;
create or replace function private.experience_can_read_post(target_post uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.actor_is_experience() and exists(
  select 1 from public.video_posts v
  join private.accounts a on a.user_id=v.owner_id
  where v.id=target_post and v.status='approved' and a.cohort='development' and a.state='active'
   and not exists(select 1 from public.blocks b
    where (b.owner_id=auth.uid() and b.blocked_id=v.owner_id)
       or (b.owner_id=v.owner_id and b.blocked_id=auth.uid()))
 );
$$;
commit;
