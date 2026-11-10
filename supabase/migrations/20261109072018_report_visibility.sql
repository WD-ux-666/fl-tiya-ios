-- A report hides its target for its author without taking it down for other players.
begin;

create table private.content_report_hides (
    viewer_id uuid not null references public.profiles(id) on delete cascade,
    target_type text not null check (target_type in ('video','comment','conversation')),
    target_id uuid not null,
    primary key (viewer_id,target_type,target_id)
);
alter table private.content_report_hides enable row level security;
revoke all on private.content_report_hides from public,anon,authenticated,service_role;
comment on table private.content_report_hides is
    'Personal report exclusions. No target or review-queue foreign key: removing a report or its subject does not undo hiding. Deleting the viewer removes their exclusions.';

create function private.remember_report_hide() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    insert into private.content_report_hides(viewer_id,target_type,target_id)
    values(new.reporter_id,new.target_type,new.target_id)
    on conflict do nothing;
    return null;
end;
$$;
revoke all on function private.remember_report_hide() from public,anon,authenticated,service_role;
-- Creating the trigger takes a write-conflicting lock on the queue before
-- backfill. Both pre-existing and concurrently filed reports acquire a hide.
create trigger fltiya_remember_report_hide after insert on private.content_reports
for each row execute function private.remember_report_hide();
insert into private.content_report_hides(viewer_id,target_type,target_id)
select reporter_id,target_type,target_id from private.content_reports
on conflict do nothing;

-- The three-argument helper is only for trusted functions with a verified
-- actor, including the server-side call service. RLS gets a current-viewer helper.
create function private.report_hides_target(viewer uuid, target_kind text, target uuid) returns boolean
language sql stable security invoker set search_path='' as $$
    select exists(select 1 from private.content_report_hides h
        where h.viewer_id=$1 and h.target_type=$2 and h.target_id=$3);
