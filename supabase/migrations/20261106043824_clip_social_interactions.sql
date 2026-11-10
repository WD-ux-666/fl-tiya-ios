-- Real short-video interactions. Private tables are never exposed directly.
-- A comment is pending until a trusted reviewer approves it. An author can
-- read/delete their own pending comment; the shared count includes approved
-- comments only. Counts and comment authors never cross social cohorts.
begin;

create table private.clip_likes (
    clip_id uuid not null references public.video_posts(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (clip_id, user_id)
);
create index clip_likes_user_idx on private.clip_likes(user_id, clip_id);

create table private.clip_comments (
    id uuid primary key,
    clip_id uuid not null references public.video_posts(id) on delete cascade,
    author_id uuid not null references public.profiles(id) on delete cascade,
    body text not null,
    status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'deleted')),
    created_at timestamptz not null default now(),
    approved_at timestamptz,
    check ((status='deleted' and body='') or (status<>'deleted' and char_length(btrim(body,E' \t\r\n')) between 1 and 1000)),
    check (status <> 'approved' or approved_at is not null)
);
create index clip_comments_post_status_time_idx on private.clip_comments(clip_id, status, created_at desc, id desc);
create index clip_comments_author_idx on private.clip_comments(author_id, clip_id);
alter table private.clip_likes enable row level security;
alter table private.clip_comments enable row level security;
revoke all on private.clip_likes, private.clip_comments from public, anon, authenticated;
grant all on private.clip_likes, private.clip_comments to service_role;

create function private.can_interact_with_clip(target_clip_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select private.actor_is_active() and exists (
        select 1 from public.video_posts v join private.accounts a on a.user_id=v.owner_id
        where v.id=target_clip_id and v.status='approved' and a.state='active'
          and (private.can_view_user(v.owner_id) or private.experience_can_read_post(v.id))
          and not exists (select 1 from public.blocks b
              where (b.owner_id=auth.uid() and b.blocked_id=v.owner_id)
                 or (b.blocked_id=auth.uid() and b.owner_id=v.owner_id))
    );
$$;

create function private.clip_comment_json(comment_row private.clip_comments) returns jsonb
language sql stable security definer set search_path='' as $$
    select jsonb_build_object('id',comment_row.id,'clip_id',comment_row.clip_id,
        'body',comment_row.body,'status',comment_row.status,'created_at',comment_row.created_at,
        'author',jsonb_build_object('id',p.id,'handle',p.handle,'display_name',p.display_name,
            'bio',p.bio,'avatar_path',p.avatar_path))
    from public.profiles p where p.id=comment_row.author_id;
$$;

create function private.clip_social_state(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); owner_profile jsonb;
begin
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    -- Reading approved development media does not expose development profiles
    -- to device accounts. Nullable uploader is rendered as Imported clip.
    select jsonb_build_object('id',p.id,'handle',p.handle,'display_name',p.display_name,
        'bio',p.bio,'avatar_path',p.avatar_path) into owner_profile
    from public.video_posts v join public.profiles p on p.id=v.owner_id
    where v.id=target_clip_id and private.can_view_user(p.id);
    return jsonb_build_object(
        'uploader',owner_profile,
        'is_liked',exists(select 1 from private.clip_likes l where l.clip_id=target_clip_id and l.user_id=actor),
        'like_count',(select count(*) from private.clip_likes l
            where l.clip_id=target_clip_id and private.can_view_user(l.user_id)),
        'comment_count',(select count(*) from private.clip_comments c
            where c.clip_id=target_clip_id and c.status='approved' and private.can_view_user(c.author_id))
    );
end;
$$;

create function private.set_clip_liked(target_clip_id uuid, liked boolean) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); clip_owner uuid;
begin
    if liked is null then raise exception using errcode='22023',message='liked_required';end if;
    select v.owner_id into clip_owner from public.video_posts v where v.id=target_clip_id;
    if not found then raise exception using errcode='42501',message='clip_unavailable';end if;
    perform private.lock_pair(actor,clip_owner);
    -- Prevent review/deletion from racing the approval check and interaction.
    perform 1 from public.video_posts v where v.id=target_clip_id for share;
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    if liked then
        insert into private.clip_likes(clip_id,user_id) values(target_clip_id,actor) on conflict do nothing;
    else
        delete from private.clip_likes l where l.clip_id=target_clip_id and l.user_id=actor;
    end if;
    return private.clip_social_state(target_clip_id);
