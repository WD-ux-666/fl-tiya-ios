begin;

-- Sample conversations do not reach other players. Honor the viewer's
-- request to hide the fixture without creating an item for real moderation.
create function private.report_curated_sample_player(target_user_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := private.require_actor();
begin
    if target_user_id is null or target_user_id=actor then
        raise exception using errcode='42501',message='sample_player_unavailable';
    end if;
    perform private.lock_pair(actor,target_user_id);
    if not private.is_community_sample(target_user_id) then
        raise exception using errcode='42501',message='sample_player_unavailable';
    end if;
    if private.report_hides_target(actor,'conversation',target_user_id) then
        return false;
    end if;
    if not private.can_see_community_sample(target_user_id) then
        raise exception using errcode='42501',message='sample_player_unavailable';
    end if;

    insert into private.content_report_hides(viewer_id,target_type,target_id)
    values (actor,'conversation',target_user_id) on conflict do nothing;
    return found;
end;
$$;

create function public.report_curated_sample_player(target_user_id uuid) returns boolean
language sql security invoker set search_path='' as $$
    select private.report_curated_sample_player(target_user_id);
$$;

revoke all on function private.report_curated_sample_player(uuid),public.report_curated_sample_player(uuid)
from public,anon,authenticated,service_role;
grant execute on function private.report_curated_sample_player(uuid),public.report_curated_sample_player(uuid)
to authenticated;

commit;
