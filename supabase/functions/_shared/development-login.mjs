import { readPaymentJSON, jsonResponse, errorResponse, rpcCall } from './payment-http.mjs';
import { PaymentError, validatedSession } from './payment-validation.mjs';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACCESS_CODE=/^FLD_[A-Za-z0-9_-]{43}$/;
const unavailable=()=>new PaymentError(503,'development_login_unavailable');
const identityMatches=(value,context)=>value?.id===context.user_id && value?.email===context.email;

export function createDevelopmentLoginHandler(services) {
 return async request=>{
  if(request.method!=='POST') return jsonResponse(405,{error:'method_not_allowed'},{Allow:'POST'});
  try {
   const code=await readPaymentJSON(request,'access_code',4096);
   if(!ACCESS_CODE.test(code)) throw new PaymentError(401,'invalid_development_access');
   const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(code));
   const hash=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
   const context=await services.lookup(hash);
   if(!context) throw new PaymentError(401,'invalid_development_access');
   if(!UUID.test(context.user_id) || typeof context.email!=='string' ||
      !/^development\.[a-f0-9-]+@example\.invalid$/.test(context.email) ||
      typeof context.label!=='string' || typeof context.exists!=='boolean') throw unavailable();
   if(!context.exists) {
    let user;
    try { user=await services.create(context,code); }
    catch(error) {
     if(!(error instanceof PaymentError) || error.code!=='development_user_exists') throw error;
     // A concurrent create can win. Never find/adopt another user by email,
     // replace the reserved UUID or reset an existing account's password.
     user=await services.existing(context.user_id);
    }
    if(!identityMatches(user,context)) throw unavailable();
   }
   const session=await services.signIn(context.email,code);
   if(!identityMatches(session?.user,context) || typeof session.access_token!=='string' ||
      !session.access_token || typeof session.refresh_token!=='string' || !session.refresh_token) throw unavailable();
   const verified=await services.verify(session.access_token,context.user_id);
   if(verified?.user_id!==context.user_id || verified?.cohort!=='development' ||
      typeof verified.display_name!=='string') throw unavailable();
   return jsonResponse(200,{access_token:session.access_token,refresh_token:session.refresh_token,
    user_id:context.user_id,display_name:verified.display_name});
  } catch(error) {
   if(error instanceof PaymentError) return errorResponse(error);
   return errorResponse(unavailable());
  }
 };
}

export function createDevelopmentServices(readEnvironment,fetchImpl=fetch) {
 function config() {
  const url=readEnvironment('SUPABASE_URL')?.replace(/\/$/,'');
  const serviceRoleKey=readEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey=readEnvironment('SUPABASE_ANON_KEY');
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url??'') || !serviceRoleKey || !anonKey) throw unavailable();
  return {url,serviceRoleKey,anonKey};
 }
 async function call(path,{method='GET',body,accessToken,admin=false}={}) {
  const c=config();
  const response=await fetchImpl(c.url+path,{method,redirect:'error',signal:AbortSignal.timeout(10000),
   headers:{apikey:admin?c.serviceRoleKey:c.anonKey,Authorization:`Bearer ${admin?c.serviceRoleKey:(accessToken??c.anonKey)}`,
    'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
  if(!response.ok) {
   // Upstream bodies may contain account/credential details. Never serialize
   // them in errors. A create conflict is handled by exact-ID lookup only.
   if(admin && method==='POST' && [409,422].includes(response.status)) throw new PaymentError(503,'development_user_exists');
   throw unavailable();
  }
  const text=await response.text();
  if(text.length>524288) throw unavailable();
  return JSON.parse(text);
 }
 return {
  lookup:hash=>rpcCall('development_login_context',{code_hash:hash},config(),fetchImpl),
  create:(context,code)=>call('/auth/v1/admin/users',{method:'POST',admin:true,body:{id:context.user_id,email:context.email,
   password:code,email_confirm:true,app_metadata:{fltiya_development:true}}}),
  existing:id=>{if(!UUID.test(id)) throw unavailable();return call('/auth/v1/admin/users/'+id,{admin:true});},
  signIn:(email,code)=>call('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password:code}}),
  async verify(accessToken,expectedID) {
   const c=config();
   const user=await call('/auth/v1/user',{accessToken});
   const actor=validatedSession(accessToken,user,c.url);
   if(actor.userId!==expectedID) throw unavailable();
   const context=await call('/rest/v1/rpc/session_context',{method:'POST',body:{},accessToken});
   if(context?.user_id!==expectedID || context?.cohort!=='development') throw unavailable();
   return context;
  },
 };
}
