-- Ordinary removal preserves message history and never changes block state.
-- Requests from the previous relationship must not be accepted again.
begin;

create function private.remove_friend(target_user_id uuid) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := private.require_actor();
begin
    if target_user_id is null or target_user_id = actor then
        raise exception using errcode = '22023', message = 'invalid_target_user';
    end if;

    -- Serialize with send/request acceptance/block and message writes for the
    -- same pair. An acceptance which wins first is removed; one after removal
    -- observes the cancelled request and cannot restore the friendship.
    perform private.lock_pair(actor, target_user_id);
    if not private.can_view_user(target_user_id) then
        raise exception using errcode = '42501', message = 'user_unavailable';
    end if;

    update public.friend_requests r set status = 'cancelled'
    where r.status in ('pending', 'accepted')
      and least(r.sender_id, r.recipient_id) = least(actor, target_user_id)
      and greatest(r.sender_id, r.recipient_id) = greatest(actor, target_user_id);
    delete from public.friendships f
    where f.user_low = least(actor, target_user_id)
      and f.user_high = greatest(actor, target_user_id);

    -- The same response for an eligible nonfriend makes retries safe without
    -- exposing a second relationship check or any third-party relationship.
    return jsonb_build_object('removed_user_id', target_user_id);
end;
$$;

create function public.remove_friend(target_user_id uuid) returns jsonb
language sql volatile security invoker set search_path = ''
as $$ select private.remove_friend(target_user_id); $$;

revoke all on function private.remove_friend(uuid), public.remove_friend(uuid)
    from public, anon, authenticated;
grant execute on function private.remove_friend(uuid), public.remove_friend(uuid)
    to authenticated;

commit;
