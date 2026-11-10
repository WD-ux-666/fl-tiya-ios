-- Draft for root review/deployment. Community members are actual saved game-card
-- owners. Normal discovery never bypasses cohort or bidirectional block rules.
begin;

create function private.discover_community_players(target_game_id text default null, search_query text default '')
returns table(id uuid, handle text, display_name text, bio text, avatar_path text, relationship text, request_id uuid)
language sql stable security definer set search_path='' as $$
    select p.id, p.handle, p.display_name, p.bio, p.avatar_path,
        case when f.user_low is not null then 'friends'
             when r.recipient_id=auth.uid() then 'incoming'
             when r.sender_id=auth.uid() then 'outgoing'
             else 'none' end,
        case when f.user_low is null then r.id else null end
    from public.profiles p
    left join public.friendships f
        on f.user_low=least(auth.uid(),p.id) and f.user_high=greatest(auth.uid(),p.id)
    left join lateral (
        select fr.id,fr.sender_id,fr.recipient_id from public.friend_requests fr
        where fr.status='pending'
          and least(fr.sender_id,fr.recipient_id)=least(auth.uid(),p.id)
          and greatest(fr.sender_id,fr.recipient_id)=greatest(auth.uid(),p.id)
        order by fr.created_at desc,fr.id desc limit 1
    ) r on true
    where private.actor_is_active() and p.id<>auth.uid() and private.can_view_user(p.id)
      and (target_game_id is null or exists (
          select 1 from public.game_cards gc where gc.user_id=p.id and gc.game_id=target_game_id))
      and (pg_catalog.strpos(pg_catalog.lower(p.handle),pg_catalog.lower(btrim(coalesce(search_query,''))))>0
        or pg_catalog.strpos(pg_catalog.lower(p.display_name),pg_catalog.lower(btrim(coalesce(search_query,''))))>0)
    order by p.handle,p.id limit 50;
$$;
create function public.discover_community_players(target_game_id text default null, search_query text default '')
returns table(id uuid, handle text, display_name text, bio text, avatar_path text, relationship text, request_id uuid)
language sql stable security invoker set search_path='' as $$
    select * from private.discover_community_players(target_game_id,search_query);
$$;

-- A deliberately narrow exception to blocked profile invisibility: the block
-- owner can identify and unblock their own entries. It reveals no biography,
-- avatar media, game cards, requests or relationship records.
-- The legacy zero-argument overload must not coexist with defaulted cursor
-- arguments: PostgREST could otherwise resolve a no-argument RPC ambiguously.
create index if not exists blocks_owner_time_idx on public.blocks(owner_id,created_at desc,blocked_id desc);
drop function if exists public.list_blocked_players();
drop function if exists private.list_blocked_players();
create function private.list_blocked_players(before_blocked_at timestamptz default null, before_user_id uuid default null)
returns table(id uuid,handle text,display_name text,blocked_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
    if (before_blocked_at is null) <> (before_user_id is null) then
        raise exception using errcode='22023',message='complete_block_cursor_required';
    end if;
    return query
    select p.id,p.handle,p.display_name,b.created_at
    from public.blocks b
    join public.profiles p on p.id=b.blocked_id
    join private.accounts a on a.user_id=p.id and a.cohort=private.current_cohort()
    where private.actor_is_active() and b.owner_id=auth.uid()
      and (before_blocked_at is null or (b.created_at,p.id)<(before_blocked_at,before_user_id))
    order by b.created_at desc,p.id desc limit 50;
end;
$$;
create function public.list_blocked_players(before_blocked_at timestamptz default null, before_user_id uuid default null)
returns table(id uuid,handle text,display_name text,blocked_at timestamptz)
language sql stable security invoker set search_path='' as $$
    select * from private.list_blocked_players(before_blocked_at,before_user_id);
$$;

create function private.unblock_user(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();
begin
    if target_user_id is null or target_user_id=actor then
        raise exception using errcode='22023',message='invalid_target_user';
    end if;
    perform private.lock_pair(actor,target_user_id);
    delete from public.blocks b where b.owner_id=actor and b.blocked_id=target_user_id;
    -- Unblocking grants visibility only. It never recreates a friend request,
    -- friendship or call authorization. A reverse block remains in force.
    return jsonb_build_object('unblocked_user_id',target_user_id);
end;
$$;
create function public.unblock_user(target_user_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$ select private.unblock_user(target_user_id); $$;

revoke all on function private.discover_community_players(text,text),public.discover_community_players(text,text),
    private.list_blocked_players(timestamptz,uuid),public.list_blocked_players(timestamptz,uuid),private.unblock_user(uuid),public.unblock_user(uuid)
    from public,anon,authenticated;
grant execute on function private.discover_community_players(text,text),public.discover_community_players(text,text),
    private.list_blocked_players(timestamptz,uuid),public.list_blocked_players(timestamptz,uuid),private.unblock_user(uuid),public.unblock_user(uuid)
    to authenticated;
commit;
