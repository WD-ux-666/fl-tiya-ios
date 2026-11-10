-- FL-Tiya canonical schema source. Not a migration history entry.
-- Apply once to the authorized, empty FL-Tiya project after reviewing its state.
-- Requires hosted Supabase Auth/Storage and Storage operation-aware helpers.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
revoke create on schema public from public, anon, authenticated;
grant usage on schema public to authenticated, service_role;

-- New functions otherwise receive EXECUTE for PUBLIC by default.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;

create table private.accounts (
    user_id uuid primary key references auth.users(id) on delete cascade,
    state text not null default 'active' check (state in ('active', 'suspended', 'deleting')),
    created_at timestamptz not null default now()
);

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    handle text not null unique check (handle ~ '^[a-z0-9_]{3,40}$'),
    display_name text not null default 'Player' check (char_length(btrim(display_name)) between 1 and 80),
    bio text not null default '' check (char_length(bio) <= 500),
    avatar_path text check (avatar_path is null or (avatar_path like id::text || '/%' and char_length(avatar_path) <= 300)),
    created_at timestamptz not null default now()
);

create table public.games (
    id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    name text not null check (char_length(name) between 1 and 100)
);
insert into public.games(id, name) values ('zenless-zone-zero', 'Zenless Zone Zero');

create table public.game_cards (
    user_id uuid not null references public.profiles(id) on delete cascade,
    game_id text not null references public.games(id),
    player_name text not null check (char_length(btrim(player_name)) between 1 and 80),
    days_played integer check (days_played is null or days_played >= 0),
    progress text not null default '' check (char_length(progress) <= 1000),
    primary key (user_id, game_id)
);
create index game_cards_game_idx on public.game_cards(game_id, user_id);

create table public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references public.profiles(id) on delete cascade,
    recipient_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
    created_at timestamptz not null default now(),
    check (sender_id <> recipient_id)
);
-- A reverse request never silently accepts an incoming request.
create unique index friend_requests_pending_pair_idx on public.friend_requests
    (least(sender_id, recipient_id), greatest(sender_id, recipient_id)) where status = 'pending';
create index friend_requests_sender_idx on public.friend_requests(sender_id, created_at desc);
create index friend_requests_recipient_idx on public.friend_requests(recipient_id, status, created_at desc);

create table public.friendships (
    user_low uuid not null references public.profiles(id) on delete cascade,
    user_high uuid not null references public.profiles(id) on delete cascade,
    primary key (user_low, user_high),
    check (user_low < user_high)
);
create index friendships_user_high_idx on public.friendships(user_high);

create table public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_low uuid not null references public.profiles(id) on delete cascade,
    user_high uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (user_low, user_high),
    check (user_low < user_high)
);
create index conversations_user_high_idx on public.conversations(user_high, created_at desc);

create table public.messages (
    id uuid primary key,
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    sender_id uuid not null references public.profiles(id) on delete cascade,
    body text not null check (char_length(btrim(body)) between 1 and 2000),
    created_at timestamptz not null default now()
);
create index messages_conversation_time_idx on public.messages(conversation_id, created_at, id);
create index messages_sender_idx on public.messages(sender_id);

