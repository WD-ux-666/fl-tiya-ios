-- Synthetic actors, content, and Storage metadata. No fixture leaves the transaction.
begin;
set local plpgsql.check_asserts = on;

do $test$
declare
    a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); d uuid:=gen_random_uuid();
    sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid();
    clip_a uuid:=gen_random_uuid(); clip_b uuid:=gen_random_uuid(); sibling_b uuid:=gen_random_uuid(); editorial uuid:=gen_random_uuid();
    comment_b uuid:=gen_random_uuid(); sibling_comment_b uuid:=gen_random_uuid(); comment_c uuid:=gen_random_uuid();
    convo uuid; msg uuid:=gen_random_uuid(); pending_call uuid;
    vid_b text:=b||'/'||clip_b||'/video.mp4'; cover_b text:=b||'/'||clip_b||'/cover.jpg';
    vid_d text:=d||'/'||editorial||'/video.mp4'; avatar_b text:=b||'/avatar.jpg';
    handle_b text:='player_'||replace(b::text,'-','');
    dev_email text:='report-fixture-'||d||'@development.invalid';
    claims_a text:=jsonb_build_object('sub',a,'role','authenticated','session_id',sa,'is_anonymous',true)::text;
    claims_b text:=jsonb_build_object('sub',b,'role','authenticated','session_id',sb,'is_anonymous',true)::text;
    claims_c text:=jsonb_build_object('sub',c,'role','authenticated','session_id',sc,'is_anonymous',true)::text;
