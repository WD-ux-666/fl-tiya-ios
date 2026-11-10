import test from 'node:test';
import assert from 'node:assert/strict';
import {createAccountDeletionHandler,createAccountDeletionServices} from '../_shared/account-deletion.mjs';
const uid='1108389d-a330-4c60-8a4f-78b6b1fbd923',sid='2108389d-a330-4c60-8a4f-78b6b1fbd923',url='https://fixture.supabase.co';
const jwt=(anonymous=false)=>'e30.'+Buffer.from(JSON.stringify({sub:uid,session_id:sid,iss:url+'/auth/v1',exp:2000000000,role:'authenticated',aud:'authenticated',is_anonymous:anonymous})).toString('base64url')+'.fixture';
const request=(body='{}')=>new Request(url,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+jwt()},body});
const env=name=>({SUPABASE_URL:url,SUPABASE_ANON_KEY:'fixture-anon',SUPABASE_SERVICE_ROLE_KEY:'fixture-service'})[name];
test('unified deletion verifies the current Auth user and only calls service-owned generic RPCs',async()=>{
 const calls=[];
 const services=createAccountDeletionServices(env,async(target,options)=>{
  calls.push({target,options});
  if(target.endsWith('/auth/v1/user'))return Response.json({id:uid,is_anonymous:false});
  assert.equal(options.headers.apikey,'fixture-service');
  assert.deepEqual(JSON.parse(options.body),{actor_user_id:uid,actor_session_id:sid});
  if(target.endsWith('/prepare_account_deletion'))return Response.json({user_id:uid,objects:[]});
  if(target.endsWith('/finish_account_deletion'))return Response.json({deleted:true});
  throw Error('Unexpected endpoint');
 });
 const response=await createAccountDeletionHandler(services)(request());
 assert.equal(response.status,200);assert.deepEqual(await response.json(),{deleted:true});
 assert.deepEqual(calls.map(x=>new URL(x.target).pathname),['/auth/v1/user','/rest/v1/rpc/prepare_account_deletion','/rest/v1/rpc/finish_account_deletion']);
 assert.equal(response.headers.get('cache-control'),'no-store');
});
test('Apple revocation configuration failure is safe and happens before any object removal or finish',async()=>{
 let calls=[];
 const services=createAccountDeletionServices(env,async(target)=>{
  calls.push(target);
  if(target.endsWith('/auth/v1/user'))return Response.json({id:uid,is_anonymous:false});
  if(target.endsWith('/prepare_account_deletion'))return Response.json({message:'apple_revocation_configuration_required'},{status:403});
  throw Error('A rejected Apple account must not reach cleanup');
 });
 const response=await createAccountDeletionHandler(services)(request());
 assert.equal(response.status,409);assert.deepEqual(await response.json(),{error:'apple_revocation_configuration_required'});
 assert.equal(calls.length,2);
});
test('revoked, foreign, suspended or expired database session fails without exposing upstream details',async()=>{
 const services=createAccountDeletionServices(env,async target=>target.endsWith('/auth/v1/user')
  ?Response.json({id:uid,is_anonymous:false})
  :Response.json({message:'account_deletion_session_required',detail:'private detail'},{status:403}));
 const response=await createAccountDeletionHandler(services)(request());
 assert.equal(response.status,401);assert.deepEqual(await response.json(),{error:'account_deletion_session_required'});
});
test('unified deletion refuses a caller-selected target and never authenticates it',async()=>{
 let called=false;
 const response=await createAccountDeletionHandler({authenticate:async()=>{called=true;}})(request(JSON.stringify({user_id:uid})));
 assert.equal(response.status,400);assert.equal(called,false);
});
test('unified deletion removes only attested own storage before the final checked transaction',async()=>{
 let phase=0,calls=[];
 const services=createAccountDeletionServices(env,async(target,options)=>{
  calls.push(target);
  if(target.endsWith('/auth/v1/user'))return Response.json({id:uid,is_anonymous:false});
  if(target.endsWith('/prepare_account_deletion'))return Response.json({user_id:uid,objects:phase++===0?[{bucket_id:'avatars',name:uid+'/old.jpg'}]:[]});
  if(target.endsWith('/storage/v1/object/avatars')){
   assert.deepEqual(JSON.parse(options.body),{prefixes:[uid+'/old.jpg']});assert.equal(options.method,'DELETE');
   return Response.json([]);
  }
  if(target.endsWith('/finish_account_deletion'))return Response.json({deleted:true});
  throw Error('Unexpected endpoint');
 });
 assert.equal((await createAccountDeletionHandler(services)(request())).status,200);
 assert.deepEqual(calls.map(x=>new URL(x).pathname),['/auth/v1/user','/rest/v1/rpc/prepare_account_deletion','/storage/v1/object/avatars','/rest/v1/rpc/prepare_account_deletion','/rest/v1/rpc/finish_account_deletion']);
});
