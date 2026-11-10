-- Follow-up to the first deployed schema: signed-upload capabilities must not
-- outlive the live account/session checks enforced for standard uploads.
alter policy fltiya_avatar_insert on storage.objects with check (
    bucket_id = 'avatars' and (select private.actor_is_active())
    and storage.allow_any_operation(array['object.upload'])
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and owner_id = (select auth.uid())::text
);
alter policy fltiya_clip_insert on storage.objects with check (
    bucket_id = 'clips' and (select private.actor_is_active())
    and storage.allow_any_operation(array['object.upload'])
    and owner_id = (select auth.uid())::text
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.video_posts v where v.owner_id = (select auth.uid()) and v.status = 'pending'
        and (v.video_path = name or v.thumbnail_path = name))
);
