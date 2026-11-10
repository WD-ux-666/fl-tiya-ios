-- Let one-tap accounts count explicitly reviewed sample likes on readable clips.
-- A sample like contributes to the total only; it never exposes the liker.
begin;

create table private.curated_clip_likes (
    clip_id uuid not null,
    user_id uuid not null,
    primary key (clip_id,user_id),
    foreign key (clip_id,user_id) references private.clip_likes(clip_id,user_id) on delete cascade
);
alter table private.curated_clip_likes enable row level security;
revoke all on private.curated_clip_likes from public,anon,authenticated,service_role;
comment on table private.curated_clip_likes is
    'Reviewed fictional likes eligible for an aggregate count on clips already readable to one-tap accounts. Removing a like revokes its opt-in.';

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
        'like_count',(select count(*) from private.clip_likes l where l.clip_id=target_clip_id
            and (private.can_view_user(l.user_id) or (experience_clip
                and exists(select 1 from private.curated_clip_likes opt_in
                    join private.accounts a on a.user_id=opt_in.user_id
                    where opt_in.clip_id=l.clip_id and opt_in.user_id=l.user_id
                        and a.cohort='development' and a.state='active')
                and not private.viewer_report_hides('conversation',l.user_id)
                and not exists(select 1 from public.blocks b
                    where (b.owner_id=actor and b.blocked_id=l.user_id)
                       or (b.owner_id=l.user_id and b.blocked_id=actor))))),
        'comment_count',(select count(*) from private.clip_comments c where c.clip_id=target_clip_id and c.status='approved'
            and private.can_read_clip_comment(c,experience_clip)));
end;
$$;

commit;
