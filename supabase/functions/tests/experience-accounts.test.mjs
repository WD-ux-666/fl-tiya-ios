import test from 'node:test';
import assert from 'node:assert/strict';
import {validatedSession} from '../_shared/payment-validation.mjs';
import {createExperienceDeletionHandler,createExperienceDeletionServices} from '../_shared/experience-deletion.mjs';
const uid='1108389d-a330-4c60-8a4f-78b6b1fbd923',sid='2108389d-a330-4c60-8a4f-78b6b1fbd923',url='https://fixture.supabase.co';
const jwt=(anon=true)=>'e30.'+Buffer.from(JSON.stringify({sub:uid,session_id:sid,iss:url+'/auth/v1',exp:2000000000,role:'authenticated',aud:'authenticated',is_anonymous:anon})).toString('base64url')+'.fixture';
const request=(body='{}',headers={})=>new Request(url,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+jwt(),...headers},body});
const actor={userId:uid,sessionId:sid};
const services=()=>({authenticate:async()=>actor,prepare:async()=>({user_id:uid,objects:[]}),removeObjects:async()=>{},finish:async()=>({deleted:true})});
test('payments reject anonymous by default; scoped option needs both actual Auth and JWT anonymity',()=>{
 const user={id:uid,is_anonymous:true};assert.throws(()=>validatedSession(jwt(),user,url),{code:'invalid_session'});
 assert.deepEqual(validatedSession(jwt(),user,url,Date.now()/1000,{allowAnonymous:true}),actor);
 assert.throws(()=>validatedSession(jwt(false),user,url,Date.now()/1000,{allowAnonymous:true}),{code:'invalid_session'});
 assert.throws(()=>validatedSession(jwt(),{id:uid,is_anonymous:false},url,Date.now()/1000,{allowAnonymous:true}),{code:'invalid_session'});
});
test('deletion only accepts empty JSON and authenticated POST',async()=>{
 let count=0;let s=services();s.authenticate=async()=>{count++;return actor;};let h=createExperienceDeletionHandler(s);
 for(const body of ['{"user_id":"'+uid+'"}','[]','null','{'])assert.equal((await h(request(body))).status,400);
 assert.equal((await h(request('{}',{'content-type':'text/plain'}))).status,415);
 assert.equal((await h(request('{}',{authorization:'Basic fixture'}))).status,401);
 assert.equal((await h(new Request(url))).status,405);assert.equal(count,0);
});
test('deletion removes attested own objects before finish and repeats manifest to cover more batches',async()=>{
 let sequence=[],round=0,s=services();s.prepare=async()=>{sequence.push('prepare');return {user_id:uid,objects:round++===0?[{bucket_id:'avatars',name:uid+'/a.png'}]:[]};};s.removeObjects=async objects=>{sequence.push('remove');assert.equal(objects[0].name,uid+'/a.png');};s.finish=async()=>{sequence.push('finish');return {deleted:true};};
 let r=await createExperienceDeletionHandler(s)(request());assert.equal(r.status,200);assert.deepEqual(await r.json(),{deleted:true});assert.deepEqual(sequence,['prepare','remove','prepare','finish']);assert.equal(r.headers.get('cache-control'),'no-store');
});
test('wrong manifest user/path/bucket fails closed and never calls finish',async()=>{
 for(const objects of [[{bucket_id:'avatars',name:sid+'/a.png'}],[{bucket_id:'arbitrary',name:uid+'/a.png'}],[{bucket_id:'clips',name:uid+'/../other'}]]){
 let s=services(),finished=false;s.prepare=async()=>({user_id:uid,objects});s.finish=async()=>{finished=true;return {deleted:true};};assert.equal((await createExperienceDeletionHandler(s)(request())).status,503);assert.equal(finished,false);
 }
 let s=services();s.prepare=async()=>({user_id:sid,objects:[]});assert.equal((await createExperienceDeletionHandler(s)(request())).status,503);
});
test('Storage failure is retryable and error bodies do not expose upstream details',async()=>{
 let s=services(),finished=false;s.prepare=async()=>({user_id:uid,objects:[{bucket_id:'clips',name:uid+'/a.mp4'}]});s.removeObjects=async()=>{throw Error('SECRET fixture');};s.finish=async()=>{finished=true;};let r=await createExperienceDeletionHandler(s)(request());assert.equal(r.status,503);assert.deepEqual(await r.json(),{error:'account_deletion_unavailable'});assert.equal(finished,false);
});
test('production service authenticates actual anonymous user and sends only verified actor/session to service RPC',async()=>{
 let calls=[];const env={SUPABASE_URL:url,SUPABASE_ANON_KEY:'public-fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture'};
 let s=createExperienceDeletionServices(k=>env[k],async(endpoint,init)=>{calls.push([endpoint,init]);if(endpoint.endsWith('/auth/v1/user'))return Response.json({id:uid,is_anonymous:true});if(endpoint.endsWith('prepare_experience_deletion'))return Response.json({user_id:uid,objects:[]});if(endpoint.endsWith('finish_experience_deletion'))return Response.json({deleted:true});throw Error('unexpected');});
 assert.equal((await createExperienceDeletionHandler(s)(request())).status,200);
 assert.deepEqual(JSON.parse(calls[1][1].body),{actor_user_id:uid,actor_session_id:sid});assert.equal(calls[1][1].headers.Authorization,'Bearer server-fixture');
});
test('production service rejects permanent users and revoked database sessions',async()=>{
 const env={SUPABASE_URL:url,SUPABASE_ANON_KEY:'public-fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture'};
 for(const permanent of [true,false]){
 let s=createExperienceDeletionServices(k=>env[k],async(endpoint)=> endpoint.endsWith('/auth/v1/user')?Response.json({id:uid,is_anonymous:!permanent}):Response.json({message:'experience_session_required'},{status:403}));
 assert.equal((await createExperienceDeletionHandler(s)(request())).status,401);
 }
});
test('Storage API batches exact attested paths and uses only server-side credentials',async()=>{
 let calls=[];const env={SUPABASE_URL:url,SUPABASE_ANON_KEY:'public-fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture'};let s=createExperienceDeletionServices(k=>env[k],async(endpoint,init)=>{calls.push([endpoint,init]);return Response.json([]);});
 await s.removeObjects([{bucket_id:'avatars',name:uid+'/a.png'},{bucket_id:'clips',name:uid+'/a.mp4'}]);assert.equal(calls.length,2);assert.equal(calls[0][0],url+'/storage/v1/object/avatars');assert.equal(calls[0][1].method,'DELETE');assert.deepEqual(JSON.parse(calls[0][1].body),{prefixes:[uid+'/a.png']});
});