$$;
create function private.viewer_report_hides(target_kind text, target uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.report_hides_target(auth.uid(),$1,$2);
$$;
revoke all on function private.report_hides_target(uuid,text,uuid), private.viewer_report_hides(text,uuid)
from public,anon,authenticated,service_role;
grant execute on function private.viewer_report_hides(text,uuid) to authenticated;

create or replace function private.can_view_user(target_user_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_active() and private.same_cohort_target(target_user_id)
       and not private.viewer_report_hides('conversation',target_user_id)
       and not exists (
           select 1 from public.blocks b
           where (b.owner_id=auth.uid() and b.blocked_id=target_user_id)
              or (b.owner_id=target_user_id and b.blocked_id=auth.uid())
       );
$$;

-- The editorial exception bypasses the cohort check for media only. It must
-- still honor existing blocks and both kinds of personal video exclusions.
create or replace function private.experience_can_read_post(target_post uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_experience() and exists (
        select 1 from public.video_posts v
        join private.accounts a on a.user_id=v.owner_id
        where v.id=target_post and v.status='approved' and a.cohort='development' and a.state='active'
          and not private.viewer_report_hides('video',v.id)
          and not private.viewer_report_hides('conversation',v.owner_id)
          and not exists(select 1 from public.blocks b
              where (b.owner_id=auth.uid() and b.blocked_id=v.owner_id)
                 or (b.owner_id=v.owner_id and b.blocked_id=auth.uid()))
    );
$$;

-- Storage video/thumbnail reads already require a readable video_posts row.
-- Leave their authentication, operation, and owner checks intact.
create policy video_posts_report_visibility on public.video_posts as restrictive for select to authenticated
using (not private.viewer_report_hides('video',id));

create or replace function private.can_interact_with_clip(target_clip_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_active() and exists (
        select 1 from public.video_posts v join private.accounts a on a.user_id=v.owner_id
        where v.id=target_clip_id and v.status='approved' and a.state='active'
          and not private.viewer_report_hides('video',v.id)
          and (private.can_view_user(v.owner_id) or private.experience_can_read_post(v.id))
    );
$$;

create or replace function private.clip_comments(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); result jsonb;
begin
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    select coalesce(jsonb_agg(private.clip_comment_json(c::private.clip_comments) order by c.created_at desc,c.id desc),'[]'::jsonb)
    into result from (
        select c.* from private.clip_comments c where c.clip_id=target_clip_id
          and (c.status='approved' or (c.author_id=actor and c.status='pending'))
          and private.can_view_user(c.author_id)
          and not private.viewer_report_hides('comment',c.id)
        order by c.created_at desc,c.id desc limit 100
    ) c;
    return result;
end;
$$;

create or replace function private.clip_social_state(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); owner_profile jsonb; owner_id uuid;
begin
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    select jsonb_build_object('id',p.id,'handle',p.handle,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path),p.id
    into owner_profile,owner_id from public.video_posts v join public.profiles p on p.id=v.owner_id
    where v.id=target_clip_id and private.can_view_user(p.id);
    return jsonb_build_object('uploader',owner_profile,
        'is_following',exists(select 1 from private.player_follows where follower_id=actor and followed_id=owner_id),
        'is_liked',exists(select 1 from private.clip_likes where clip_id=target_clip_id and user_id=actor),
        'like_count',(select count(*) from private.clip_likes where clip_id=target_clip_id and private.can_view_user(user_id)),
        'comment_count',(select count(*) from private.clip_comments where clip_id=target_clip_id and status='approved'
            and private.can_view_user(author_id) and not private.viewer_report_hides('comment',id)));
end;
$$;

-- A player can keep their side of the history, but cannot make the reporting
-- player's device ring. Existing authorization checks/sweep handle open calls.
create or replace function private.call_pair_allowed(first_user uuid,second_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.call_user_eligible(first_user) and private.call_user_eligible(second_user)
      and exists(select 1 from private.accounts a join private.accounts b on b.cohort=a.cohort
          where a.user_id=first_user and b.user_id=second_user)
      and exists(select 1 from public.friendships f where f.user_low=least(first_user,second_user) and f.user_high=greatest(first_user,second_user))
      and not exists(select 1 from public.blocks b
          where (b.owner_id=first_user and b.blocked_id=second_user) or (b.owner_id=second_user and b.blocked_id=first_user))
      and not private.report_hides_target(first_user,'conversation',second_user)
      and not private.report_hides_target(second_user,'conversation',first_user);
$$;

create or replace function private.call_json(c private.calls,actor uuid) returns jsonb
language sql stable security definer set search_path='' as $$
    select jsonb_build_object('id',c.id,'caller_id',c.caller_id,'callee_id',c.callee_id,'kind',c.kind,'status',c.status,
        'created_at',c.created_at,'answered_at',c.answered_at,'ended_at',c.ended_at,'expires_at',c.expires_at,'ended_reason',c.ended_reason,
        'peer_id',p.id,'peer_display_name',p.display_name,'peer_avatar_path',p.avatar_path)
    from public.profiles p where p.id=case when c.caller_id=actor then c.callee_id else c.caller_id end
      and not private.report_hides_target(actor,'conversation',p.id);
$$;

create or replace function private.submit_content_report(
    p_target_type text, p_target_id uuid, p_reason text, p_details text
) returns boolean
language plpgsql volatile security definer set search_path='' as $$
declare
    actor uuid:=private.require_actor();
    subject uuid;
    details_value text:=nullif(btrim(p_details,E' \t\r\n'),'');
begin
    if p_target_type is null or p_target_type not in ('video','comment','conversation')
        or p_target_id is null or p_reason is null
        or p_reason not in ('spam','harassment','inappropriate','other')
        or char_length(details_value)>500 then
        raise exception using errcode='22023',message='invalid_report';
    end if;
    -- A retry of the viewer's own known key is allowed even if the target is
    -- now hidden, deleted, blocked, or no longer in the review queue.
    if private.report_hides_target(actor,p_target_type,p_target_id) then
        return false;
    end if;
    case p_target_type
    when 'video' then
        select v.owner_id into subject from public.video_posts v
        where v.id=p_target_id and private.can_interact_with_clip(v.id);
    when 'comment' then
        select c.author_id into subject from private.clip_comments c
        where c.id=p_target_id and c.status='approved'
          and private.can_interact_with_clip(c.clip_id) and private.can_view_user(c.author_id)
          and not private.viewer_report_hides('comment',c.id);
    when 'conversation' then
        if p_target_id<>actor and private.can_view_user(p_target_id) then
            -- Hold the peer through insert before taking the pair lock used
            -- by blocks, call creation, and account-deletion cleanup.
            perform 1 from auth.users where id=p_target_id for key share;
            perform private.lock_pair(actor,p_target_id);
            select p.id into subject from public.profiles p
            where p.id=p_target_id and private.can_view_user(p.id);
        end if;
    end case;
    if subject is null or subject=actor then
        -- Another report may have committed while visibility was checked.
        if private.report_hides_target(actor,p_target_type,p_target_id) then
            return false;
        end if;
        raise exception using errcode='42501',message='report_target_unavailable';
    end if;
    -- The personal key is also the durable deduplication authority. Claim
    -- it first so even concurrent queue maintenance cannot re-open a report.
    insert into private.content_report_hides(viewer_id,target_type,target_id)
    values(actor,p_target_type,p_target_id) on conflict do nothing;
    if not found then return false; end if;
    insert into private.content_reports(reporter_id,subject_id,target_type,target_id,reason,details)
    values(actor,subject,p_target_type,p_target_id,p_reason,details_value)
    on conflict (reporter_id,target_type,target_id) do nothing;
    return found;
end;
$$;

commit;
