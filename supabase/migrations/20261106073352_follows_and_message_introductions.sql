-- Follow never grants friendship or calls. Each sender gets one lifetime
-- nonfriend introduction per recipient; friend messages do not spend it.
begin;
create table private.player_follows (
 follower_id uuid not null references public.profiles(id) on delete cascade,
 followed_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(follower_id,followed_id), check(follower_id<>followed_id)
);
create index player_follows_followed_idx on private.player_follows(followed_id,follower_id);
-- Neither table depends on messages/conversations/friendships/blocks: deleting
-- history, unfriend/refriend or unblock cannot replenish a spent introduction.
create table private.message_introductions (
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 message_id uuid not null unique,
 created_at timestamptz not null default now(),
 primary key(sender_id,recipient_id), check(sender_id<>recipient_id)
);
create index message_introductions_recipient_idx on private.message_introductions(recipient_id);
create table private.message_receipts (
 message_id uuid primary key,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 body_hash bytea not null,
 created_at timestamptz not null default now(), check(sender_id<>recipient_id)
);
create index message_receipts_sender_idx on private.message_receipts(sender_id);
create index message_receipts_recipient_idx on private.message_receipts(recipient_id);
-- Preserve idempotency for already delivered messages without altering them.
insert into private.message_receipts(message_id,sender_id,recipient_id,body_hash,created_at)
 select m.id,m.sender_id,case when m.sender_id=c.user_low then c.user_high else c.user_low end,
 extensions.digest(m.body,'sha256'),m.created_at from public.messages m
 join public.conversations c on c.id=m.conversation_id;
alter table private.player_follows enable row level security;
alter table private.message_introductions enable row level security;
alter table private.message_receipts enable row level security;
revoke all on private.player_follows,private.message_introductions,private.message_receipts from public,anon,authenticated;
grant all on private.player_follows,private.message_introductions,private.message_receipts to service_role;

-- Called only by trusted private writers, after require_actor. Hold target
-- identity/account through the transaction to serialize account deletion.
create function private.require_social_peer(target_user_id uuid) returns void
language plpgsql volatile security definer set search_path='' as $$
begin
 if target_user_id is null or target_user_id=auth.uid() then
  raise exception using errcode='22023',message='invalid_target_user';end if;
 perform 1 from auth.users where id=target_user_id for share;
 perform 1 from private.accounts where user_id=target_user_id for share;
 perform 1 from private.development_accounts where user_id=target_user_id for share;
 if not private.can_view_user(target_user_id) then
  raise exception using errcode='42501',message='user_unavailable';end if;
