-- Synthetic Auth/relationship/call fixtures only. ALWAYS rolled back. This
-- verifies SQL authority/state/outbox, not actual LiveKit networking or media.
begin;
do $test$
<<calls>>
declare
 a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid();sb uuid:=gen_random_uuid();so uuid:=gen_random_uuid();
 sa_other uuid:=gen_random_uuid();sb_other uuid:=gen_random_uuid();password_session uuid:=gen_random_uuid();
 d uuid:=gen_random_uuid();sd uuid:=gen_random_uuid();
 email_d text; call_id uuid; second_id uuid; result jsonb; jobs jsonb;worker_token text;call_snapshot jsonb;
begin
 email_d:='fixture-'||d::text||'@development.invalid';
 insert into private.development_accounts(user_id,email,label,code_hash,enabled,expires_at)
 values(d,email_d,'Call fixture',replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),true,now()+interval '1 hour');
 insert into auth.users(id,aud,role) values(a,'authenticated','authenticated'),(b,'authenticated','authenticated'),(outsider,'authenticated','authenticated');
 insert into auth.users(id,aud,role,email,email_confirmed_at) values(d,'authenticated','authenticated',email_d,now());
 insert into auth.identities(provider_id,user_id,identity_data,provider) values
 (a::text,a,jsonb_build_object('sub',a),'apple'),(b::text,b,jsonb_build_object('sub',b),'apple'),(outsider::text,outsider,jsonb_build_object('sub',outsider),'apple'),
 (d::text,d,jsonb_build_object('sub',d,'email',email_d),'email');
 insert into auth.sessions(id,user_id) values(sa,a),(sa_other,a),(password_session,a),(sb,b),(sb_other,b),(so,outsider),(sd,d);
 insert into auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at) values
 (gen_random_uuid(),sa,'oauth',now(),now()),(gen_random_uuid(),sa_other,'oauth',now(),now()),(gen_random_uuid(),sb,'oauth',now(),now()),(gen_random_uuid(),sb_other,'oauth',now(),now()),(gen_random_uuid(),so,'oauth',now(),now());
 assert not has_function_privilege('authenticated','public.call_action(uuid,uuid,text,uuid,uuid,text)','execute'),'client cannot forge Edge actor arguments';
 assert not has_function_privilege('anon','public.claim_call_cleanup(text)','execute'),'no anonymous cleanup';
 assert not has_table_privilege('authenticated','private.calls','select'),'calls not exposed through Data API';
 assert (select relrowsecurity from pg_class where oid='private.calls'::regclass),'call RLS enabled';
 begin perform public.call_action(a,gen_random_uuid(),'state');raise exception 'invented session allowed';exception when insufficient_privilege then assert sqlerrm='invalid_session';end;
 begin perform public.call_action(a,password_session,'state');raise exception 'non OAuth production session allowed';exception when insufficient_privilege then assert sqlerrm='invalid_session';end;
 begin perform public.call_action(a,sa,'create',null,b,'voice');raise exception 'stranger allowed';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 insert into public.friendships(user_low,user_high) values(least(a,b),greatest(a,b)),(least(a,outsider),greatest(a,outsider)),(least(a,d),greatest(a,d));
 begin perform public.call_action(a,sa,'create',null,d,'voice');raise exception 'cross cohort allowed';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 result:=public.call_action(a,sa,'create',null,b,'voice');call_id:=(result->'call'->>'id')::uuid;
 assert result->'call'->>'status'='ringing','create rings';assert not result?'room_name','no room exposed before accept';
 begin perform public.call_action(outsider,so,'state',call_id);raise exception 'outsider read allowed';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 begin perform public.call_action(a,sa,'accept',call_id);raise exception 'caller accepted own call';exception when insufficient_privilege then null;end;
 begin perform public.call_action(a,sa,'token',call_id);raise exception 'ringing token allowed';exception when raise_exception then assert sqlerrm='call_not_accepted';end;
 begin perform public.call_action(outsider,so,'create',null,a,'video');raise exception 'busy participant allowed';exception when unique_violation then assert sqlerrm='call_busy';end;
 assert public.call_action(b,sb,'state')->'call'->>'id'=call_id::text,'callee incoming state';
 assert public.call_action(b,sb_other,'state')->'call'->>'id'=call_id::text,'ringing available on another callee session';
 assert public.call_action(a,sa_other,'state')->'call'='null'::jsonb,'another caller session cannot discover ringing';
 assert public.call_action(a,sa_other,'state',call_id)->'call'='null'::jsonb,'explicit ringing state hidden from another caller session';
 select to_jsonb(c) into call_snapshot from private.calls c where id=call_id;
 begin perform public.call_action(a,sa_other,'end',call_id);raise exception 'another caller session cancelled ringing';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 assert (select to_jsonb(c)=call_snapshot from private.calls c where id=call_id),'unauthorized cancellation preserves ringing call';
 result:=public.call_action(b,sb,'accept',call_id);assert result->'call'->>'status'='accepted','callee accepts';
 update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id=sa;
 assert (select status='accepted' from private.calls where id=call_id),'session extension preserves call';
 select to_jsonb(c) into call_snapshot from private.calls c where id=call_id;
 assert public.call_action(a,sa,'state')->'call'->>'id'=call_id::text,'selected caller discovers accepted call';
 assert public.call_action(b,sb,'state',call_id)->'call'->>'id'=call_id::text,'selected callee reads accepted state';
 assert public.call_action(a,sa_other,'state')->'call'='null'::jsonb,'another caller session cannot discover accepted call';
 assert public.call_action(b,sb_other,'state')->'call'='null'::jsonb,'another callee session cannot discover accepted call';
 assert public.call_action(a,sa_other,'state',call_id)->'call'='null'::jsonb,'explicit accepted state hidden from another caller session';
 assert public.call_action(b,sb_other,'state',call_id)->'call'='null'::jsonb,'explicit accepted state hidden from another callee session';
 begin perform public.call_action(a,sa_other,'heartbeat',call_id);raise exception 'another caller session renewed heartbeat';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 begin perform public.call_action(b,sb_other,'token',call_id);raise exception 'another callee session joined';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 begin perform public.call_action(b,sb_other,'accept',call_id);raise exception 'stale callee accepted selected call';exception when raise_exception then assert sqlerrm='call_not_ringing';end;
 begin perform public.call_action(a,sa_other,'end',call_id);raise exception 'another caller session ended accepted call';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 begin perform public.call_action(b,sb_other,'end',call_id);raise exception 'stale callee cleanup ended selected call';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 assert (select to_jsonb(c)=call_snapshot from private.calls c where id=call_id),'other-session state and denied renewals preserve the selected call';
 result:=public.call_action(a,sa,'token',call_id);assert result->>'room_name' ~ '^fltiya_[a-f0-9]{32}$','opaque room';assert result->>'identity' not in (a::text,b::text),'per call opaque identity';
 begin perform public.call_action(a,sa_other,'token',call_id);raise exception 'different session joined';exception when insufficient_privilege then assert sqlerrm='call_unavailable';end;
 result:=public.call_action(a,sa,'heartbeat',call_id);assert result->'call'->>'status'='accepted','heartbeat';
 delete from public.friendships where user_low=least(a,b) and user_high=greatest(a,b);
 assert (select status='ended' and ended_reason='relationship_unavailable' from private.calls where id=call_id),'unfriend closes immediately';
 assert exists(select 1 from private.call_cleanup where private.call_cleanup.call_id=calls.call_id and completed_at is null),'durable outbox created';
 assert public.call_action(a,sa,'state',call_id)->'call'->>'status'='ended','closed state readable';
 begin perform public.call_action(a,sa,'token',call_id);raise exception 'unfriend token allowed';exception when raise_exception then assert sqlerrm='call_not_accepted';end;
 select decrypted_secret into worker_token from vault.decrypted_secrets where name='fltiya_call_worker_token';
 begin perform public.claim_call_cleanup(repeat('0',64));raise exception 'invalid worker allowed';exception when insufficient_privilege then assert sqlerrm='invalid_worker';end;
 jobs:=public.claim_call_cleanup(worker_token);assert jsonb_array_length(jobs)>0,'outbox claimed';
 perform public.finish_call_cleanup(call_id,(select (value->>'lease_id')::uuid from jsonb_array_elements(jobs) where value->>'call_id'=call_id::text),false,'arbitrary upstream detail');
 assert (select last_error='rtc_cleanup_failed' and lease_id is null and completed_at is null from private.call_cleanup where private.call_cleanup.call_id=calls.call_id),'failed cleanup retained safely';
 -- An old completion cannot steal a newer lease, and one successful DeleteRoom
 -- is not enough to discard the delayed-token tombstone.
 update private.call_cleanup set next_attempt_at=clock_timestamp()-interval '1 second' where private.call_cleanup.call_id=calls.call_id;
 jobs:=public.claim_call_cleanup(worker_token);
 perform public.finish_call_cleanup(call_id,gen_random_uuid(),true,null);
 assert (select lease_id is not null from private.call_cleanup where private.call_cleanup.call_id=calls.call_id),'stale lease ignored';
 perform public.finish_call_cleanup(call_id,(select (value->>'lease_id')::uuid from jsonb_array_elements(jobs) where value->>'call_id'=call_id::text),true,null);
 assert (select completed_at is null from private.call_cleanup where private.call_cleanup.call_id=calls.call_id),'successful cleanup repeats through token refresh window';
 insert into public.friendships(user_low,user_high) values(least(a,b),greatest(a,b));
 result:=public.call_action(a,sa,'create',null,b,'video');second_id:=(result->'call'->>'id')::uuid;
 insert into public.blocks(owner_id,blocked_id) values(b,a);
 assert (select status='ended' from private.calls where id=second_id),'block closes immediately';
 delete from public.blocks where owner_id=b and blocked_id=a;
 result:=public.call_action(a,sa,'create',null,b,'voice');second_id:=(result->'call'->>'id')::uuid;
 result:=public.call_action(b,sb,'reject',second_id);assert result->'call'->>'status'='rejected','reject';
 result:=public.call_action(a,sa,'create',null,b,'voice');second_id:=(result->'call'->>'id')::uuid;
 update private.calls set expires_at=clock_timestamp()-interval '1 second' where id=second_id;
 result:=public.call_action(a,sa,'state',second_id);assert result->'call'->>'status'='missed','ringing expires';
 result:=public.call_action(a,sa,'create',null,b,'voice');second_id:=(result->'call'->>'id')::uuid;
 result:=public.call_action(b,sb,'accept',second_id);
 update private.calls set caller_seen_at=clock_timestamp()-interval '1 minute',expires_at=clock_timestamp()-interval '1 second' where id=second_id;
 result:=public.call_action(b,sb,'state',second_id);assert result->'call'->>'status'='ended' and result->'call'->>'ended_reason'='heartbeat_expired','accepted heartbeat expiry';
 -- Rate limiter intentionally limits six outgoing attempts/minute.
 update private.calls set created_at=clock_timestamp()-interval '2 minutes' where caller_id=a;
 result:=public.call_action(a,sa,'create',null,b,'voice');second_id:=(result->'call'->>'id')::uuid;
 result:=public.call_action(b,sb,'accept',second_id);
 delete from auth.sessions where id=sb;
 assert (select status='ended' and ended_reason='session_unavailable' from private.calls where id=second_id),'session deletion closes immediately';
 assert (select count(*) from private.call_cleanup where identities is not null)>=5,'every close has durable cleanup';
 result:=public.call_action(a,sa,'create',null,outsider,'voice');second_id:=(result->'call'->>'id')::uuid;
 update private.accounts set state='suspended' where user_id=outsider;
 assert (select status='ended' from private.calls where id=second_id),'account suspension closes immediately';
 update private.accounts set state='active' where user_id=outsider;
 result:=public.call_action(a,sa,'create',null,outsider,'voice');second_id:=(result->'call'->>'id')::uuid;
 update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id=outsider;
 assert (select status='ended' from private.calls where id=second_id),'Auth ban closes immediately';
 assert not private.call_session_active(outsider,so),'Auth ban blocks further calls';
 result:=public.call_action(a,sa,'create',null,b,'voice');second_id:=(result->'call'->>'id')::uuid;
 result:=public.call_action(a,sa,'end',second_id);
 assert result->'call'->>'status'='ended' and result->'call'->>'ended_reason'='cancelled','creating caller session cancels ringing';
 assert (select count(*) from cron.job where jobname='fltiya-call-maintenance')=1,'maintenance fallback scheduled';
end $test$;
rollback;
