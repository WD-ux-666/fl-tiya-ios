-- Let one-tap accounts see only explicitly curated example comments on readable clips.
-- Content is opted in separately from the schema. Private account details stay private.
begin;

create table private.curated_clip_comment_credits (
    comment_id uuid primary key references private.clip_comments(id) on delete cascade,
    display_name text not null check (char_length(btrim(display_name)) between 1 and 80)
);
alter table private.curated_clip_comment_credits enable row level security;
revoke all on private.curated_clip_comment_credits from public,anon,authenticated,service_role;

-- Only used inside trusted RPCs after they have verified access to the clip.
-- A visible development clip alone does not make its other comments public.
create function private.can_read_clip_comment(c private.clip_comments, experience_clip boolean) returns boolean
language sql stable security invoker set search_path='' as $$
    select not private.viewer_report_hides('comment',c.id)
        and (private.can_view_user(c.author_id)
            or (experience_clip and c.status='approved'
                and exists(select 1 from private.curated_clip_comment_credits credit where credit.comment_id=c.id)
                and exists(select 1 from private.accounts a
                    where a.user_id=c.author_id and a.cohort='development' and a.state='active')
                and not private.viewer_report_hides('conversation',c.author_id)
                and not exists(select 1 from public.blocks b
                    where (b.owner_id=auth.uid() and b.blocked_id=c.author_id)
                       or (b.owner_id=c.author_id and b.blocked_id=auth.uid()))));
$$;
revoke all on function private.can_read_clip_comment(private.clip_comments,boolean)
from public,anon,authenticated,service_role;

create or replace function private.clip_comments(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); result jsonb; experience_clip boolean;
begin
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    experience_clip := private.experience_can_read_post(target_clip_id);
    select coalesce(jsonb_agg(
        case when credit.comment_id is not null and experience_clip and not private.can_view_user(c.author_id)
            then jsonb_build_object('id',c.id,'clip_id',c.clip_id,'body',c.body,
                'status',c.status,'created_at',c.created_at,'is_sample',true,
                'author',jsonb_build_object('id',c.id,'handle','sample',
                    'display_name',credit.display_name || ' · Sample','bio','','avatar_path',null))
            else private.clip_comment_json(c::private.clip_comments)
        end order by c.created_at desc,c.id desc
    ),'[]'::jsonb)
    into result from (
        select c.* from private.clip_comments c where c.clip_id=target_clip_id
          and (c.status='approved' or (c.author_id=actor and c.status='pending'))
          and private.can_read_clip_comment(c,experience_clip)
        order by c.created_at desc,c.id desc limit 100
    ) c left join private.curated_clip_comment_credits credit on credit.comment_id=c.id;
    return result;
end;
$$;

create or replace function private.clip_social_state(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); owner_profile jsonb; owner_id uuid; experience_clip boolean;
begin
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    experience_clip := private.experience_can_read_post(target_clip_id);
    select jsonb_build_object('id',p.id,'handle',p.handle,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path),p.id
    into owner_profile,owner_id from public.video_posts v join public.profiles p on p.id=v.owner_id
    where v.id=target_clip_id and private.can_view_user(p.id);
    return jsonb_build_object('uploader',owner_profile,
        'is_following',exists(select 1 from private.player_follows where follower_id=actor and followed_id=owner_id),
        'is_liked',exists(select 1 from private.clip_likes where clip_id=target_clip_id and user_id=actor),
        'like_count',(select count(*) from private.clip_likes where clip_id=target_clip_id and private.can_view_user(user_id)),
        'comment_count',(select count(*) from private.clip_comments c where c.clip_id=target_clip_id and c.status='approved'
            and private.can_read_clip_comment(c,experience_clip)));
end;
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
          and private.can_interact_with_clip(c.clip_id)
          and private.can_read_clip_comment(c,private.experience_can_read_post(c.clip_id));
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