end $$;
create function private.player_follow_state(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();
begin
 if target_user_id is null or not private.can_view_user(target_user_id) then
  raise exception using errcode='42501',message='user_unavailable';end if;
 return jsonb_build_object('is_following',exists(select 1 from private.player_follows
  where follower_id=actor and followed_id=target_user_id),
  'follower_count',(select count(*) from private.player_follows where followed_id=target_user_id and private.can_view_user(follower_id)));
end $$;
create function private.set_player_followed(target_user_id uuid,followed boolean) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();
begin
 if followed is null then raise exception using errcode='22023',message='followed_required';end if;
 perform private.require_social_peer(target_user_id);
 perform private.lock_pair(actor,target_user_id);
 if not private.can_view_user(target_user_id) then raise exception using errcode='42501',message='user_unavailable';end if;
 if followed then
  insert into private.player_follows(follower_id,followed_id) values(actor,target_user_id) on conflict do nothing;
 else delete from private.player_follows where follower_id=actor and followed_id=target_user_id;end if;
 return private.player_follow_state(target_user_id);
end $$;
create function private.open_direct_conversation(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor(); result public.conversations;
begin
 perform private.require_social_peer(target_user_id);
 perform private.lock_pair(actor,target_user_id);
 if not private.can_view_user(target_user_id) then raise exception using errcode='42501',message='user_unavailable';end if;
 insert into public.conversations(user_low,user_high) values(least(actor,target_user_id),greatest(actor,target_user_id)) on conflict do nothing;
 select * into result from public.conversations where user_low=least(actor,target_user_id) and user_high=greatest(actor,target_user_id);
 return to_jsonb(result);
end $$;
create function private.conversation_messaging_state(target_conversation_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();peer uuid;friend boolean;spent boolean;
begin
 select case when user_low=actor then user_high else user_low end into peer from public.conversations
 where id=target_conversation_id and actor in(user_low,user_high);
 if not found or not private.can_read_conversation(target_conversation_id) then
  raise exception using errcode='42501',message='conversation_unavailable';end if;
 friend:=exists(select 1 from public.friendships where user_low=least(actor,peer) and user_high=greatest(actor,peer));
 spent:=exists(select 1 from private.message_introductions where sender_id=actor and recipient_id=peer);
 return jsonb_build_object('is_friend',friend,'can_send',friend or not spent,'has_sent_introduction',spent);
end $$;
create or replace function private.send_message(target_conversation_id uuid,message_id uuid,message_body text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();peer uuid;message_row public.messages;
 receipt private.message_receipts;normalized_body text:=btrim(message_body,E' \t\r\n');claimed uuid;
begin
 if message_id is null or normalized_body is null or char_length(normalized_body) not between 1 and 2000 then
  raise exception using errcode='22023',message='invalid_message';end if;
 select case when user_low=actor then user_high else user_low end into peer from public.conversations
 where id=target_conversation_id and actor in(user_low,user_high);
 if not found then raise exception using errcode='42501',message='conversation_unavailable';end if;
 perform private.require_social_peer(peer);
 perform private.lock_pair(actor,peer);
 if not private.can_read_conversation(target_conversation_id) then
  raise exception using errcode='42501',message='conversation_unavailable';end if;
 -- Check durable receipt before quota. A retry never sends again, even when
 -- an administrator deleted the message/conversation or friendship changed.
 select * into receipt from private.message_receipts r where r.message_id=send_message.message_id;
 if found then
  if receipt.sender_id<>actor or receipt.recipient_id<>peer or receipt.body_hash<>extensions.digest(normalized_body,'sha256') then
   raise exception using errcode='22023',message='message_id_conflict';end if;
  select * into message_row from public.messages m where m.id=message_id;
  if found then return to_jsonb(message_row);end if;
  return jsonb_build_object('id',message_id,'accepted',true);
 end if;
 if not exists(select 1 from public.friendships where user_low=least(actor,peer) and user_high=greatest(actor,peer)) then
  -- Unique PK is the final concurrency authority, not count-then-insert.
  insert into private.message_introductions(sender_id,recipient_id,message_id)
   values(actor,peer,message_id) on conflict(sender_id,recipient_id) do nothing returning sender_id into claimed;
  if claimed is null then raise exception using errcode='P0001',message='stranger_message_limit';end if;
 end if;
 insert into private.message_receipts(message_id,sender_id,recipient_id,body_hash)
 values(message_id,actor,peer,extensions.digest(normalized_body,'sha256')) on conflict do nothing returning * into receipt;
 if not found then raise exception using errcode='22023',message='message_id_conflict';end if;
 insert into public.messages(id,conversation_id,sender_id,body) values(message_id,target_conversation_id,actor,normalized_body)
 on conflict do nothing returning * into message_row;
 if not found then raise exception using errcode='22023',message='message_id_conflict';end if;
 return to_jsonb(message_row);
end $$;
create or replace function private.clip_social_state(target_clip_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=private.require_actor();owner_profile jsonb;owner_id uuid;
begin
 if not private.can_interact_with_clip(target_clip_id) then raise exception using errcode='42501',message='clip_unavailable';end if;
 select jsonb_build_object('id',p.id,'handle',p.handle,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path),p.id
 into owner_profile,owner_id from public.video_posts v join public.profiles p on p.id=v.owner_id
 where v.id=target_clip_id and private.can_view_user(p.id);
 return jsonb_build_object('uploader',owner_profile,
  'is_following',exists(select 1 from private.player_follows where follower_id=actor and followed_id=owner_id),
  'is_liked',exists(select 1 from private.clip_likes where clip_id=target_clip_id and user_id=actor),
  'like_count',(select count(*) from private.clip_likes where clip_id=target_clip_id and private.can_view_user(user_id)),
  'comment_count',(select count(*) from private.clip_comments where clip_id=target_clip_id and status='approved' and private.can_view_user(author_id)));
end $$;
create function private.remove_blocked_follows() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from private.player_follows where (follower_id=new.owner_id and followed_id=new.blocked_id)
  or (follower_id=new.blocked_id and followed_id=new.owner_id);
 return new;
end $$;
create trigger fltiya_remove_blocked_follows after insert on public.blocks for each row execute function private.remove_blocked_follows();
revoke all on function private.remove_blocked_follows() from public,anon,authenticated;
create function public.player_follow_state(target_user_id uuid) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.player_follow_state($1); $$;
create function public.set_player_followed(target_user_id uuid,followed boolean) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.set_player_followed($1,$2); $$;
create function public.open_direct_conversation(target_user_id uuid) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.open_direct_conversation($1); $$;
create function public.conversation_messaging_state(target_conversation_id uuid) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.conversation_messaging_state($1); $$;
revoke all on function private.require_social_peer(uuid) from public,anon,authenticated;
revoke all on function private.player_follow_state(uuid),private.set_player_followed(uuid,boolean),private.open_direct_conversation(uuid),private.conversation_messaging_state(uuid),
 public.player_follow_state(uuid),public.set_player_followed(uuid,boolean),public.open_direct_conversation(uuid),public.conversation_messaging_state(uuid) from public,anon,authenticated;
grant execute on function private.player_follow_state(uuid),private.set_player_followed(uuid,boolean),private.open_direct_conversation(uuid),private.conversation_messaging_state(uuid),
 public.player_follow_state(uuid),public.set_player_followed(uuid,boolean),public.open_direct_conversation(uuid),public.conversation_messaging_state(uuid) to authenticated;
comment on table private.message_introductions is 'Lifetime one nonfriend introduction per sender/recipient. Friend messages do not consume it. Unfriend, unblock and history deletion never reset it; account deletion cascades.';
commit;
