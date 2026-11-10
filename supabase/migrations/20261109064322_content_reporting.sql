-- The app can submit reports but cannot read or change the private review queue.
begin;

create table private.content_reports (
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    subject_id uuid not null references public.profiles(id) on delete cascade,
    target_type text not null check (target_type in ('video','comment','conversation')),
    target_id uuid not null,
    reason text not null check (reason in ('spam','harassment','inappropriate','other')),
    details text check (char_length(details) between 1 and 500),
    created_at timestamptz not null default now(),
    reviewed_at timestamptz,
    primary key (reporter_id,target_type,target_id),
    check (reporter_id <> subject_id),
    check (target_type <> 'conversation' or target_id = subject_id)
);
create index content_reports_subject_idx on private.content_reports(subject_id);
create index content_reports_pending_idx on private.content_reports(created_at) where reviewed_at is null;
alter table private.content_reports enable row level security;
revoke all on private.content_reports from public,anon,authenticated,service_role;
grant select on private.content_reports to service_role;
grant update (reviewed_at) on private.content_reports to service_role;
comment on table private.content_reports is
    'Private moderation queue. Conversation targets reference the other participant; no message text or other content is copied.';

create function private.submit_content_report(
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

    case p_target_type
    when 'video' then
        -- Includes editorial clips readable by experience accounts, without
        -- disclosing a hidden uploader to the reporting account.
        select v.owner_id into subject from public.video_posts v
        where v.id=p_target_id and private.can_interact_with_clip(v.id);
    when 'comment' then
        select c.author_id into subject from private.clip_comments c
        where c.id=p_target_id and c.status='approved'
          and private.can_interact_with_clip(c.clip_id) and private.can_view_user(c.author_id);
    when 'conversation' then
        -- Same access check as the direct chat entry. A new conversation can be
        -- reported before an introduction, without creating a conversation row.
        select p.id into subject from public.profiles p
        where p.id=p_target_id and private.can_view_user(p.id);
    end case;

    if subject is null or subject=actor then
        raise exception using errcode='42501',message='report_target_unavailable';
    end if;
    insert into private.content_reports(reporter_id,subject_id,target_type,target_id,reason,details)
    values(actor,subject,p_target_type,p_target_id,p_reason,details_value)
    on conflict (reporter_id,target_type,target_id) do nothing;
    return found;
end;
$$;

create function public.submit_content_report(
    p_target_type text, p_target_id uuid, p_reason text, p_details text default null
) returns boolean
language sql volatile security invoker set search_path='' as $$
    select private.submit_content_report($1,$2,$3,$4);
$$;
revoke all on function private.submit_content_report(text,uuid,text,text),
    public.submit_content_report(text,uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function private.submit_content_report(text,uuid,text,text),
    public.submit_content_report(text,uuid,text,text) to authenticated;

commit;
