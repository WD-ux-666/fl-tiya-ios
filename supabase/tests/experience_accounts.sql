-- Synthetic authorization fixtures. No live user/content mutation survives.
begin;
do $test$
declare
 e uuid:=gen_random_uuid(); f uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); fake uuid:=gen_random_uuid();
 se uuid:=gen_random_uuid(); sf uuid:=gen_random_uuid(); sp uuid:=gen_random_uuid(); sd uuid:=gen_random_uuid(); wrong uuid:=gen_random_uuid();
 approved uuid:=gen_random_uuid(); pending uuid:=gen_random_uuid(); rejected uuid:=gen_random_uuid(); ownpost uuid:=gen_random_uuid();
 conv uuid:=gen_random_uuid(); mid uuid:=gen_random_uuid(); guide_dev uuid:=gen_random_uuid(); guide_draft uuid:=gen_random_uuid(); r jsonb; cid uuid; n integer;
begin
 insert into private.development_accounts(user_id,email,label,code_hash,expires_at) values(d,'fixture-'||d||'@development.invalid','Experience content fixture',encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
 insert into auth.users(id,aud,role,is_anonymous,raw_user_meta_data) values
 (e,'authenticated','authenticated',true,'{"experience_email":"same@example.invalid","cohort":"development"}'),
 (f,'authenticated','authenticated',true,'{"experience_email":"same@example.invalid"}'),
 (p,'authenticated','authenticated',false,'{}'),
 (fake,'authenticated','authenticated',false,'{"is_experience":true,"is_anonymous":true}');
 insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous) values(d,'authenticated','authenticated','fixture-'||d||'@development.invalid',now(),false);
 insert into auth.identities(provider_id,user_id,identity_data,provider) values(p::text,p,jsonb_build_object('sub',p),'apple'),(d::text,d,jsonb_build_object('sub',d),'email');
 insert into auth.sessions(id,user_id) values(se,e),(sf,f),(sp,p),(sd,d),(wrong,e);
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),se,'anonymous',now(),now()),(gen_random_uuid(),sf,'anonymous',now(),now()),(gen_random_uuid(),sp,'oauth',now(),now()),(gen_random_uuid(),sd,'password',now(),now()),(gen_random_uuid(),wrong,'password',now(),now());
 assert (select is_experience and cohort='production' from private.accounts where user_id=e),'Auth anonymous creation attests immutable production experience';
 assert (select is_experience from private.accounts where user_id=f),'same unverified email creates independent account';
 assert not (select is_experience from private.accounts where user_id=fake),'editable metadata cannot attest experience';
 assert not private.account_is_eligible(fake),'ordinary identity-less account remains ineligible';
 begin update private.accounts set is_experience=false where user_id=e; raise exception 'experience flag changed'; exception when insufficient_privilege then null; end;
 assert private.call_session_active(e,se),'real experience anonymous session supports calls';
 assert not private.call_session_active(e,wrong),'password session cannot impersonate anonymous session';
 insert into public.video_posts(id,owner_id,game_id,video_path,thumbnail_path,status,approved_at) values
 (approved,d,'zenless-zone-zero',d||'/'||approved||'/video.mp4',d||'/'||approved||'/cover.jpg','approved',now()),
 (pending,d,'zenless-zone-zero',d||'/'||pending||'/video.mp4',null,'pending',null),
 (rejected,d,'zenless-zone-zero',d||'/'||rejected||'/video.mp4',null,'rejected',null),
 (ownpost,e,'zenless-zone-zero',e||'/'||ownpost||'/video.mp4',null,'pending',null);
 update public.profiles set avatar_path=d||'/avatar.jpg' where id=d;
 insert into public.game_cards(user_id,game_id,player_name) values(d,'zenless-zone-zero','Private development card'),(e,'zenless-zone-zero','Own experience card');
 insert into storage.objects(bucket_id,name,owner_id) values('clips',d||'/'||approved||'/video.mp4',d::text),('clips',d||'/'||approved||'/cover.jpg',d::text),('clips',d||'/'||pending||'/video.mp4',d::text),('clips',d||'/unreferenced.mp4',d::text),('avatars',d||'/avatar.jpg',d::text),('clips',e||'/'||ownpost||'/video.mp4',e::text);
 insert into public.friendships(user_low,user_high) values(least(e,d),greatest(e,d)),(least(e,f),greatest(e,f));
 insert into public.conversations(id,user_low,user_high) values(conv,least(e,d),greatest(e,d));
 insert into public.messages(id,conversation_id,sender_id,body) values(mid,conv,d,'Private development message');
 insert into public.guides(id,game_id,title,source_url,source_name,attribution,status,published_at,cohort) values
 (guide_dev,'zenless-zone-zero','Published development reference','https://example.invalid/reference','Fixture','Fixture attribution','published',now(),'development'),
 (guide_draft,'zenless-zone-zero','Draft development reference','https://example.invalid/draft','Fixture','Fixture attribution','draft',null,'development');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','session_id',se,'is_anonymous',true)::text,true);
 set local role authenticated;
 r:=public.session_context();
 assert r->>'user_id'=e::text and r->>'cohort'='production' and r->>'is_experience'='true','server context attests experience';
 assert (select count(*) from public.video_posts where id in (approved,pending,rejected))=1,'only approved development content exception';
 assert (select count(*) from public.profiles where id=d)=0,'development author profile remains private';
 assert (select count(*) from public.game_cards where user_id=d)=0,'development game cards remain private';
 assert (select count(*) from public.messages where id=mid)=0,'development messages remain private';
 assert (select count(*) from public.friendships where e in (user_low,user_high))=1,'only production friendship is visible';
 assert (select count(*) from public.game_cards where user_id=e)=1,'experience own card visible';
 assert (select count(*) from public.guides where id in (guide_dev,guide_draft))=1,'experience reads published development guides only';
 begin perform public.send_friend_request(d); raise exception 'cross cohort request permitted'; exception when insufficient_privilege then null; end;
 perform set_config('storage.operation','storage.object.get_authenticated',true);
 assert (select count(*) from storage.objects where name in (d||'/'||approved||'/video.mp4',d||'/'||approved||'/cover.jpg'))=2,'approved exact video and cover readable';
 assert (select count(*) from storage.objects where name in (d||'/'||pending||'/video.mp4',d||'/unreferenced.mp4',d||'/avatar.jpg'))=0,'pending arbitrary and avatar files remain private';
 perform set_config('storage.operation','storage.object.list',true);
 assert (select count(*) from storage.objects where name like d||'/%')=0,'experience does not gain storage listing';
 r:=public.payment_state();
 assert r->>'purchases_enabled'='false' and r->>'purchase_unavailable_reason'='experience_account','anonymous checkout disabled';
 reset role;
 -- A forged claim cannot replace actual session AMR or actual Auth anonymity.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','session_id',wrong,'is_anonymous',true)::text,true);
 assert not private.actor_is_active(),'wrong real session AMR denied';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','session_id',se,'is_anonymous',false)::text,true);
 assert not private.actor_is_active(),'anonymous JWT mismatch denied';
 update auth.sessions set not_after=now()-interval '1 second' where id=se;
 assert not private.call_session_active(e,se),'expired anonymous DB session denied';
 update auth.sessions set not_after=null where id=se;
 -- Even an attached Apple identity and OAuth AMR cannot authorize payment for
 -- a server-attested experience account.
 insert into auth.identities(provider_id,user_id,identity_data,provider) values(e::text,e,jsonb_build_object('sub',e),'apple');
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values(gen_random_uuid(),se,'oauth',now(),now());
 set local role service_role;
 begin perform public.credit_apple_purchase(e,se,'Production','999999999999','fixture',e);raise exception 'anonymous purchase credited';exception when insufficient_privilege then null;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated','session_id',sp,'is_anonymous',false)::text,true);
 set local role authenticated;
 assert (public.session_context()->>'is_experience')='false','Apple context not experience';
 assert (select count(*) from public.video_posts where id=approved)=0,'Apple users do not receive development content exception';
 assert (select count(*) from public.guides where id=guide_dev)=0,'Apple users do not receive development guide exception';
 reset role;
 -- The synthetic Apple identity above tested payment rejection. A linked Apple
 -- account must now be rejected by both deletion entry points until revocation
 -- is configured, so restore the anonymous-only fixture before its cleanup test.
 delete from auth.identities where user_id=e and provider='apple';
 -- Current-only deletion is service-only; marking deleting closes calls and
 -- queues RTC cleanup before any external object cleanup. Repeats are safe.
 set local role service_role;
 r:=public.call_action(e,se,'create',null,f,'voice');cid:=(r->'call'->>'id')::uuid;
 perform public.call_action(f,sf,'accept',cid);
 r:=public.prepare_experience_deletion(e,se);
 assert r->>'user_id'=e::text and jsonb_array_length(r->'objects')=1,'deletion manifest contains only current own objects';
 r:=public.prepare_experience_deletion(e,se);
 assert r->>'user_id'=e::text,'deleting account retries with retained current anonymous session';
 reset role;
 assert (select state='deleting' from private.accounts where user_id=e),'deletion disables app access';
 assert (select status='ended' from private.calls where id=cid),'deletion closes accepted call';
 assert exists(select 1 from private.call_cleanup where call_id=cid),'deletion schedules durable RTC cleanup';
 assert not exists(select 1 from auth.sessions where id=wrong),'other sessions revoked';
 assert exists(select 1 from auth.sessions where id=se),'current deletion session remains for retry';
 begin insert into storage.objects(bucket_id,name,owner_id) values('avatars',e||'/late-upload.png',e::text);raise exception 'deleting account admitted an upload';exception when insufficient_privilege then null;end;
 set local role service_role;
 begin perform public.finish_experience_deletion(e,se);raise exception 'deleted with outstanding objects';exception when object_not_in_prerequisite_state then null;end;
 begin perform public.prepare_experience_deletion(p,sp);raise exception 'Apple deletion accepted';exception when insufficient_privilege then null;end;
 begin perform public.prepare_experience_deletion(f,se);raise exception 'wrong user session deletion accepted';exception when insufficient_privilege then null;end;
 reset role;
 -- Only synthetic metadata is reassigned to model an empty ownership set.
 -- Physical object removal is verified separately through the real Storage API.
 update storage.objects set owner_id=fake::text,owner=null where owner_id=e::text;
 set local role service_role;
 r:=public.finish_experience_deletion(e,se);
 assert r='{"deleted":true}'::jsonb,'completed deletion response';
 reset role;
 assert not exists(select 1 from auth.users where id=e),'Auth user hard deleted';
 assert not exists(select 1 from auth.sessions where user_id=e),'Auth sessions cascade';
 assert not exists(select 1 from public.profiles where id=e),'profile cascade';
 assert not exists(select 1 from public.game_cards where user_id=e),'game cards cascade';
 assert not exists(select 1 from public.friendships where e in (user_low,user_high)),'friendship cascade';
 assert not exists(select 1 from public.conversations where id=conv),'conversation cascade';
 assert not exists(select 1 from public.messages where id=mid),'message cascade';
 assert exists(select 1 from private.call_cleanup where call_id=cid),'cleanup survives hard deletion';
 assert exists(select 1 from auth.users where id=f),'independent account with same metadata email unaffected';
 assert not has_function_privilege('authenticated','public.prepare_experience_deletion(uuid,uuid)','execute'),'clients cannot choose deletion actor';
 assert not has_function_privilege('anon','public.finish_experience_deletion(uuid,uuid)','execute'),'public cannot invoke hard deletion';
end $test$;
rollback;
