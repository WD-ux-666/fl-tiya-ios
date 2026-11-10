-- Link explicitly credited comments to their approved community sample.
-- Keep the comment author's pseudonym and resolve the sample through community access controls.
begin;

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
                || case when sample.id is not null then jsonb_build_object(
                    'sample_handle',sample.handle,'sample_game_id',sample.game_id)
                    else '{}'::jsonb end
            else private.clip_comment_json(c::private.clip_comments)
        end order by c.created_at desc,c.id desc
    ),'[]'::jsonb)
    into result from (
        select c.* from private.clip_comments c where c.clip_id=target_clip_id
          and (c.status='approved' or (c.author_id=actor and c.status='pending'))
          and private.can_read_clip_comment(c,experience_clip)
        order by c.created_at desc,c.id desc limit 100
    ) c
    left join private.curated_clip_comment_credits credit on credit.comment_id=c.id
    left join private.curated_community_players sample
      on experience_clip and credit.comment_id is not null and sample.id=c.author_id
      and private.can_see_community_sample(sample.id)
      and not exists (
          select 1 from private.curated_community_players other
          where other.game_id=sample.game_id and lower(other.handle)=lower(sample.handle) and other.id<>sample.id
      );
    return result;
end;
$$;

commit;