begin
    insert into auth.users(id,aud,role,is_anonymous) values
        (a,'authenticated','authenticated',true),(b,'authenticated','authenticated',true),(c,'authenticated','authenticated',true);
    insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
        values(d,dev_email,'Report visibility fixture',encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
    insert into auth.users(id,aud,role,email,email_confirmed_at,is_anonymous)
        values(d,'authenticated','authenticated',dev_email,now(),false);
    insert into auth.identities(provider_id,user_id,identity_data,provider)
        values(d::text,d,jsonb_build_object('sub',d),'email');
    insert into auth.sessions(id,user_id) values(sa,a),(sb,b),(sc,c);
    insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
        (gen_random_uuid(),sa,'anonymous',now(),now()),(gen_random_uuid(),sb,'anonymous',now(),now()),
        (gen_random_uuid(),sc,'anonymous',now(),now());
    insert into public.friendships(user_low,user_high) values(least(a,b),greatest(a,b));
    insert into public.conversations(user_low,user_high) values(least(a,b),greatest(a,b)) returning id into convo;
    insert into public.messages(id,conversation_id,sender_id,body) values(msg,convo,b,'Synthetic conversation message');
    insert into public.game_cards(user_id,game_id,player_name) values(b,'zenless-zone-zero','Report fixture player');
    update public.profiles set avatar_path=avatar_b where id=b;
    insert into public.video_posts(id,owner_id,game_id,video_path,thumbnail_path,status,approved_at) values
        (clip_a,a,'zenless-zone-zero',a||'/'||clip_a||'/video.mp4',null,'approved',now()),
        (clip_b,b,'zenless-zone-zero',vid_b,cover_b,'approved',now()),
        (sibling_b,b,'zenless-zone-zero',b||'/'||sibling_b||'/video.mp4',null,'approved',now()),
        (editorial,d,'zenless-zone-zero',vid_d,null,'approved',now());
    insert into storage.objects(bucket_id,name,owner_id) values
        ('clips',vid_b,b::text),('clips',cover_b,b::text),('clips',vid_d,d::text),('avatars',avatar_b,b::text);
    insert into private.clip_comments(id,clip_id,author_id,body,status,approved_at) values
        (comment_b,clip_a,b,'First B comment','approved',now()),
        (sibling_comment_b,clip_a,b,'Second B comment','approved',now()),
        (comment_c,clip_a,c,'C comment','approved',now());
    insert into private.clip_likes(clip_id,user_id) values(clip_a,b),(clip_a,c);
    pending_call:=(public.call_action(b,sb,'create',null,a,'voice')->'call'->>'id')::uuid;

    perform set_config('request.jwt.claims',claims_a,true);
    perform set_config('storage.operation','storage.object.get_authenticated',true);
    set local role authenticated;
    assert exists(select 1 from public.video_posts where id=clip_b),'A can see B clip before report';
    assert (select count(*) from storage.objects where name in(vid_b,cover_b))=2,'A can open clip and cover before report';
    assert jsonb_array_length(public.clip_comments(clip_a))=3,'A sees all comments before reporting';
    assert public.submit_content_report('video',clip_b,'spam'),'Report visible video';
    assert not exists(select 1 from public.video_posts where id=clip_b),'Reported video hidden from the reporter';
    assert not exists(select 1 from storage.objects where name in(vid_b,cover_b)),'Reported video and cover can no longer be downloaded';
    assert exists(select 1 from public.video_posts where id=sibling_b),'Reporting a video does not hide other videos';
    begin
        perform public.clip_social_state(clip_b);
        raise exception 'Reported clip still returned social metadata';
    exception when insufficient_privilege then assert sqlerrm='clip_unavailable'; end;
    assert not public.submit_content_report('video',clip_b,'spam'),'Retry succeeds without another report';
    assert public.submit_content_report('comment',comment_b,'harassment'),'Report visible comment';
    assert jsonb_array_length(public.clip_comments(clip_a))=2,'Only reported comment removed';
    assert not public.clip_comments(clip_a) @> jsonb_build_array(jsonb_build_object('id',comment_b)), 'Reported comment no longer returned';
    assert public.clip_social_state(clip_a)->>'comment_count'='2','Visible comment count tracks exact hides';
    assert exists(select 1 from public.profiles where id=b),'Item reports do not hide its author';
    assert exists(select 1 from storage.objects where name=vid_d),'Curated clip remains visible to experience user';
    assert public.submit_content_report('video',editorial,'inappropriate'),'Visible cross-cohort clip can be reported';
    assert not exists(select 1 from public.video_posts where id=editorial),'Curated exception honors a video report';
    assert not exists(select 1 from storage.objects where name=vid_d),'Curated media download honors a video report';

    assert public.submit_content_report('conversation',b,'harassment'),'Report player in a direct conversation';
    assert not exists(select 1 from public.profiles where id=b),'Reported player profile hidden';
    assert not exists(select 1 from public.game_cards where user_id=b),'Reported player cards hidden';
    assert not exists(select 1 from public.discover_community_players('zenless-zone-zero',handle_b)), 'Reported player removed from community discovery';
    assert not exists(select 1 from public.discover_players(handle_b)), 'Reported player removed from player search';
    assert not exists(select 1 from storage.objects where name=avatar_b),'Reported player avatar hidden';
    assert not exists(select 1 from public.video_posts where id=sibling_b),'Reported player videos hidden';
    assert not exists(select 1 from public.conversations where id=convo),'Reported player conversation hidden';
    assert not exists(select 1 from public.messages where id=msg),'Reported player message hidden';
    assert jsonb_array_length(public.clip_comments(clip_a))=1,'Reported player other comments hidden';
    assert public.clip_social_state(clip_a)->>'comment_count'='1','Reported player removed from comment count';
    assert public.clip_social_state(clip_a)->>'like_count'='1','Reported player removed from like count';
    assert not exists(select 1 from public.list_blocked_players() where id=b),'Report is separate from explicit block';
    begin
        perform public.open_direct_conversation(b);
        raise exception 'Reported player conversation reopened';
    exception when insufficient_privilege then assert sqlerrm='user_unavailable'; end;
    begin
        perform public.submit_content_report('video',sibling_b,'spam');
        raise exception 'Never-reported hidden clip was reportable';
    exception when insufficient_privilege then assert sqlerrm='report_target_unavailable'; end;
    reset role;

    assert public.call_action(a,sa,'state')->'call'='null'::jsonb,'Reported peer cannot appear as an incoming call';
    assert public.call_action(a,sa,'state',pending_call)->'call'='null'::jsonb,'Reporter cannot reopen hidden peer call status';
    assert (select status='missed' and ended_reason='relationship_unavailable' from private.calls where id=pending_call),
        'Existing call sweep marks a hidden incoming call unavailable';
    begin
        perform public.call_action(b,sb,'create',null,a,'voice');
        raise exception 'A reported peer could ring the reporter';
    exception when insufficient_privilege then assert sqlerrm='call_unavailable'; end;

    -- Moderator purges the reports; this must not clear the user's hiding choices.
    delete from private.content_reports where reporter_id=a;
    set local role authenticated;
    assert not public.submit_content_report('conversation',b,'harassment'),'Duplicate remains safe after moderation queue cleanup';
    assert not public.submit_content_report('video',clip_b,'spam'),'Video remains hidden and cannot be reported again after queue cleanup';
    perform public.block_user(b);
    assert exists(select 1 from public.list_blocked_players() where id=b),'Explicit block remains available for a reported peer';
    perform public.unblock_user(b);
    assert not exists(select 1 from public.list_blocked_players() where id=b),'Unblocking removes explicit block only';
    assert not exists(select 1 from public.profiles where id=b),'Unblocking does not undo report hiding';
    assert not exists(select 1 from public.video_posts where id=sibling_b),'Unblocking does not restore reported player clips';
    perform public.block_user(c);
    assert jsonb_array_length(public.clip_comments(clip_a))=0,'Block hides comments on other authors videos';
    perform public.unblock_user(c);
    assert jsonb_array_length(public.clip_comments(clip_a))=1,'Unblocking restores unrelated comments only';
    reset role;

    perform set_config('request.jwt.claims',claims_b,true);
    set local role authenticated;
    assert exists(select 1 from public.profiles where id=a),'Report is one-way for profile visibility';
    assert exists(select 1 from public.conversations where id=convo),'Other party keeps their chat history';
    assert exists(select 1 from public.video_posts where id=clip_b),'Original author still sees their clip';
    assert jsonb_array_length(public.clip_comments(clip_a))=3,'Reported author still sees comments';
    reset role;
    perform set_config('request.jwt.claims',claims_c,true);
    set local role authenticated;
    assert exists(select 1 from public.profiles where id=b),'Third-party profile visibility is unchanged';
    assert exists(select 1 from public.video_posts where id in(clip_b,sibling_b)),'Third-party video visibility is unchanged';
    assert exists(select 1 from storage.objects where name=vid_d),'Third-party curated access remains intact';
    assert public.clip_social_state(clip_a)->>'comment_count'='3','Third-party comment count stays unchanged';
    reset role;

    assert not has_table_privilege('authenticated','private.content_report_hides','select,insert,update,delete'), 'No client table access';
    assert not has_table_privilege('anon','private.content_report_hides','select,insert,update,delete'), 'No public table access';
    assert exists(select 1 from private.content_report_hides where viewer_id=a and target_id=clip_b), 'Hidden key independent of review queue';
    delete from auth.users where id=b;
    assert exists(select 1 from private.content_report_hides where viewer_id=a and target_id=clip_b), 'Other-user deletion cannot clear exact item hides';
    delete from auth.users where id=a;
    assert not exists(select 1 from private.content_report_hides where viewer_id=a), 'Own account deletion removes personal hides';
end $test$;
rollback;
