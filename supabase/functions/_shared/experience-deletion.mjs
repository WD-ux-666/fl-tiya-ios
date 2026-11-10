import {authenticateUser,bearerToken,jsonResponse} from './payment-http.mjs';
import {PaymentError} from './payment-validation.mjs';
const fail=(status,code)=>{throw new PaymentError(status,code);};
const record=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
async function emptyJSON(request){
 if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')fail(415,'json_required');
 const length=request.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>256))fail(413,'request_too_large');
 const reader=request.body?.getReader();if(!reader)fail(400,'invalid_request');let bytes=0;const chunks=[];
 try{for(;;){const {value,done}=await reader.read();if(done)break;bytes+=value.byteLength;if(bytes>256){await reader.cancel();fail(413,'request_too_large');}chunks.push(value);}}finally{reader.releaseLock();}
 const all=new Uint8Array(bytes);let offset=0;for(const c of chunks){all.set(c,offset);offset+=c.length;}
 let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all));}catch{fail(400,'invalid_request');}
 if(!record(body)||Object.keys(body).length!==0)fail(400,'invalid_request');
}
function manifest(result,actor){
 if(!record(result)||result.user_id!==actor.userId||!Array.isArray(result.objects)||result.objects.length>500)fail(503,'account_deletion_unavailable');
 for(const o of result.objects){
  if(!record(o)||!['avatars','clips'].includes(o.bucket_id)||typeof o.name!=='string'||o.name.length>300||!o.name.startsWith(actor.userId+'/')||o.name.split('/').some(x=>!x||x==='.'||x==='..'))fail(503,'account_deletion_unavailable');
 }
 return result.objects;
}
export function createAccountDeletionHandler(services){return async request=>{
 try{
  if(request.method!=='POST')return jsonResponse(405,{error:'method_not_allowed'});
  await emptyJSON(request);
  const actor=await services.authenticate(bearerToken(request.headers));
  // Each pass revalidates the real, current server session. Deleting state denies new
  // uploads immediately, while existing in-flight uploads must drain before the
  // final checked transaction can delete the user. Retry continues safely.
  for(let pass=0;pass<10;pass++){
   const objects=manifest(await services.prepare(actor),actor);
   if(objects.length){await services.removeObjects(objects);continue;}
   const result=await services.finish(actor);
   if(result?.deleted!==true)fail(503,'account_deletion_unavailable');
   return jsonResponse(200,{deleted:true});
  }
  fail(503,'account_deletion_retry_required');
 }catch(error){
  if(error instanceof PaymentError)return jsonResponse(error.status,{error:error.code});
  return jsonResponse(503,{error:'account_deletion_unavailable'});
 }
};}
export const createExperienceDeletionHandler=createAccountDeletionHandler;
function createDeletionServices(readEnvironment,fetchImpl,prepareRPC,finishRPC){
 function config(){
  const url=readEnvironment('SUPABASE_URL')?.replace(/\/$/,'');const anonKey=readEnvironment('SUPABASE_ANON_KEY');const serviceRoleKey=readEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  if(!url?.startsWith('https://')||!anonKey||!serviceRoleKey)fail(503,'account_deletion_unavailable');return {url,anonKey,serviceRoleKey};
 }
 async function rpc(name,actor){
  const c=config();let response;try{response=await fetchImpl(c.url+'/rest/v1/rpc/'+name,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{apikey:c.serviceRoleKey,Authorization:'Bearer '+c.serviceRoleKey,'Content-Type':'application/json'},body:JSON.stringify({actor_user_id:actor.userId,actor_session_id:actor.sessionId})});}catch{fail(503,'account_deletion_unavailable');}
  let value;try{const text=await response.text();if(text.length>262144)throw Error();value=JSON.parse(text);}catch{fail(503,'account_deletion_unavailable');}
  if(!response.ok){
   if(['experience_session_required','account_deletion_session_required'].includes(value?.message))fail(401,value.message);
   if(value?.message==='apple_revocation_configuration_required')fail(409,'apple_revocation_configuration_required');
   fail(503,'account_deletion_unavailable');
  }return value;
 }
 return {
  async authenticate(token){const c=config();const actor=await authenticateUser(token,c,fetchImpl,{allowAnonymous:true});
   // The deletion-specific RPC independently verifies the current Auth session,
   // immutable cohort and account state. No editable metadata grants deletion.
   return actor;
  },
  prepare:actor=>rpc(prepareRPC,actor),
  finish:actor=>rpc(finishRPC,actor),
  async removeObjects(objects){
   const c=config();for(const bucket of ['avatars','clips']){
    const paths=objects.filter(o=>o.bucket_id===bucket).map(o=>o.name);if(!paths.length)continue;
    let response;try{response=await fetchImpl(c.url+'/storage/v1/object/'+bucket,{method:'DELETE',redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:c.serviceRoleKey,Authorization:'Bearer '+c.serviceRoleKey,'Content-Type':'application/json'},body:JSON.stringify({prefixes:paths})});}catch{fail(503,'account_deletion_unavailable');}
    // The next manifest and final transaction prove no owned objects remain.
    if(!response.ok)fail(503,'account_deletion_unavailable');await response.body?.cancel();
   }
  },
 };
}
export function createExperienceDeletionServices(readEnvironment,fetchImpl=fetch){
 return createDeletionServices(readEnvironment,fetchImpl,'prepare_experience_deletion','finish_experience_deletion');
}
export function createAccountDeletionServices(readEnvironment,fetchImpl=fetch){
 return createDeletionServices(readEnvironment,fetchImpl,'prepare_account_deletion','finish_account_deletion');
}
