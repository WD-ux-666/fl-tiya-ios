begin;

-- Approved sample identity snapshots; no access to the source profiles or credentials.
create table private.curated_community_players (
    id uuid primary key references public.profiles(id) on delete cascade,
    game_id text not null references public.games(id),
    handle text not null,
    display_name text not null,
    bio text not null,
    avatar_path text not null unique check (
        split_part(avatar_path,'/',1)=id::text and avatar_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|jpg|jpeg)$'
    )
);
create index curated_community_players_game_idx on private.curated_community_players(game_id);
create table private.curated_community_requests (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references private.accounts(user_id) on delete cascade,
    player_id uuid not null references private.curated_community_players(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(sender_id,player_id)
);
create index curated_community_requests_player_idx on private.curated_community_requests(player_id);
alter table private.curated_community_players enable row level security;
alter table private.curated_community_requests enable row level security;
revoke all on private.curated_community_players,private.curated_community_requests
from public,anon,authenticated,service_role;

-- Identity access for the sample feature only, independent of development login reservations.
create function private.is_community_sample(target_user_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
    select private.actor_is_experience() and exists (
        select 1 from private.curated_community_players p
        join private.accounts a on a.user_id=p.id and a.cohort='development' and a.state='active'
        where p.id=target_user_id
    );
$$;
create function private.can_see_community_sample(target_user_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
    select private.is_community_sample(target_user_id)
       and not private.viewer_report_hides('conversation',target_user_id)
       and not exists (select 1 from public.blocks b
           where (b.owner_id=auth.uid() and b.blocked_id=target_user_id)
              or (b.owner_id=target_user_id and b.blocked_id=auth.uid()));
$$;
create function private.can_read_community_sample_avatar(object_name text) returns boolean
language sql stable security definer set search_path='' as $$
    select exists (
        select 1 from private.curated_community_players p
        where p.avatar_path=object_name and private.can_see_community_sample(p.id)
    );
$$;
revoke all on function private.is_community_sample(uuid),private.can_see_community_sample(uuid),
    private.can_read_community_sample_avatar(text) from public,anon,authenticated,service_role;
grant execute on function private.can_read_community_sample_avatar(text) to authenticated;

create policy fltiya_curated_community_avatar_read on storage.objects for select to authenticated using (
    bucket_id='avatars'
    and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info'])
    and private.can_read_community_sample_avatar(name)
);

create function private.community_players_with_samples(target_game_id text, search_query text)
returns table(id uuid, handle text, display_name text, bio text, avatar_path text, relationship text,
    request_id uuid, is_sample boolean, sample_game_id text)
language sql stable security definer set search_path='' as $$
    select * from (
        select p.*,false as is_sample,null::text as sample_game_id
        from private.discover_community_players(target_game_id,search_query) p
        union all
        select p.id,p.handle,p.display_name,p.bio,p.avatar_path,
            case when r.id is null then 'none' else 'outgoing' end,r.id,true,p.game_id
        from private.curated_community_players p
        left join private.curated_community_requests r on r.player_id=p.id and r.sender_id=auth.uid()
        where private.can_see_community_sample(p.id)
          and (target_game_id is null or p.game_id=target_game_id)
          and (pg_catalog.strpos(pg_catalog.lower(p.handle),pg_catalog.lower(btrim(coalesce(search_query,''))))>0
            or pg_catalog.strpos(pg_catalog.lower(p.display_name),pg_catalog.lower(btrim(coalesce(search_query,''))))>0)
    ) as players
    order by players.is_sample,players.handle,players.id limit 50;
$$;
drop function public.discover_community_players(text,text);
create function public.discover_community_players(target_game_id text default null, search_query text default '')
returns table(id uuid, handle text, display_name text, bio text, avatar_path text, relationship text,
    request_id uuid, is_sample boolean, sample_game_id text)
language sql stable security invoker set search_path='' as $$
    select * from private.community_players_with_samples(target_game_id,search_query);
$$;
revoke all on function private.community_players_with_samples(text,text),
    public.discover_community_players(text,text) from public,anon,authenticated,service_role;
grant execute on function private.community_players_with_samples(text,text),
    public.discover_community_players(text,text) to authenticated;

create or replace function private.send_friend_request(target_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
    actor uuid := private.require_actor();
    request_row public.friend_requests;
    sample_request private.curated_community_requests;
begin
    if target_user_id is null or target_user_id=actor then
        raise exception using errcode='22023',message='invalid_target_user';
    end if;
    perform private.lock_pair(actor,target_user_id);
    if private.can_see_community_sample(target_user_id) then
        -- Pending UI test only. The fixture cannot receive or accept this request.
        insert into private.curated_community_requests(sender_id,player_id)
        values (actor,target_user_id) on conflict (sender_id,player_id) do nothing;
        select * into strict sample_request from private.curated_community_requests r
        where r.sender_id=actor and r.player_id=target_user_id;
        return jsonb_build_object('id',sample_request.id,'sender_id',actor,'recipient_id',target_user_id,
            'status','pending','created_at',sample_request.created_at,'is_sample',true);
    end if;
    if not private.can_view_user(target_user_id) then
        raise exception using errcode='42501',message='user_unavailable';
    end if;
    if exists (select 1 from public.friendships f where f.user_low=least(actor,target_user_id) and f.user_high=greatest(actor,target_user_id)) then
        raise exception using errcode='22023',message='already_friends';
    end if;
    select * into request_row from public.friend_requests r
    where least(r.sender_id,r.recipient_id)=least(actor,target_user_id)
      and greatest(r.sender_id,r.recipient_id)=greatest(actor,target_user_id)
      and r.status='pending' for update;
    if found then
        if request_row.sender_id<>actor then
            raise exception using errcode='22023',message='incoming_request_exists';
        end if;
        return to_jsonb(request_row);
    end if;
    insert into public.friend_requests(sender_id,recipient_id)
    values (actor,target_user_id) returning * into request_row;
    return to_jsonb(request_row);
end;
$$;

create or replace function private.block_user(target_user_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid := private.require_actor();
begin
    if target_user_id is null or target_user_id=actor then
        raise exception using errcode='22023',message='invalid_target_user';
    end if;
    perform private.lock_pair(actor,target_user_id);
    if private.is_community_sample(target_user_id) then
        insert into public.blocks(owner_id,blocked_id) values(actor,target_user_id) on conflict do nothing;
        delete from private.curated_community_requests r where r.sender_id=actor and r.player_id=target_user_id;
        return jsonb_build_object('blocked_user_id',target_user_id);
    end if;
    if not private.same_cohort_target(target_user_id) then
        raise exception using errcode='42501',message='user_unavailable';
    end if;
    insert into public.blocks(owner_id,blocked_id) values(actor,target_user_id) on conflict do nothing;
    update public.friend_requests r set status='cancelled' where r.status='pending'
        and least(r.sender_id,r.recipient_id)=least(actor,target_user_id)
        and greatest(r.sender_id,r.recipient_id)=greatest(actor,target_user_id);
    delete from public.friendships f where f.user_low=least(actor,target_user_id) and f.user_high=greatest(actor,target_user_id);
    return jsonb_build_object('blocked_user_id',target_user_id);
end;
$$;

create or replace function private.list_blocked_players(before_blocked_at timestamptz default null, before_user_id uuid default null)
returns table(id uuid,handle text,display_name text,blocked_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
    if (before_blocked_at is null) <> (before_user_id is null) then
        raise exception using errcode='22023',message='complete_block_cursor_required';
    end if;
    return query
    select player.id,player.handle,player.display_name,player.created_at
    from (
        select p.id,p.handle,p.display_name,b.created_at
        from public.blocks b
        join public.profiles p on p.id=b.blocked_id
        join private.accounts a on a.user_id=p.id and a.cohort=private.current_cohort()
        where private.actor_is_active() and b.owner_id=auth.uid()
        union all
        select p.id,p.handle,p.display_name,b.created_at
        from public.blocks b
        join private.curated_community_players p on p.id=b.blocked_id
        where b.owner_id=auth.uid() and private.is_community_sample(p.id)
    ) player
    where before_blocked_at is null or (player.created_at,player.id)<(before_blocked_at,before_user_id)
    order by player.created_at desc,player.id desc limit 50;
end;
$$;

notify pgrst, 'reload schema';
commit;
