-- Synthetic authenticated identities and content; every row rolls back.
begin;
do $test$
declare
    a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();d uuid:=gen_random_uuid();
    sa uuid:=gen_random_uuid();sb uuid:=gen_random_uuid();sd uuid:=gen_random_uuid();
    post_a uuid:=gen_random_uuid();post_d uuid:=gen_random_uuid();pending uuid:=gen_random_uuid();
    rejected uuid:=gen_random_uuid();comment_a uuid:=gen_random_uuid();comment_b uuid:=gen_random_uuid();comment_d uuid:=gen_random_uuid();
    r jsonb;
begin
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
        values(d,'fixture-'||d||'@development.invalid','Clip social fixture',
            encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
    insert into auth.users(id,aud,role,is_anonymous) values
        (a,'authenticated','authenticated',true),(b,'authenticated','authenticated',true);
    insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous)
        values(d,'authenticated','authenticated','fixture-'||d||'@development.invalid',now(),false);
    insert into auth.identities(provider_id,user_id,identity_data,provider)
        values(d::text,d,jsonb_build_object('sub',d),'email');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b),(sd,d);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'anonymous',now(),now()),(gen_random_uuid(),sb,'anonymous',now(),now()),
        (gen_random_uuid(),sd,'password',now(),now());
    insert into public.video_posts(id,owner_id,game_id,video_path,status,approved_at) values
        (post_a,a,'zenless-zone-zero',a||'/'||post_a||'/video.mp4','approved',now()),
        (post_d,d,'zenless-zone-zero',d||'/'||post_d||'/video.mp4','approved',now()),
        (pending,a,'zenless-zone-zero',a||'/'||pending||'/video.mp4','pending',null),
        (rejected,a,'zenless-zone-zero',a||'/'||rejected||'/video.mp4','rejected',null);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    r:=public.clip_social_state(post_a);
    assert r->'uploader'->>'id'=a::text,'permitted real uploader returned';
    assert r->>'like_count'='0' and r->>'comment_count'='0' and r->>'is_liked'='false','no fabricated counts';
    r:=public.set_clip_liked(post_a,true);
    assert r->>'like_count'='1' and r->>'is_liked'='true','confirmed like persisted';
    r:=public.set_clip_liked(post_a,true);
    assert r->>'like_count'='1','set-like retry does not double count';
    perform public.set_clip_liked(post_a,false);
    r:=public.set_clip_liked(post_a,false);
    assert r->>'like_count'='0' and r->>'is_liked'='false','unlike retry is idempotent';
    r:=public.add_clip_comment(post_a,comment_a,'  First comment  ');
    assert r->>'status'='pending' and r->>'body'='First comment','server trims and holds pending';
    assert r->'author'->>'id'=a::text,'server assigns actual author';
    perform public.add_clip_comment(post_a,comment_a,'First comment');
    assert jsonb_array_length(public.clip_comments(post_a))=1,'retry same ID returns one pending comment';
    assert public.clip_social_state(post_a)->>'comment_count'='0','pending not in approved public count';
    begin perform public.add_clip_comment(post_a,comment_a,'Altered body');raise exception 'same UUID accepted changed body';exception when invalid_parameter_value then null;end;
    begin perform public.add_clip_comment(post_a,gen_random_uuid(),E' \t\n');raise exception 'whitespace comment accepted';exception when invalid_parameter_value then null;end;
    begin perform public.add_clip_comment(pending,gen_random_uuid(),'Pending target');raise exception 'pending post accepted interaction';exception when insufficient_privilege then null;end;
    begin perform public.set_clip_liked(rejected,true);raise exception 'rejected post accepted like';exception when insufficient_privilege then null;end;
    begin perform public.set_clip_liked(gen_random_uuid(),true);raise exception 'missing post accepted like';exception when insufficient_privilege then null;end;
    -- Approved editorial clips are visible, but their cross-cohort account is not.
    r:=public.set_clip_liked(post_d,true);
    assert r->'uploader'='null'::jsonb and r->>'like_count'='1','experience exception retains private development uploader';
    reset role;
    assert (select count(*) from private.clip_comments where id=comment_a)=1,'one actual comment row';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert jsonb_array_length(public.clip_comments(post_a))=0,'peer cannot see pending';
    perform public.delete_clip_comment(comment_a);
    r:=public.add_clip_comment(post_a,comment_b,'Peer comment');
    reset role;
    assert exists(select 1 from private.clip_comments where id=comment_a),'peer cannot delete another author comment';
    update private.clip_comments set status='approved',approved_at=now() where id in (comment_a,comment_b);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    assert jsonb_array_length(public.clip_comments(post_a))=2,'reviewed same-cohort comments published';
    assert public.clip_social_state(post_a)->>'comment_count'='2','approved count reflects real rows';
    perform public.block_user(b);
    assert jsonb_array_length(public.clip_comments(post_a))=1,'blocked author excluded';
    assert public.clip_social_state(post_a)->>'comment_count'='1','blocked author not counted';
    perform public.delete_clip_comment(comment_a);
    assert public.clip_social_state(post_a)->>'comment_count'='0','own delete refreshes approved count';
    perform public.delete_clip_comment(comment_a);
    begin perform public.add_clip_comment(post_a,comment_a,'First comment');raise exception 'retry resurrected deleted comment';
    exception when invalid_parameter_value then assert sqlerrm='comment_deleted','deleted retry remains deleted';end;
    reset role;
    assert (select status='deleted' and body='' and approved_at is null from private.clip_comments where id=comment_a),'delete erases content and leaves dedupe only';
    set local role authenticated;
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb,'is_anonymous',true)::text,true);
    set local role authenticated;
    begin perform public.set_clip_liked(post_a,true);raise exception 'blocked peer interacted';exception when insufficient_privilege then null;end;
    begin perform public.clip_comments(post_a);raise exception 'blocked peer read comments';exception when insufficient_privilege then null;end;
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',d,'role','authenticated','session_id',sd,'is_anonymous',false)::text,true);
    set local role authenticated;
    r:=public.set_clip_liked(post_d,true);
    assert r->>'like_count'='1','development count excludes production likes';
    assert r->'uploader'->>'id'=d::text,'development author visible within cohort';
    perform public.add_clip_comment(post_d,comment_d,'Development-only comment');
    begin perform public.clip_social_state(post_a);raise exception 'cross cohort social access granted';exception when insufficient_privilege then null;end;
    reset role;
    update private.clip_comments set status='approved',approved_at=now() where id=comment_d;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text,true);
    set local role authenticated;
    r:=public.clip_social_state(post_d);
    assert r->>'like_count'='1' and r->>'is_liked'='true','production count excludes development likes';
    assert r->>'comment_count'='0' and jsonb_array_length(public.clip_comments(post_d))=0,'development comments remain isolated';
    reset role;
    update auth.sessions set not_after=now()-interval '1 second' where id=sa;
    set local role authenticated;
    begin perform public.clip_social_state(post_d);raise exception 'revoked session read interactions';exception when insufficient_privilege then null;end;
    reset role;
    assert not has_table_privilege('authenticated','private.clip_likes','select'),'no direct like directory';
    assert not has_table_privilege('authenticated','private.clip_comments','insert'),'cannot bypass comment review';
    assert not has_table_privilege('authenticated','private.clip_comments','update'),'cannot self approve';
    assert not has_function_privilege('anon','public.set_clip_liked(uuid,boolean)','execute'),'unauthenticated mutation denied';
    assert not has_function_privilege('authenticated','private.clip_comment_json(private.clip_comments)','execute'),'internal JSON helper not callable';
end $test$;
rollback;
