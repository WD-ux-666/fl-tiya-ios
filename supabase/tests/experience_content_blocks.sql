-- Synthetic metadata only, no uploaded bytes. The fixture transaction rolls back.
begin;
do $test$
declare e uuid:=gen_random_uuid();d uuid:=gen_random_uuid();se uuid:=gen_random_uuid();
 p uuid:=gen_random_uuid();object_name text;dev_email text:='fixture-content-'||d||'@development.invalid';
begin
 insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
 values(d,dev_email,'Content authorization fixture',encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
 insert into auth.users(id,aud,role,is_anonymous) values(e,'authenticated','authenticated',true);
 insert into auth.users(id,aud,role,email,email_confirmed_at) values(d,'authenticated','authenticated',dev_email,now());
 insert into auth.identities(provider_id,user_id,identity_data,provider) values(d::text,d,jsonb_build_object('sub',d),'email');
 insert into auth.sessions(id,user_id) values(se,e);
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
 values(gen_random_uuid(),se,'anonymous',now(),now());
 object_name:=d||'/'||p||'/video.mp4';
 insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at)
 values(p,d,'zenless-zone-zero',object_name,'approved',now());
 insert into storage.objects(bucket_id,name,owner_id) values('clips',object_name,d::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',e,'role','authenticated','session_id',se,'is_anonymous',true)::text,true);
 perform set_config('storage.operation','storage.object.get_authenticated',true);
 set local role authenticated;
 assert private.experience_can_read_post(p),'active imported catalog exception permits approved content';
 assert exists(select 1 from public.video_posts where id=p),'approved catalog row visible';
 assert exists(select 1 from storage.objects where name=object_name),'approved catalog bytes policy visible';
 assert not exists(select 1 from public.profiles where id=d),'exception does not expose development profile';
 reset role;
 update private.accounts set state='suspended' where user_id=d;
 set local role authenticated;
 assert not private.experience_can_read_post(p),'inactive author exception denied';
 assert not exists(select 1 from public.video_posts where id=p),'inactive author catalog row hidden';
 assert not exists(select 1 from storage.objects where name=object_name),'inactive author storage hidden';
 reset role;
 update private.accounts set state='active' where user_id=d;
 -- Cross-cohort blocks cannot be created through the public API. Direct seed
 -- exercises defense if an administrative import ever creates either pair.
 insert into public.blocks(owner_id,blocked_id) values(e,d);
 set local role authenticated;
 assert not private.experience_can_read_post(p),'own block denies exception';
 assert not exists(select 1 from public.video_posts where id=p),'own block hides feed row';
 assert not exists(select 1 from storage.objects where name=object_name),'own block hides storage';
 reset role;
 delete from public.blocks where owner_id=e and blocked_id=d;
 insert into public.blocks(owner_id,blocked_id) values(d,e);
 set local role authenticated;
 assert not private.experience_can_read_post(p),'reverse block denies exception';
 assert not exists(select 1 from public.video_posts where id=p),'reverse block hides feed row';
 assert not exists(select 1 from storage.objects where name=object_name),'reverse block hides storage';
 reset role;
end $test$;
rollback;