end;
$$;

create function private.clip_comments(target_clip_id uuid) returns jsonb
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
        order by c.created_at desc,c.id desc limit 100
    ) c;
    return result;
end;
$$;

create function private.add_clip_comment(target_clip_id uuid, comment_id uuid, comment_body text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); clip_owner uuid; normalized_body text:=btrim(comment_body,E' \t\r\n');
    result private.clip_comments;
begin
    if comment_id is null or normalized_body is null or char_length(normalized_body) not between 1 and 1000 then
        raise exception using errcode='22023',message='invalid_comment';
    end if;
    select v.owner_id into clip_owner from public.video_posts v where v.id=target_clip_id;
    if not found then raise exception using errcode='42501',message='clip_unavailable';end if;
    perform private.lock_pair(actor,clip_owner);
    perform 1 from public.video_posts v where v.id=target_clip_id for share;
    if not private.can_interact_with_clip(target_clip_id) then
        raise exception using errcode='42501',message='clip_unavailable';
    end if;
    -- Serializes same UUID retries even if a request supplies a different post.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('clip-comment:'||comment_id::text,0));
    select * into result from private.clip_comments c where c.id=comment_id for update;
    if found then
        if result.author_id<>actor or result.clip_id<>target_clip_id then
            raise exception using errcode='22023',message='comment_id_conflict';
        end if;
        if result.status='deleted' then
            raise exception using errcode='22023',message='comment_deleted';
        end if;
        if result.body<>normalized_body then
            raise exception using errcode='22023',message='comment_id_conflict';
        end if;
        -- A rejected retry must not look like a newly accepted pending comment.
        if result.status='rejected' then
            raise exception using errcode='22023',message='comment_rejected';
        end if;
        return private.clip_comment_json(result);
    end if;
    insert into private.clip_comments(id,clip_id,author_id,body)
        values(comment_id,target_clip_id,actor,normalized_body) returning * into result;
    return private.clip_comment_json(result);
end;
$$;

create function private.delete_clip_comment(comment_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();
begin
    -- Own rows only; uniform success for missing/foreign UUIDs avoids an oracle.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('clip-comment:'||comment_id::text,0));
    -- Erase the text, retaining only a deduplication tombstone so an uncertain
    -- send retry cannot resurrect a comment after its author deleted it.
    update private.clip_comments c set status='deleted',body='',approved_at=null
        where c.id=comment_id and c.author_id=actor and c.status<>'deleted';
end;
$$;

create function public.clip_social_state(target_clip_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.clip_social_state($1); $$;
create function public.set_clip_liked(target_clip_id uuid, liked boolean) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.set_clip_liked($1,$2); $$;
create function public.clip_comments(target_clip_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.clip_comments($1); $$;
create function public.add_clip_comment(target_clip_id uuid, comment_id uuid, comment_body text) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.add_clip_comment($1,$2,$3); $$;
create function public.delete_clip_comment(comment_id uuid) returns void
language sql volatile security invoker set search_path='' as $$ select private.delete_clip_comment($1); $$;

revoke all on function private.can_interact_with_clip(uuid),private.clip_comment_json(private.clip_comments),
    private.clip_social_state(uuid),private.set_clip_liked(uuid,boolean),private.clip_comments(uuid),
    private.add_clip_comment(uuid,uuid,text),private.delete_clip_comment(uuid),
    public.clip_social_state(uuid),public.set_clip_liked(uuid,boolean),public.clip_comments(uuid),
    public.add_clip_comment(uuid,uuid,text),public.delete_clip_comment(uuid) from public,anon,authenticated;
grant execute on function private.clip_social_state(uuid),private.set_clip_liked(uuid,boolean),private.clip_comments(uuid),
    private.add_clip_comment(uuid,uuid,text),private.delete_clip_comment(uuid),
    public.clip_social_state(uuid),public.set_clip_liked(uuid,boolean),public.clip_comments(uuid),
    public.add_clip_comment(uuid,uuid,text),public.delete_clip_comment(uuid) to authenticated;

comment on table private.clip_comments is 'User comments require trusted review. Approved-only aggregate counts; same-cohort authors and bidirectional blocks are enforced by the RPCs. Own pending rows are visible only to their author.';
comment on table private.clip_likes is 'One real like per account/post. No client table privileges; use idempotent set_clip_liked.';
commit;
