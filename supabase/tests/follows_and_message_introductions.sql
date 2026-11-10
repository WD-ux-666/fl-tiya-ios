-- All identities, sessions, follows, conversations, messages and quota receipts
-- are synthetic and rolled back. This makes no changes to existing users.
begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();d uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid();sb uuid:=gen_random_uuid();sc uuid:=gen_random_uuid();sd uuid:=gen_random_uuid();
 conv uuid;old_conv uuid;second_conv uuid;req uuid;mid uuid:=gen_random_uuid();friend_mid uuid:=gen_random_uuid();r jsonb;
begin
 insert into auth.users(id,aud,role) values(a,'authenticated','authenticated'),(b,'authenticated','authenticated'),(c,'authenticated','authenticated');
 insert into private.development_accounts(user_id,email,label,code_hash,expires_at)
 values(d,'fixture-'||d||'@development.invalid','Follow messaging fixture',encode(extensions.digest(d::text,'sha256'),'hex'),now()+interval '1 hour');
 insert into auth.users(id,aud,role,email,email_confirmed_at) values(d,'authenticated','authenticated','fixture-'||d||'@development.invalid',now());
 insert into auth.identities(provider_id,user_id,identity_data,provider) values
 (a::text,a,jsonb_build_object('sub',a),'apple'),(b::text,b,jsonb_build_object('sub',b),'apple'),(c::text,c,jsonb_build_object('sub',c),'apple'),
 (d::text,d,jsonb_build_object('sub',d),'email');
 insert into auth.sessions(id,user_id) values(sa,a),(sb,b),(sc,c),(sd,d);
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
 (gen_random_uuid(),sa,'oauth',now(),now()),(gen_random_uuid(),sb,'oauth',now(),now()),(gen_random_uuid(),sc,'oauth',now(),now());
 assert not has_table_privilege('authenticated','private.message_introductions','insert'),'no direct quota writes';
 assert not has_table_privilege('authenticated','private.message_receipts','delete'),'cannot erase receipts';
 assert not has_table_privilege('authenticated','private.player_follows','select'),'follows private';
 assert not has_function_privilege('anon','public.open_direct_conversation(uuid)','execute'),'anon cannot open chat';
 assert not has_function_privilege('authenticated','private.require_social_peer(uuid)','execute'),'internal helper not callable';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
 set local role authenticated;
 assert public.player_follow_state(b)->>'is_following'='false','unfollowed initially';
 r:=public.set_player_followed(b,true);
 assert r->>'is_following'='true' and r->>'follower_count'='1','follow persisted';
 assert public.set_player_followed(b,true)=r,'follow retry idempotent';
 begin perform public.set_player_followed(a,true);raise exception 'self follow allowed';exception when invalid_parameter_value then null;end;
 begin perform public.send_friend_request(a);raise exception 'self friend allowed';exception when invalid_parameter_value then null;end;
 begin perform public.open_direct_conversation(a);raise exception 'self message allowed';exception when invalid_parameter_value then null;end;
 begin perform public.set_player_followed(d,true);raise exception 'cross cohort follow';exception when insufficient_privilege then null;end;
 begin perform public.open_direct_conversation(d);raise exception 'cross cohort chat';exception when insufficient_privilege then null;end;
 conv:=(public.open_direct_conversation(b)->>'id')::uuid;
 assert (public.open_direct_conversation(b)->>'id')::uuid=conv,'open chat retry preserves ID';
 assert public.conversation_messaging_state(conv)->>'is_friend'='false','follow is not friendship';
 assert public.conversation_messaging_state(conv)->>'can_send'='true','first intro available';
 reset role;
 begin perform public.call_action(a,sa,'create',null,b,'voice');raise exception 'follow or chat unlocked call';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 set local role authenticated;
 perform public.send_message(conv,mid,E'  First hello \n');
 assert public.conversation_messaging_state(conv)->>'has_sent_introduction'='true','intro spent';
 assert public.conversation_messaging_state(conv)->>'can_send'='false','stranger composer locked';
 assert public.send_message(conv,mid,'First hello')->>'id'=mid::text,'same UUID retry acknowledged';
 begin perform public.send_message(conv,mid,'Changed');raise exception 'changed retry allowed';exception when invalid_parameter_value then null;end;
 begin perform public.send_message(conv,gen_random_uuid(),'Second');raise exception 'second intro allowed';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 begin perform public.send_message(conv,gen_random_uuid(),E' \n\t');raise exception 'blank accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id',sc)::text,true);
 assert not exists(select 1 from public.conversations where id=conv),'outsider cannot read chat';
 assert not exists(select 1 from public.messages where conversation_id=conv),'outsider cannot read messages';
 begin perform public.send_message(conv,gen_random_uuid(),'Intrude');raise exception 'outsider sent';exception when insufficient_privilege then null;end;
 begin perform public.conversation_messaging_state(conv);raise exception 'outsider inspected state';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
 assert public.conversation_messaging_state(conv)->>'can_send'='true','reverse direction has independent quota';
 perform public.send_message(conv,gen_random_uuid(),'My intro');
 begin perform public.send_message(conv,gen_random_uuid(),'My second');raise exception 'reverse second allowed';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 assert (select count(*) from public.messages where conversation_id=conv)=2,'one actual intro each';
 req:=(public.send_friend_request(a)->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
 r:=public.respond_friend_request(req,true);
 assert (r->>'conversation_id')::uuid=conv,'friend accept opens same intro chat';
 assert public.conversation_messaging_state(conv)->>'can_send'='true','friends unrestricted';
 perform public.send_message(conv,gen_random_uuid(),'Friend message 1');
 perform public.send_message(conv,gen_random_uuid(),'Friend message 2');
 perform public.remove_friend(b);
 begin perform public.send_message(conv,gen_random_uuid(),'After unfriend');raise exception 'unfriend reset quota';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 perform public.block_user(b);
 assert not exists(select 1 from public.messages where conversation_id=conv),'block hides text';
 begin perform public.send_message(conv,mid,'First hello');raise exception 'blocked retry visible';exception when insufficient_privilege then null;end;
 begin perform public.open_direct_conversation(b);raise exception 'blocked open allowed';exception when insufficient_privilege then null;end;
 begin perform public.set_player_followed(b,true);raise exception 'blocked follow';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
 begin perform public.open_direct_conversation(a);raise exception 'reverse blocked open';exception when insufficient_privilege then null;end;
 reset role;
 assert not exists(select 1 from private.player_follows where follower_id=a and followed_id=b),'block removes follows';
 set local role authenticated;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
 perform public.unblock_user(b);
 begin perform public.send_message(conv,gen_random_uuid(),'After unblock');raise exception 'unblock reset quota';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 reset role;
 delete from public.messages where id=mid;
 set local role authenticated;
 perform public.send_message(conv,mid,'First hello');
 assert not exists(select 1 from public.messages where id=mid),'deleted intro retry does not resurrect';
 reset role;
 old_conv:=conv;
 delete from public.conversations where id=conv;
 set local role authenticated;
 conv:=(public.open_direct_conversation(b)->>'id')::uuid;
 assert conv<>old_conv,'new conversation created';
 assert public.conversation_messaging_state(conv)->>'can_send'='false','conversation deletion never resets pair quota';
 perform public.send_message(conv,mid,'First hello');
 assert not exists(select 1 from public.messages where conversation_id=conv),'retry after new chat does not redeliver';
 begin perform public.send_message(conv,gen_random_uuid(),'Fresh intro');raise exception 'history reset quota';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 -- Friends who have never used an introduction retain exactly one after removal.
 req:=(public.send_friend_request(c)->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id',sc)::text,true);
 second_conv:=(public.respond_friend_request(req,true)->>'conversation_id')::uuid;
 perform public.send_message(second_conv,friend_mid,'Friend before intro');
 perform public.send_message(second_conv,gen_random_uuid(),'Another friend message');
 perform public.remove_friend(a);
 assert public.conversation_messaging_state(second_conv)->>'can_send'='true','friend sends do not consume intro';
 perform public.send_message(second_conv,gen_random_uuid(),'First nonfriend message');
 begin perform public.send_message(second_conv,gen_random_uuid(),'Second nonfriend');raise exception 'former friend second intro';exception when raise_exception then assert sqlerrm='stranger_message_limit';end;
 reset role;
 -- Deleting-state peers and actors are denied before messages/follows mutate.
 update private.accounts set state='deleting' where user_id=b;
 set local role authenticated;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
 begin perform public.open_direct_conversation(b);raise exception 'deleting peer open';exception when insufficient_privilege then null;end;
 begin perform public.set_player_followed(b,true);raise exception 'deleting peer follow';exception when insufficient_privilege then null;end;
 begin perform public.send_message(conv,mid,'First hello');raise exception 'deleting peer retry';exception when insufficient_privilege then null;end;
 reset role;
 update private.accounts set state='deleting' where user_id=a;
 set local role authenticated;
 begin perform public.open_direct_conversation(c);raise exception 'deleting actor open';exception when insufficient_privilege then null;end;
 reset role;
 -- The durable pair PK is a second concurrency guard in addition to the
 -- transaction-scoped advisory lock shared by send/accept/block/remove.
 assert exists(select 1 from pg_constraint where conrelid='private.message_introductions'::regclass and contype='p'),'pair unique constraint exists';
 assert (select count(*) from private.message_introductions where sender_id=a and recipient_id=b)=1,'one durable quota row';
 assert not exists(select 1 from public.messages where id=mid),'deleted payload stays erased';
end $test$;
rollback;