create table public.blocks (
    owner_id uuid not null references public.profiles(id) on delete cascade,
    blocked_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (owner_id, blocked_id),
    check (owner_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks(blocked_id, owner_id);

-- Foundations only: no curated content, accepted clips or successful purchases
-- are seeded. Review and economic fields have no client write privileges.
create table public.video_posts (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id) on delete cascade,
    game_id text not null references public.games(id),
    caption text not null default '' check (char_length(caption) <= 500),
    video_path text not null unique,
    thumbnail_path text unique,
    status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
    created_at timestamptz not null default now(),
    approved_at timestamptz,
    check (video_path like owner_id::text || '/' || id::text || '/%' and char_length(video_path) <= 300),
    check (thumbnail_path is null or (thumbnail_path like owner_id::text || '/' || id::text || '/%' and char_length(thumbnail_path) <= 300)),
    check (status <> 'approved' or approved_at is not null)
);
create index video_posts_owner_idx on public.video_posts(owner_id, created_at desc);
create index video_posts_approved_idx on public.video_posts(game_id, approved_at desc) where status = 'approved';
create table private.video_reviews (
    id uuid primary key default gen_random_uuid(),
    post_id uuid not null references public.video_posts(id) on delete cascade,
    decision text not null check (decision in ('approved', 'rejected')),
    reviewer_reference text not null,
    notes text not null default '',
    created_at timestamptz not null default now()
);
create index video_reviews_post_idx on private.video_reviews(post_id);

create table public.guides (
    id uuid primary key default gen_random_uuid(),
    game_id text not null references public.games(id),
    title text not null check (char_length(btrim(title)) between 1 and 200),
    summary text not null default '' check (char_length(summary) <= 1000),
    source_url text not null check (source_url like 'https://%'),
    source_name text not null check (char_length(btrim(source_name)) > 0),
    source_author text,
    attribution text not null check (char_length(btrim(attribution)) > 0),
    status text not null default 'draft' check (status in ('draft', 'published')),
    published_at timestamptz,
    check (status <> 'published' or published_at is not null)
);
create index guides_game_published_idx on public.guides(game_id, published_at desc) where status = 'published';

create table public.wallets (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    sparks bigint not null default 0 check (sparks >= 0)
);
create table public.spark_packs (
    id text primary key,
    name text not null,
    sparks bigint not null check (sparks > 0),
    store_product_id text unique,
    is_active boolean not null default false
);
create table public.avatar_frames (
    id text primary key,
    name text not null,
    price_sparks bigint not null check (price_sparks > 0),
    artwork_path text,
    is_active boolean not null default false
);
create table public.owned_avatar_frames (
    user_id uuid not null references public.profiles(id) on delete cascade,
    frame_id text not null references public.avatar_frames(id),
    created_at timestamptz not null default now(),
    primary key (user_id, frame_id)
);
create index owned_avatar_frames_frame_idx on public.owned_avatar_frames(frame_id);
create table private.purchase_transactions (
    environment text not null check (environment in ('Sandbox', 'Production')),
    transaction_id text not null,
    -- Keep transaction uniqueness after deletion to prevent receipt replay.
    user_id uuid references public.profiles(id) on delete set null,
    store_product_id text not null,
    credited_sparks bigint not null check (credited_sparks > 0),
    verified_at timestamptz not null default now(),
    primary key (environment, transaction_id)
);
create index purchase_transactions_user_idx on private.purchase_transactions(user_id);
create table private.wallet_ledger (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references public.profiles(id) on delete set null,
    delta bigint not null check (delta <> 0),
    reason text not null check (reason in ('storekit_recharge', 'frame_purchase', 'storekit_refund')),
    reference text not null unique,
    created_at timestamptz not null default now()
);
create index wallet_ledger_user_idx on private.wallet_ledger(user_id, created_at desc);

-- RLS includes current account/session checks, not merely the JWT's role.
-- The Apple identity is server-owned Auth data; user_metadata is never trusted.
create function private.actor_is_active() returns boolean
language sql stable security definer set search_path = '' as $$
    select auth.uid() is not null
       and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
       and exists (select 1 from private.accounts a where a.user_id = auth.uid() and a.state = 'active')
       and exists (select 1 from auth.sessions s where s.id = nullif(auth.jwt() ->> 'session_id', '')::uuid and s.user_id = auth.uid())
       and exists (select 1 from auth.identities i where i.user_id = auth.uid() and i.provider = 'apple');
$$;

create function private.can_view_user(target_user_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select private.actor_is_active()
       and exists (select 1 from private.accounts a where a.user_id = target_user_id and a.state = 'active')
       and not exists (
           select 1 from public.blocks b
           where (b.owner_id = auth.uid() and b.blocked_id = target_user_id)
              or (b.owner_id = target_user_id and b.blocked_id = auth.uid())
       );
$$;

create function private.can_read_conversation(target_conversation_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select private.actor_is_active() and exists (
        select 1 from public.conversations c
        where c.id = target_conversation_id
          and auth.uid() in (c.user_low, c.user_high)
          and private.can_view_user(case when c.user_low = auth.uid() then c.user_high else c.user_low end)
    );
$$;

-- strpos is a literal substring search: %, _ and backslash never become SQL
-- wildcard syntax. Limit prevents an unbounded directory response.
create function private.discover_players(search_query text) returns setof public.profiles
language sql stable security definer set search_path = '' as $$
    select p.* from public.profiles p
    where private.actor_is_active() and p.id <> auth.uid() and private.can_view_user(p.id)
      and (pg_catalog.strpos(pg_catalog.lower(p.handle), pg_catalog.lower(btrim(coalesce(search_query, '')))) > 0
        or pg_catalog.strpos(pg_catalog.lower(p.display_name), pg_catalog.lower(btrim(coalesce(search_query, '')))) > 0)
    order by p.handle, p.id limit 50;
$$;

-- Mutation helpers run only in private. Exposed wrappers are SECURITY INVOKER.
-- Holding the account row prevents deletion/suspension from racing a write.
create function private.require_actor() returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
    if not private.actor_is_active() then
        raise exception using errcode = '42501', message = 'active_apple_session_required';
    end if;
    perform 1 from private.accounts a where a.user_id = actor and a.state = 'active' for share;
    if not found then
        raise exception using errcode = '42501', message = 'active_account_required';
    end if;
    return actor;
end;
$$;

create function private.lock_pair(first_user uuid, second_user uuid) returns void
language sql volatile security definer set search_path = '' as $$
    select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        least(first_user, second_user)::text || ':' || greatest(first_user, second_user)::text, 0));
$$;

create function private.send_friend_request(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
    actor uuid := private.require_actor();
    request_row public.friend_requests;
begin
    if target_user_id is null or target_user_id = actor then
        raise exception using errcode = '22023', message = 'invalid_target_user';
    end if;
    perform private.lock_pair(actor, target_user_id);
    if not private.can_view_user(target_user_id) then
        raise exception using errcode = '42501', message = 'user_unavailable';
    end if;
    if exists (select 1 from public.friendships f where f.user_low = least(actor, target_user_id) and f.user_high = greatest(actor, target_user_id)) then
        raise exception using errcode = '22023', message = 'already_friends';
    end if;
    select * into request_row from public.friend_requests r
    where least(r.sender_id, r.recipient_id) = least(actor, target_user_id)
      and greatest(r.sender_id, r.recipient_id) = greatest(actor, target_user_id)
      and r.status = 'pending' for update;
    if found then
        if request_row.sender_id <> actor then
            raise exception using errcode = '22023', message = 'incoming_request_exists';
        end if;
        return to_jsonb(request_row);
    end if;
    insert into public.friend_requests(sender_id, recipient_id)
    values (actor, target_user_id) returning * into request_row;
    return to_jsonb(request_row);
end;
$$;

create function private.respond_friend_request(request_id uuid, accept boolean) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
    actor uuid := private.require_actor();
    request_row public.friend_requests;
    conversation_id uuid;
begin
    if accept is null then
        raise exception using errcode = '22023', message = 'accept_required';
    end if;
    -- Read identity first, then acquire the same pair lock used by blocking.
    select * into request_row from public.friend_requests r where r.id = request_id and r.recipient_id = actor;
    if not found then
        raise exception using errcode = '42501', message = 'request_unavailable';
    end if;
    perform private.lock_pair(actor, request_row.sender_id);
    select * into request_row from public.friend_requests r where r.id = request_id and r.recipient_id = actor for update;
    if not found or not private.can_view_user(request_row.sender_id) then
        raise exception using errcode = '42501', message = 'request_unavailable';
    end if;
    if request_row.status = 'accepted' and accept then
        select c.id into conversation_id from public.conversations c
        where c.user_low = least(actor, request_row.sender_id) and c.user_high = greatest(actor, request_row.sender_id);
        return jsonb_build_object('request_id', request_id, 'status', 'accepted', 'conversation_id', conversation_id);
    end if;
    if request_row.status <> 'pending' then
        raise exception using errcode = '22023', message = 'request_not_pending';
    end if;
    update public.friend_requests r set status = case when accept then 'accepted' else 'declined' end where r.id = request_id;
    if accept then
        insert into public.friendships(user_low, user_high)
        values (least(actor, request_row.sender_id), greatest(actor, request_row.sender_id)) on conflict do nothing;
        insert into public.conversations(user_low, user_high)
        values (least(actor, request_row.sender_id), greatest(actor, request_row.sender_id)) on conflict do nothing;
        select c.id into conversation_id from public.conversations c
        where c.user_low = least(actor, request_row.sender_id) and c.user_high = greatest(actor, request_row.sender_id);
    end if;
    return jsonb_build_object('request_id', request_id, 'status', case when accept then 'accepted' else 'declined' end, 'conversation_id', conversation_id);
end;
$$;

create function private.block_user(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := private.require_actor();
begin
    if target_user_id is null or target_user_id = actor then
        raise exception using errcode = '22023', message = 'invalid_target_user';
    end if;
    perform private.lock_pair(actor, target_user_id);
    if not exists (select 1 from public.profiles p where p.id = target_user_id) then
        raise exception using errcode = '22023', message = 'user_unavailable';
    end if;
    insert into public.blocks(owner_id, blocked_id) values (actor, target_user_id) on conflict do nothing;
    update public.friend_requests r set status = 'cancelled'
    where r.status = 'pending'
      and least(r.sender_id, r.recipient_id) = least(actor, target_user_id)
      and greatest(r.sender_id, r.recipient_id) = greatest(actor, target_user_id);
    delete from public.friendships f where f.user_low = least(actor, target_user_id) and f.user_high = greatest(actor, target_user_id);
    -- Conversations remain stored, but both participants lose read/send access.
    return jsonb_build_object('blocked_user_id', target_user_id);
end;
$$;

create function private.send_message(target_conversation_id uuid, message_id uuid, message_body text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
    actor uuid := private.require_actor();
    peer uuid;
    message_row public.messages;
    normalized_body text := btrim(message_body);
begin
    if message_id is null or normalized_body is null or char_length(normalized_body) not between 1 and 2000 then
        raise exception using errcode = '22023', message = 'invalid_message';
    end if;
    select case when c.user_low = actor then c.user_high else c.user_low end into peer
    from public.conversations c where c.id = target_conversation_id and actor in (c.user_low, c.user_high);
    if not found then
        raise exception using errcode = '42501', message = 'conversation_unavailable';
    end if;
    perform private.lock_pair(actor, peer);
    if not private.can_view_user(peer) or not exists (
        select 1 from public.friendships f where f.user_low = least(actor, peer) and f.user_high = greatest(actor, peer)
    ) then
        raise exception using errcode = '42501', message = 'friendship_required';
    end if;
    select * into message_row from public.messages m where m.id = message_id;
    if found then
        if message_row.sender_id <> actor or message_row.conversation_id <> target_conversation_id or message_row.body <> normalized_body then
            raise exception using errcode = '22023', message = 'message_id_conflict';
        end if;
        return to_jsonb(message_row);
    end if;
    -- ON CONFLICT handles a same-UUID request racing in a different pair.
    insert into public.messages(id, conversation_id, sender_id, body)
    values (message_id, target_conversation_id, actor, normalized_body) on conflict do nothing returning * into message_row;
    if not found then
        raise exception using errcode = '22023', message = 'message_id_conflict';
    end if;
    return to_jsonb(message_row);
end;
$$;

create function public.send_friend_request(target_user_id uuid) returns jsonb
language sql volatile security invoker set search_path = '' as $$ select private.send_friend_request(target_user_id); $$;
create function public.respond_friend_request(request_id uuid, accept boolean) returns jsonb
language sql volatile security invoker set search_path = '' as $$ select private.respond_friend_request(request_id, accept); $$;
create function public.block_user(target_user_id uuid) returns jsonb
language sql volatile security invoker set search_path = '' as $$ select private.block_user(target_user_id); $$;
create function public.send_message(target_conversation_id uuid, message_id uuid, message_body text) returns jsonb
language sql volatile security invoker set search_path = '' as $$ select private.send_message(target_conversation_id, message_id, message_body); $$;
create function public.discover_players(search_query text) returns setof public.profiles
language sql stable security invoker set search_path = '' as $$ select * from private.discover_players(search_query); $$;

-- No email, Apple subject or untrusted metadata is copied into public profiles.
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    insert into private.accounts(user_id) values (new.id);
    insert into public.profiles(id, handle) values (new.id, 'player_' || replace(new.id::text, '-', ''));
    insert into public.wallets(user_id) values (new.id);
    return new;
end;
$$;
create trigger fltiya_auth_user_created after insert on auth.users for each row execute function private.handle_new_user();

-- Every application table is protected, including server-only private tables.
alter table private.accounts enable row level security;
alter table private.video_reviews enable row level security;
alter table private.purchase_transactions enable row level security;
alter table private.wallet_ledger enable row level security;
alter table public.profiles enable row level security;
alter table public.games enable row level security;
alter table public.game_cards enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.blocks enable row level security;
alter table public.video_posts enable row level security;
alter table public.guides enable row level security;
alter table public.wallets enable row level security;
alter table public.spark_packs enable row level security;
alter table public.avatar_frames enable row level security;
alter table public.owned_avatar_frames enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (private.can_view_user(id));
create policy profiles_update on public.profiles for update to authenticated
    using ((select private.actor_is_active()) and id = (select auth.uid()))
    with check ((select private.actor_is_active()) and id = (select auth.uid()));
create policy games_read on public.games for select to authenticated using ((select private.actor_is_active()));
create policy game_cards_read on public.game_cards for select to authenticated using (private.can_view_user(user_id));
create policy game_cards_insert on public.game_cards for insert to authenticated
    with check ((select private.actor_is_active()) and user_id = (select auth.uid()));
create policy game_cards_update on public.game_cards for update to authenticated
    using ((select private.actor_is_active()) and user_id = (select auth.uid()))
    with check ((select private.actor_is_active()) and user_id = (select auth.uid()));
create policy game_cards_delete on public.game_cards for delete to authenticated
    using ((select private.actor_is_active()) and user_id = (select auth.uid()));
create policy friend_requests_read on public.friend_requests for select to authenticated
    using ((select private.actor_is_active()) and (select auth.uid()) in (sender_id, recipient_id)
        and private.can_view_user(case when sender_id = (select auth.uid()) then recipient_id else sender_id end));
create policy friendships_read on public.friendships for select to authenticated
    using ((select private.actor_is_active()) and (select auth.uid()) in (user_low, user_high)
        and private.can_view_user(case when user_low = (select auth.uid()) then user_high else user_low end));
create policy conversations_read on public.conversations for select to authenticated using (private.can_read_conversation(id));
create policy messages_read on public.messages for select to authenticated using (private.can_read_conversation(conversation_id));
create policy blocks_read on public.blocks for select to authenticated
    using ((select private.actor_is_active()) and owner_id = (select auth.uid()));
create policy video_posts_read on public.video_posts for select to authenticated
    using ((select private.actor_is_active()) and (owner_id = (select auth.uid()) or (status = 'approved' and private.can_view_user(owner_id))));
create policy video_posts_insert on public.video_posts for insert to authenticated
    with check ((select private.actor_is_active()) and owner_id = (select auth.uid()) and status = 'pending' and approved_at is null);
create policy guides_read on public.guides for select to authenticated using ((select private.actor_is_active()) and status = 'published');
create policy wallets_read on public.wallets for select to authenticated using ((select private.actor_is_active()) and user_id = (select auth.uid()));
create policy spark_packs_read on public.spark_packs for select to authenticated using ((select private.actor_is_active()) and is_active);
create policy avatar_frames_read on public.avatar_frames for select to authenticated using ((select private.actor_is_active()) and is_active);
create policy owned_avatar_frames_read on public.owned_avatar_frames for select to authenticated
    using ((select private.actor_is_active()) and user_id = (select auth.uid()));

-- Explicit per-object grants also neutralize legacy default table grants.
revoke all on public.profiles, public.games, public.game_cards, public.friend_requests,
    public.friendships, public.conversations, public.messages, public.blocks,
    public.video_posts, public.guides, public.wallets, public.spark_packs,
    public.avatar_frames, public.owned_avatar_frames from public, anon, authenticated;
revoke all on private.accounts, private.video_reviews, private.purchase_transactions, private.wallet_ledger from public, anon, authenticated;
grant select on public.profiles, public.games, public.game_cards, public.friend_requests,
    public.friendships, public.conversations, public.messages, public.blocks,
    public.video_posts, public.guides, public.wallets, public.spark_packs,
    public.avatar_frames, public.owned_avatar_frames to authenticated;
grant update (handle, display_name, bio, avatar_path) on public.profiles to authenticated;
grant insert, update, delete on public.game_cards to authenticated;
grant insert (id, owner_id, game_id, caption, video_path, thumbnail_path) on public.video_posts to authenticated;
grant all on public.profiles, public.games, public.game_cards, public.friend_requests,
    public.friendships, public.conversations, public.messages, public.blocks,
    public.video_posts, public.guides, public.wallets, public.spark_packs,
    public.avatar_frames, public.owned_avatar_frames to service_role;
grant all on private.accounts, private.video_reviews, private.purchase_transactions, private.wallet_ledger to service_role;

revoke all on function private.actor_is_active(), private.can_view_user(uuid), private.can_read_conversation(uuid),
    private.require_actor(), private.lock_pair(uuid, uuid), private.handle_new_user(), private.discover_players(text),
    private.send_friend_request(uuid), private.respond_friend_request(uuid, boolean),
    private.block_user(uuid), private.send_message(uuid, uuid, text),
    public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean),
    public.block_user(uuid), public.send_message(uuid, uuid, text), public.discover_players(text) from public, anon, authenticated;
grant execute on function private.actor_is_active(), private.can_view_user(uuid), private.can_read_conversation(uuid),
    private.discover_players(text), private.send_friend_request(uuid), private.respond_friend_request(uuid, boolean),
    private.block_user(uuid), private.send_message(uuid, uuid, text),
    public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean),
    public.block_user(uuid), public.send_message(uuid, uuid, text), public.discover_players(text) to authenticated;

-- Private buckets only. No public URLs, object signing or listing is granted.
-- New immutable names are required; authenticated UPDATE/DELETE is not granted.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types) values
    ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
    ('clips', 'clips', false, 104857600, array['video/mp4', 'video/quicktime', 'image/jpeg', 'image/png', 'image/webp']);

create policy fltiya_avatar_insert on storage.objects for insert to authenticated with check (
    bucket_id = 'avatars' and (select private.actor_is_active())
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and owner_id = (select auth.uid())::text
);
create policy fltiya_avatar_read on storage.objects for select to authenticated using (
    bucket_id = 'avatars' and (select private.actor_is_active())
    and storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
    and exists (select 1 from public.profiles p where p.avatar_path = name and private.can_view_user(p.id))
);
create policy fltiya_clip_insert on storage.objects for insert to authenticated with check (
    bucket_id = 'clips' and (select private.actor_is_active())
    and owner_id = (select auth.uid())::text
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.video_posts v where v.owner_id = (select auth.uid()) and v.status = 'pending'
        and (v.video_path = name or v.thumbnail_path = name))
);
create policy fltiya_clip_read on storage.objects for select to authenticated using (
    bucket_id = 'clips' and (select private.actor_is_active())
    and storage.allow_any_operation(array['object.get_authenticated', 'object.get_authenticated_info'])
    and exists (select 1 from public.video_posts v where (v.video_path = name or v.thumbnail_path = name)
        and (v.owner_id = (select auth.uid()) or (v.status = 'approved' and private.can_view_user(v.owner_id))))
);

comment on table public.game_cards is 'Manually entered player information. No game password, token, credential or unofficial account scraping.';
comment on table public.wallets is 'Server-only economic writes. Zero starts empty; no client recharge or purchase simulation.';
comment on table public.owned_avatar_frames is 'Permanent entitlements; server-only writes after a verified transactional purchase.';
comment on table public.video_posts is 'Pending/rejected owner-only; reviewer must verify existing immutable video and thumbnail before approval.';
comment on function private.actor_is_active() is 'Fails closed after suspension, deletion or session revocation, including reads with an unexpired old JWT.';

commit;
