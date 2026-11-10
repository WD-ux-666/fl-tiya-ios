import test from 'node:test';
import assert from 'node:assert/strict';
import { createDevelopmentLoginHandler, createDevelopmentServices } from '../_shared/development-login.mjs';

const userId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const code='FLD_'+'A'.repeat(43);
const context={user_id:userId,email:`development.${userId}@example.invalid`,label:'Development Alpha',exists:false};
const request=value=>new Request('https://example.invalid/development-login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value)});
function setup(changes={}) {
 const calls=[];
 const services={
  lookup:async hash=>{calls.push(['lookup',hash]);return context;},
  create:async value=>{calls.push(['create',value.user_id]);return {id:userId,email:context.email};},
  existing:async()=>({id:userId,email:context.email}),
  signIn:async()=>{calls.push(['signin']);return {access_token:'transient-access',refresh_token:'transient-refresh',user:{id:userId,email:context.email}};},
  verify:async()=>{calls.push(['verify']);return {user_id:userId,display_name:'Development Alpha',cohort:'development'};},
  ...changes,
 };
 return {handler:createDevelopmentLoginHandler(services),calls};
}
test('unknown access codes never create or authenticate an account',async()=>{
 const {handler,calls}=setup({lookup:async()=>null});
 const response=await handler(request({access_code:code}));
 assert.equal(response.status,401);assert.deepEqual(calls,[]);
});
test('valid access code provisions only its reserved identity and returns a verified real session',async()=>{
 const {handler,calls}=setup(); const response=await handler(request({access_code:code}));
 assert.equal(response.status,200); const body=await response.json();
 assert.equal(body.user_id,userId); assert.equal(body.access_token,'transient-access');
 assert.deepEqual(calls.map(x=>x[0]),['lookup','create','signin','verify']);
 assert.match(calls[0][1],/^[a-f0-9]{64}$/);assert.notEqual(calls[0][1],code);
});
test('existing identities are not reset or recreated',async()=>{
 const {handler,calls}=setup({lookup:async()=>({...context,exists:true})});
 assert.equal((await handler(request({access_code:code}))).status,200);
 assert.ok(!calls.some(x=>x[0]==='create'));
});
test('wrong provisioned ID and cross-account session cannot unlock',async()=>{
 for(const changes of [
  {create:async()=>({id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',email:context.email})},
  {signIn:async()=>({access_token:'a',refresh_token:'b',user:{id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',email:context.email}})},
  {verify:async()=>({user_id:userId,display_name:'No',cohort:'production'})},
 ]) { const {handler}=setup(changes);const response=await handler(request({access_code:code})); assert.equal(response.status,503);const body=await response.json();assert.equal(body.access_token,undefined); }
});
test('malformed, excessive and beneficiary requests fail before lookup',async()=>{
 for(const body of [{access_code:'short'},{access_code:code,user_id:userId},{access_code:code+'A'.repeat(10000)}]) {
  const {handler,calls}=setup();assert.ok((await handler(request(body))).status>=400);assert.deepEqual(calls,[]);
 }
});
test('errors never reveal access codes or auth tokens',async()=>{
 const {handler}=setup({signIn:async()=>{throw new Error(code+' transient-refresh');}});
 const response=await handler(request({access_code:code}));assert.equal(response.status,503);
 const text=await response.text();assert.ok(!text.includes(code));assert.ok(!text.includes('transient-refresh'));
});

const baseURL='https://project.supabase.co';
const jwt=subject=>['fixture',Buffer.from(JSON.stringify({sub:subject,session_id:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+300,iss:baseURL+'/auth/v1'})).toString('base64url'),'fixture'].join('.');
function runtime({race=false,badIdentity=false,failSignIn=false}={}) {
 const calls=[];const token=jwt(userId);
 const fetcher=async(url,options)=>{
  const path=url.slice(baseURL.length);calls.push({path,...options,body:options.body?JSON.parse(options.body):undefined});
  if(path==='/rest/v1/rpc/development_login_context') return Response.json(context);
  if(path==='/auth/v1/admin/users') return race?Response.json({message:'private upstream details'},{status:422}):Response.json({id:userId,email:context.email});
  if(path==='/auth/v1/admin/users/'+userId) return Response.json({id:userId,email:context.email});
  if(path==='/auth/v1/token?grant_type=password') return failSignIn?Response.json({message:code},{status:400}):Response.json({access_token:token,refresh_token:'private-refresh',user:{id:userId,email:context.email}});
  if(path==='/auth/v1/user') return Response.json({id:badIdentity?'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb':userId});
  if(path==='/rest/v1/rpc/session_context') return Response.json({user_id:userId,display_name:context.label,cohort:'development'});
  throw new Error('unexpected request');
 };
 const env={SUPABASE_URL:baseURL,SUPABASE_SERVICE_ROLE_KEY:'server-fixture',SUPABASE_ANON_KEY:'public-fixture'};
 return {handler:createDevelopmentLoginHandler(createDevelopmentServices(name=>env[name],fetcher)),calls,token};
}
test('runtime uses server credentials only for reserved lookup/create and verifies the actual user JWT',async()=>{
 const {handler,calls,token}=runtime();const response=await handler(request({access_code:code}));
 assert.equal(response.status,200);assert.equal(calls.length,5);
 const create=calls.find(x=>x.path==='/auth/v1/admin/users');
 assert.deepEqual(create.body,{id:userId,email:context.email,password:code,email_confirm:true,app_metadata:{fltiya_development:true}});
 assert.equal(create.headers.Authorization,'Bearer server-fixture');
 for(const call of calls.filter(x=>['/auth/v1/user','/rest/v1/rpc/session_context'].includes(x.path))) {
  assert.equal(call.headers.Authorization,'Bearer '+token);assert.equal(call.headers.apikey,'public-fixture');
 }
 assert.ok(calls.every(x=>x.redirect==='error'));
});
test('concurrent provisioning retrieves the exact reserved UUID without password updates',async()=>{
 const {handler,calls}=runtime({race:true});assert.equal((await handler(request({access_code:code}))).status,200);
 assert.ok(calls.some(x=>x.path==='/auth/v1/admin/users/'+userId && x.method==='GET'));
 assert.ok(!calls.some(x=>['PUT','PATCH','DELETE'].includes(x.method)));
});
test('runtime rejects a verified JWT subject mismatch and redacts upstream authentication errors',async()=>{
 for(const flags of [{badIdentity:true},{failSignIn:true}]) {
  const {handler}=runtime(flags);const response=await handler(request({access_code:code}));
  assert.ok(response.status>=400);const body=await response.text();assert.ok(!body.includes(code));assert.ok(!body.includes('private-refresh'));
 }
});
