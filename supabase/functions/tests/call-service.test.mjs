import test from 'node:test';
import assert from 'node:assert/strict';
import { CallError, createCallHandler, createCallServices, joinGrant, liveKitConfiguration, signLiveKitJWT, validateCallRequest } from '../_shared/call-service.mjs';

const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const peer='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const identity='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const room='fltiya_'+'a'.repeat(32);
const actor={userId:id,sessionId:identity};
const call={id,caller_id:id,callee_id:peer,kind:'voice',status:'accepted',peer_id:peer,peer_display_name:'Friend'};
const request=(body,headers={})=>new Request('https://example.invalid/call-service',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer fixture',...headers},body:JSON.stringify(body)});
function setup(changes={}){
 const calls=[];
 const services={authenticate:async()=>{calls.push('auth');return actor;},requireRTC:()=>calls.push('config'),
  action:async(_actor,body)=>{calls.push(body.action);return {call,room_name:room,identity};},
  prepareRoom:async()=>calls.push('room'),joinToken:async()=>{calls.push('sign');return {url:'wss://fixture.livekit.cloud',token:'opaque-jwt',expires_at:'2030-01-01T00:00:00Z'};},
  claimCleanup:async()=>[],finishCleanup:async()=>{},cleanupRoom:async()=>{},...changes};
 return {handler:createCallHandler(services),calls};
}
test('request actions reject peer identity override, arbitrary rooms, and malformed IDs',()=>{
 for(const body of [{action:'create',target_user_id:peer,kind:'voice',room_name:'chosen'},
  {action:'token',call_id:id,user_id:peer},{action:'token',call_id:[id]},
  {action:'create',target_user_id:[peer],kind:'voice'},{action:'create',target_user_id:peer,kind:'screen'},
  {action:'end'},{action:'availability',call_id:id},{action:'cleanup',worker_token:'secret'}]){
  assert.throws(()=>validateCallRequest(body),CallError);
 }
 assert.deepEqual(validateCallRequest({action:'state'}),{action:'state'});
});
test('missing RTC config prevents create before a ringing row is written',async()=>{
 const {handler,calls}=setup({requireRTC:()=>{throw new CallError(503,'calls_unavailable');}});
 const response=await handler(request({action:'create',target_user_id:peer,kind:'voice'}));
 assert.equal(response.status,503);assert.deepEqual(calls,['auth']);assert.equal((await response.json()).error,'calls_unavailable');
});
test('availability rechecks server session and reports missing RTC as unavailable',async()=>{
 const {handler,calls}=setup({requireRTC:()=>{throw new CallError(503,'calls_unavailable');}});
 assert.equal((await (await handler(request({action:'availability'}))).json()).available,false);
 assert.deepEqual(calls,['auth','state']);
 const denied=setup({action:async()=>{throw new CallError(401,'invalid_session');}});
 assert.equal((await denied.handler(request({action:'availability'}))).status,401);
});
test('state and end still work while RTC config is missing, without routing data',async()=>{
 const {handler}=setup({requireRTC:()=>{throw Error('must not call');}});
 for(const action of ['state','end','reject','heartbeat']){
  const response=await handler(request({action,call_id:id}));assert.equal(response.status,200);
  const value=await response.json();assert.equal(value.call.id,id);assert.equal(value.room_name,undefined);assert.equal(value.identity,undefined);assert.equal(value.rtc,undefined);
 }
});
test('join tokens require acceptance then room creation, signing and a final DB gate',async()=>{
 const {handler,calls}=setup();const response=await handler(request({action:'token',call_id:id}));
 assert.equal(response.status,200);assert.deepEqual(calls,['auth','config','token','room','sign','token']);
 assert.equal((await response.json()).rtc.token,'opaque-jwt');
 const ringing=setup({action:async()=>({call:{...call,status:'ringing'},room_name:room,identity})});
 assert.equal((await ringing.handler(request({action:'token',call_id:id}))).status,403);assert.ok(!ringing.calls.includes('sign'));
});
test('unfriend/hangup during RTC preparation never returns the signed token',async()=>{
 let reads=0;const {handler}=setup({action:async()=>{if(++reads===2)throw new CallError(409,'call_not_accepted');return {call,room_name:room,identity};}});
 const response=await handler(request({action:'token',call_id:id}));assert.equal(response.status,409);assert.ok(!(await response.text()).includes('opaque-jwt'));
});
test('cleanup has a separate private-token boundary and records failed jobs for retry',async()=>{
 const outcomes=[];const jobs=[{call_id:id,lease_id:identity},{call_id:peer,lease_id:identity}];
 const {handler,calls}=setup({claimCleanup:async()=>jobs,cleanupRoom:async job=>{if(job.call_id===id)throw Error('upstream secret');},finishCleanup:async(job,success)=>outcomes.push([job.call_id,success])});
 assert.equal((await handler(request({action:'cleanup'}))).status,401);
 const response=await handler(request({action:'cleanup'},{'x-fltiya-call-worker':'a'.repeat(64)}));
 assert.equal(response.status,200);const summary=await response.json();assert.equal(summary.processed,2);assert.equal(summary.completed,1);assert.deepEqual(outcomes,[[id,false],[peer,true]]);assert.deepEqual(calls,[]);
});
test('oversized chunked requests and anonymous requests cannot reach Auth or DB',async()=>{
 const {handler,calls}=setup();let response=await handler(request({action:'state',padding:'x'.repeat(3000)}));assert.equal(response.status,413);
 response=await handler(request({action:'state'},{Authorization:''}));assert.equal(response.status,401);assert.deepEqual(calls,[]);
});
test('errors cannot serialize SQL details, API secrets or JWTs',async()=>{
 const {handler}=setup({action:async()=>{throw Error('secret-key opaque-jwt postgres details');}});
 const response=await handler(request({action:'state'}));assert.equal(response.status,503);assert.equal((await response.json()).error,'calls_unavailable');assert.equal(response.headers.get('cache-control'),'no-store');
});
test('RTC only accepts Cloud secure URLs required for revocation guarantees',()=>{
 const secrets={LIVEKIT_URL:'wss://fixture.livekit.cloud',LIVEKIT_API_KEY:'api-key',LIVEKIT_API_SECRET:'api-secret'};
 assert.equal(liveKitConfiguration(key=>secrets[key]).apiURL,'https://fixture.livekit.cloud');
 for(const url of ['wss://self.example','https://fixture.livekit.cloud','wss://fixture.livekit.cloud.evil.invalid','wss://fixture.livekit.cloud/path','wss://user@fixture.livekit.cloud','wss://fixture.livekit.cloud?key=secret']){
  assert.throws(()=>liveKitConfiguration(key=>key==='LIVEKIT_URL'?url:secrets[key]),CallError);
 }
});
test('JWT signature, identity, room, TTL and microphone/camera grants are restricted',async()=>{
 const now=2000000000;const grant=joinGrant(room,'voice');const jwt=await signLiveKitJWT('api-key','api-secret',{sub:identity,video:grant},now);
 const [header,payload,signature]=jwt.split('.');const claims=JSON.parse(Buffer.from(payload,'base64url'));
 assert.equal(claims.iss,'api-key');assert.equal(claims.sub,identity);assert.equal(claims.exp-now,120);assert.equal(claims.nbf,now-1);
 assert.deepEqual(claims.video.canPublishSources,['microphone']);assert.equal(claims.video.room,room);
 for(const key of ['roomCreate','roomAdmin','roomList','roomRecord','canPublishData','canUpdateOwnMetadata'])assert.equal(claims.video[key],false);
 assert.deepEqual(joinGrant(room,'video').canPublishSources,['microphone','camera']);
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode('api-secret'),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 assert.ok(await crypto.subtle.verify('HMAC',key,Buffer.from(signature,'base64url'),new TextEncoder().encode(header+'.'+payload)));
});

const env={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'private-service-key',SUPABASE_ANON_KEY:'public-key',LIVEKIT_URL:'wss://fixture.livekit.cloud',LIVEKIT_API_KEY:'api-key',LIVEKIT_API_SECRET:'api-secret'};
test('runtime uses service-role DB RPC with verified actor arguments and safe error mapping',async()=>{
 const seen=[];const services=createCallServices(key=>env[key],async(url,options)=>{seen.push({url,...options});return Response.json({message:'call_busy'},{status:409});});
 await assert.rejects(()=>services.action(actor,{action:'create',target_user_id:peer,kind:'voice'}),e=>e.status===409&&e.code==='call_busy');
 const sent=JSON.parse(seen[0].body);assert.equal(sent.actor_user_id,id);assert.equal(sent.actor_session_id,identity);assert.equal(seen[0].headers.Authorization,'Bearer private-service-key');
});
test('runtime removes both identities with explicit cutoff then deletes room, never trusting client grants',async()=>{
 const seen=[];const before=Math.floor(Date.now()/1000);const services=createCallServices(key=>env[key],async(url,options)=>{seen.push({url,...options});return Response.json({});});
 await services.cleanupRoom({room_name:room,identities:[id,identity]});
 assert.deepEqual(seen.map(x=>x.url.split('/').pop()),['RemoveParticipant','RemoveParticipant','DeleteRoom']);
 for(const sent of seen.slice(0,2)){
  const body=JSON.parse(sent.body);assert.equal(body.room,room);assert.ok(Number(body.revoke_token_ts)>=before+2);
  const claims=JSON.parse(Buffer.from(sent.headers.Authorization.slice(7).split('.')[1],'base64url'));assert.deepEqual(claims.video,{roomAdmin:true,room});
 }
 const deleteClaims=JSON.parse(Buffer.from(seen[2].headers.Authorization.slice(7).split('.')[1],'base64url'));assert.deepEqual(deleteClaims.video,{roomCreate:true});
});
test('runtime creates only two-person rooms and treats cleanup not_found idempotently',async()=>{
 const seen=[];const services=createCallServices(key=>env[key],async(url,options)=>{seen.push({url,...options});return url.endsWith('CreateRoom')?Response.json({}):Response.json({code:'not_found'},{status:404});});
 await services.prepareRoom(room);assert.deepEqual(JSON.parse(seen[0].body),{name:room,empty_timeout:60,departure_timeout:20,max_participants:2});
 await services.cleanupRoom({room_name:room,identities:[id,identity]});assert.equal(seen.length,4);
});
test('one failed revocation still attempts the other identity and deletes the room, then retries',async()=>{
 const seen=[];const services=createCallServices(key=>env[key],async(url)=>{seen.push(url.split('/').pop());return seen.length===1?Response.json({code:'unavailable'},{status:503}):Response.json({});});
 await assert.rejects(()=>services.cleanupRoom({room_name:room,identities:[id,identity]}),e=>e.code==='rtc_cleanup_failed');
 assert.deepEqual(seen,['RemoveParticipant','RemoveParticipant','DeleteRoom']);
});
