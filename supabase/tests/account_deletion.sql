-- Apply after the self-service deletion migration. All identities/content are
-- random isolated fixtures; the transaction always rolls back. Storage rows are
-- synthetic metadata, not physical files. HTTP verifies the real Storage API.
begin;
do $test$
declare
 e uuid:=gen_random_uuid(); f uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); fake uuid:=gen_random_uuid();
 se uuid:=gen_random_uuid(); second_e uuid:=gen_random_uuid(); sf uuid:=gen_random_uuid(); sd uuid:=gen_random_uuid(); second_d uuid:=gen_random_uuid(); sp uuid:=gen_random_uuid();
 post_d uuid:=gen_random_uuid(); comment_e uuid:=gen_random_uuid(); review_d uuid:=gen_random_uuid(); cid uuid; r jsonb; reason text;
 dev_email text:='delete-'||d||'@development.invalid'; hash text:=encode(extensions.digest(d::text,'sha256'),'hex');
begin
 insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
  values(d,dev_email,'Isolated deletion fixture',hash,now()+interval '1 hour');
 insert into auth.users(id,aud,role,is_anonymous) values
  (e,'authenticated','authenticated',true),(f,'authenticated','authenticated',true),
  (p,'authenticated','authenticated',false),(fake,'authenticated','authenticated',false);
 insert into auth.users(id,aud,role,is_anonymous,email,email_confirmed_at)
  values(d,'authenticated','authenticated',false,dev_email,now());
 insert into auth.identities(provider_id,user_id,identity_data,provider) values
  (p::text,p,jsonb_build_object('sub',p),'apple'),(d::text,d,jsonb_build_object('sub',d),'email');
 insert into auth.sessions(id,user_id) values(se,e),(second_e,e),(sf,f),(sd,d),(second_d,d),(sp,p);
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
  (gen_random_uuid(),se,'anonymous',now(),now()),(gen_random_uuid(),sf,'anonymous',now(),now()),
  (gen_random_uuid(),sd,'password',now(),now()),(gen_random_uuid(),sp,'oauth',now(),now());
 -- Valid bearer identity alone is insufficient: the actual session must be its
 -- own, live session, and production anonymous users require real anonymous AMR.
 set local role service_role;
 begin perform public.prepare_account_deletion(e,sf);raise exception 'foreign session accepted';exception when insufficient_privilege then null;end;
 begin perform public.prepare_account_deletion(e,second_e);raise exception 'wrong AMR accepted';exception when insufficient_privilege then null;end;
 begin perform public.prepare_account_deletion(fake,se);raise exception 'ineligible account accepted';exception when insufficient_privilege then null;end;
 begin
  perform public.prepare_account_deletion(p,sp);raise exception 'Apple account mutated';
 exception when insufficient_privilege then get stacked diagnostics reason=message_text;
  assert reason='apple_revocation_configuration_required','Apple returns a specific safe refusal';
 end;
 begin perform public.prepare_experience_deletion(p,sp);raise exception 'legacy Apple deletion accepted';exception when insufficient_privilege then null;end;
 reset role;
 assert (select state='active' from private.accounts where user_id=p),'Apple refusal precedes state change';
 assert exists(select 1 from auth.sessions where id=sp),'Apple refusal does not revoke sessions';
 update auth.sessions set not_after=now()-interval '1 second' where id=sd;
 set local role service_role;
 begin perform public.prepare_account_deletion(d,sd);raise exception 'expired session accepted';exception when insufficient_privilege then null;end;
 reset role;
 update auth.sessions set not_after=null where id=sd;
 update private.accounts set state='suspended' where user_id=d;
 set local role service_role;
 begin perform public.prepare_account_deletion(d,sd);raise exception 'suspended account accepted';exception when insufficient_privilege then null;end;
 reset role;
 update private.accounts set state='active' where user_id=d;
 -- Linking Apple on any cohort/anonymous attestation is also protected; the old
 -- anonymous-only endpoint cannot bypass provider revocation prerequisites.
 insert into auth.identities(provider_id,user_id,identity_data,provider) values(e::text,e,jsonb_build_object('sub',e),'apple');
 set local role service_role;
 begin perform public.prepare_experience_deletion(e,se);raise exception 'linked anonymous Apple deletion accepted';exception when insufficient_privilege then null;end;
 reset role;
 assert (select state='active' from private.accounts where user_id=e),'linked identity refusal is non-destructive';
 delete from auth.identities where user_id=e and provider='apple';
 insert into public.friendships(user_low,user_high) values(least(e,f),greatest(e,f));
 set local role service_role;
 r:=public.call_action(e,se,'create',null,f,'voice');cid:=(r->'call'->>'id')::uuid;
 perform public.call_action(f,sf,'accept',cid);
 r:=public.prepare_account_deletion(e,se);
 assert r->>'user_id'=e::text,'experience is supported by the unified entry';
 reset role;
 assert not private.call_session_active(e,se),'deleting actor cannot use app/call operations';
 assert (select status='ended' from private.calls where id=cid),'accepted call ends before deleting objects';
 assert exists(select 1 from private.call_cleanup where call_id=cid),'RTC cleanup is durable';
 assert not exists(select 1 from auth.sessions where id=second_e),'other sessions are revoked';
 set local role service_role;
 perform public.prepare_account_deletion(e,se);
 r:=public.finish_account_deletion(e,se);
 assert r='{"deleted":true}'::jsonb,'experience completes and current retry is supported';
 reset role;
 assert not exists(select 1 from auth.users where id=e),'experience Auth record deleted';
 assert exists(select 1 from auth.users where id=f),'other users remain';
 assert exists(select 1 from private.call_cleanup where call_id=cid),'external cleanup survives deletion';
 -- Development account content must be cleaned before Auth can be deleted.
 insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at)
  values(post_d,d,'zenless-zone-zero',d||'/'||post_d||'/clip.mp4','approved',now());
 insert into private.video_reviews(id,post_id,decision,reviewer_reference) values(review_d,post_d,'approved','fixture');
 insert into private.clip_comments(id,clip_id,author_id,body) values(comment_e,post_d,f,'Isolated comment');
 insert into private.clip_likes(clip_id,user_id) values(post_d,f);
 insert into public.game_cards(user_id,game_id,player_name) values(d,'zenless-zone-zero','Isolated card');
 insert into storage.objects(bucket_id,name,owner_id) values('avatars',d||'/avatar.jpg',d::text),('clips',d||'/'||post_d||'/clip.mp4',d::text);
 set local role service_role;
 begin perform public.finish_account_deletion(d,sd);raise exception 'finish ran before prepare';exception when insufficient_privilege then null;end;
 r:=public.prepare_account_deletion(d,sd);
 assert jsonb_array_length(r->'objects')=2,'manifest includes only current account files';
 r:=public.prepare_account_deletion(d,sd);
 assert jsonb_array_length(r->'objects')=2,'disabled reservation still permits the deletion driver to retry';
 begin perform public.finish_account_deletion(d,sd);raise exception 'outstanding files ignored';exception when object_not_in_prerequisite_state then null;end;
 reset role;
 assert (select not enabled from private.development_accounts where user_id=d),'access code permanently retired';
 assert private.development_login_context(hash) is null,'retired access code cannot log in or provision again';
 assert exists(select 1 from auth.sessions where id=sd),'deletion driver survives for retry';
 assert not exists(select 1 from auth.sessions where id=second_d),'other development sessions revoked';
 assert not private.account_is_eligible(d),'deleting development user cannot access business data';
 begin insert into storage.objects(bucket_id,name,owner_id) values('avatars',d||'/late.jpg',d::text);raise exception 'new upload accepted';exception when insufficient_privilege then null;end;
 -- Reassign only these rollback fixture metadata rows to model physical removal.
 -- Production object cleanup always uses the Storage API and rechecks ownership.
 update storage.objects set owner_id=fake::text,owner=null where owner_id=d::text;
 set local role service_role;
 r:=public.finish_account_deletion(d,sd);
 assert r='{"deleted":true}'::jsonb,'development completion returned';
 reset role;
 assert not exists(select 1 from auth.users where id=d),'development Auth parent hard deleted';
 assert not exists(select 1 from public.profiles where id=d),'profile removed';
 assert not exists(select 1 from public.game_cards where user_id=d),'game card removed';
 assert not exists(select 1 from auth.sessions where user_id=d),'Auth sessions removed';
 assert not exists(select 1 from public.video_posts where id=post_d),'uploaded post removed';
 assert not exists(select 1 from private.video_reviews where id=review_d),'post review cascades';
 assert not exists(select 1 from private.clip_comments where id=comment_e),'post comments cascade';
 assert not exists(select 1 from private.clip_likes where clip_id=post_d),'post likes cascade';
 assert exists(select 1 from private.development_accounts where user_id=d and not enabled),'retired reservation survives hard deletion';
 begin insert into auth.users(id,aud,role,email,email_confirmed_at) values(d,'authenticated','authenticated',dev_email,now());raise exception 'retired UUID recreated';exception when insufficient_privilege then null;end;
 begin insert into auth.users(id,aud,role,email) values(gen_random_uuid(),'authenticated','authenticated',dev_email);raise exception 'retired email recreated';exception when insufficient_privilege then null;end;
 assert not has_function_privilege('authenticated','public.prepare_account_deletion(uuid,uuid)','execute'),'client cannot pick deletion target';
 assert not has_function_privilege('anon','public.finish_account_deletion(uuid,uuid)','execute'),'public cannot finalize';
 assert not has_function_privilege('service_role','private.require_account_deletion(uuid,uuid)','execute'),'internal guard is not directly exposed';
 assert has_function_privilege('service_role','public.prepare_account_deletion(uuid,uuid)','execute'),'verified Edge service can prepare';
end $test$;
rollback;
