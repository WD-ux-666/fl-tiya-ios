import { authenticateUser } from './payment-http.mjs';
import { PaymentError } from './payment-validation.mjs';

export class CallError extends Error {
 constructor(status,code){super(code);this.status=status;this.code=code;}
}
const fail=(status,code)=>{throw new CallError(status,code);};
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACTIONS=new Set(['create','accept','reject','end','heartbeat','state','token','cleanup','availability']);
const SAFE_ERRORS=new Map([
 ['invalid_session',401],['invalid_worker',401],['call_unavailable',403],['invalid_request',400],
 ['call_busy',409],['call_not_ringing',409],['call_not_accepted',409],['call_rate_limited',429],
]);
const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}});
const record=x=>x&&typeof x==='object'&&!Array.isArray(x);

export function validateCallRequest(body){
 if(!record(body)||!ACTIONS.has(body.action))fail(400,'invalid_request');
 const keys=body.action==='create'?['action','target_user_id','kind']:['cleanup','availability'].includes(body.action)?['action']:['action','call_id'];
 if(Object.keys(body).some(k=>!keys.includes(k)))fail(400,'invalid_request');
 if(body.action==='create'){
  if(typeof body.target_user_id!=='string'||!UUID.test(body.target_user_id)||!['voice','video'].includes(body.kind))fail(400,'invalid_request');
 }else if(!['cleanup','availability'].includes(body.action)&&(body.call_id!==undefined||body.action!=='state')&&(typeof body.call_id!=='string'||!UUID.test(body.call_id)))fail(400,'invalid_request');
 return body;
}
async function readJSON(request){
 if(request.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json')fail(415,'json_required');
 const length=request.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>2048))fail(413,'request_too_large');
 const reader=request.body?.getReader();if(!reader)fail(400,'invalid_request');
 let bytes=0;const chunks=[];
 try{for(;;){const {value,done}=await reader.read();if(done)break;bytes+=value.byteLength;if(bytes>2048){await reader.cancel();fail(413,'request_too_large');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const all=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){all.set(chunk,offset);offset+=chunk.length;}
 try{return validateCallRequest(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(all)));}
 catch(e){if(e instanceof CallError)throw e;fail(400,'invalid_request');}
}
function bearer(request){const value=request.headers.get('authorization');const match=value?.length<=16384&&/^Bearer ([A-Za-z0-9_.-]+)$/i.exec(value);if(!match)fail(401,'authentication_required');return match[1];}
function safeCall(result){
 const c=result?.call;if(c===null)return {call:null};
 if(!record(c)||!UUID.test(c.id??'')||!['ringing','accepted','rejected','ended','missed'].includes(c.status))fail(503,'calls_unavailable');
 // Explicit allowlist prevents service-only RTC routing data reaching state.
 return {call:Object.fromEntries(['id','caller_id','callee_id','kind','status','created_at','answered_at','ended_at','expires_at','ended_reason','peer_id','peer_display_name','peer_avatar_path'].map(k=>[k,c[k]??null]))};
}

export function createCallHandler(services){
 return async request=>{
  try{
   if(request.method!=='POST')return json(405,{error:'method_not_allowed'});
   const body=await readJSON(request);
   if(body.action==='cleanup'){
    const token=request.headers.get('x-fltiya-call-worker');
    if(!/^[a-f0-9]{64}$/.test(token??''))fail(401,'invalid_worker');
    const jobs=await services.claimCleanup(token);let completed=0;
    for(const job of jobs){
     let succeeded=false;let errorCode='rtc_cleanup_failed';
     try{await services.cleanupRoom(job);succeeded=true;completed++;}
     catch(e){if(e instanceof CallError&&e.code==='calls_unavailable')errorCode=e.code;}
     await services.finishCleanup(job,succeeded,errorCode);
    }
    return json(200,{processed:jobs.length,completed});
   }
   const actor=await services.authenticate(bearer(request));
   if(body.action==='availability'){
    // Check database session eligibility too; /user alone accepts a still-valid
    // access JWT whose server session may already have been revoked.
    await services.action(actor,{action:'state'});
    try{services.requireRTC();return json(200,{available:true});}
    catch(e){if(e instanceof CallError&&e.code==='calls_unavailable')return json(200,{available:false});throw e;}
   }
   if(['create','accept','token'].includes(body.action))services.requireRTC();
   const result=await services.action(actor,body);
   if(body.action!=='token')return json(200,safeCall(result));
   if(result?.call?.status!=='accepted'||!/^fltiya_[a-f0-9]{32}$/.test(result.room_name??'')||!UUID.test(result.identity??''))fail(403,'call_unavailable');
   await services.prepareRoom(result.room_name);
   const rtc=await services.joinToken(result);
   // Room creation/signing are external IO. Recheck after both so an unfriend,
   // hangup or revoked session during them cannot return a fresh join token.
   const checked=await services.action(actor,{action:'token',call_id:body.call_id});
   if(checked.room_name!==result.room_name||checked.identity!==result.identity||checked.call?.status!=='accepted')fail(403,'call_unavailable');
   return json(200,{...safeCall(checked),rtc});
  }catch(e){
   if(e instanceof CallError)return json(e.status,{error:e.code});
   if(e instanceof PaymentError)return json(e.status,{error:e.code==='payment_service_unavailable'?'calls_unavailable':e.code});
   return json(503,{error:'calls_unavailable'});
  }
 };
}

const b64url=bytes=>btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
export async function signLiveKitJWT(apiKey,secret,claims,nowSeconds=Math.floor(Date.now()/1000)){
 const encode=value=>b64url(new TextEncoder().encode(JSON.stringify(value)));
 const input=encode({alg:'HS256',typ:'JWT'})+'.'+encode({iss:apiKey,nbf:nowSeconds-1,iat:nowSeconds,exp:nowSeconds+120,...claims});
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return input+'.'+b64url(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(input))));
}
export function joinGrant(room,kind){
 return {room,roomJoin:true,roomCreate:false,roomList:false,roomAdmin:false,roomRecord:false,
  canSubscribe:true,canPublish:true,canPublishData:false,canUpdateOwnMetadata:false,
  canPublishSources:kind==='video'?['microphone','camera']:['microphone']};
}
export function liveKitConfiguration(readEnvironment){
 let url;try{url=new URL(readEnvironment('LIVEKIT_URL'));}catch{fail(503,'calls_unavailable');}
 const apiKey=readEnvironment('LIVEKIT_API_KEY');const secret=readEnvironment('LIVEKIT_API_SECRET');
 // Cloud's explicit token revocation is required. roomCreate:false does NOT
 // prevent roomJoin from automatically creating a deleted room on reconnect.
 if(url.protocol!=='wss:'||!url.hostname.endsWith('.livekit.cloud')||url.username||url.password||url.port||url.search||url.hash||!['','/'].includes(url.pathname)||!apiKey||!secret)fail(503,'calls_unavailable');
 return {url:url.origin,apiURL:'https://'+url.hostname,apiKey,secret};
}
export function createCallServices(readEnvironment,fetchImpl=fetch){
 function config(){
  const url=readEnvironment('SUPABASE_URL')?.replace(/\/$/,'');const serviceRoleKey=readEnvironment('SUPABASE_SERVICE_ROLE_KEY');const anonKey=readEnvironment('SUPABASE_ANON_KEY');
  if(!url?.startsWith('https://')||!serviceRoleKey||!anonKey)fail(503,'calls_unavailable');
  return {url,serviceRoleKey,anonKey};
 }
 async function rpc(name,parameters){
  const cfg=config();let response;
  try{response=await fetchImpl(cfg.url+'/rest/v1/rpc/'+name,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{apikey:cfg.serviceRoleKey,Authorization:'Bearer '+cfg.serviceRoleKey,'Content-Type':'application/json'},body:JSON.stringify(parameters)});}
  catch{fail(503,'calls_unavailable');}
  let value;try{const text=await response.text();if(text.length>65536)throw Error();value=text?JSON.parse(text):null;}catch{fail(503,'calls_unavailable');}
  if(!response.ok){const status=SAFE_ERRORS.get(value?.message);fail(status??503,status?value.message:'calls_unavailable');}
  return value;
 }
 async function liveKit(method,parameters,video,allowMissing=false){
  const cfg=liveKitConfiguration(readEnvironment);const token=await signLiveKitJWT(cfg.apiKey,cfg.secret,{video});let response;
  try{response=await fetchImpl(cfg.apiURL+'/twirp/livekit.RoomService/'+method,{method:'POST',redirect:'error',signal:AbortSignal.timeout(5000),headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(parameters)});}
  catch{fail(503,'rtc_cleanup_failed');}
  if(!response.ok){let code;try{code=(await response.json())?.code;}catch{}
   if(!(allowMissing&&response.status===404&&code==='not_found'))fail(503,method==='CreateRoom'?'calls_unavailable':'rtc_cleanup_failed');}
 }
 return {
  requireRTC:()=>liveKitConfiguration(readEnvironment),
  authenticate:token=>authenticateUser(token,config(),fetchImpl,{allowAnonymous:true}),
  action:(actor,body)=>rpc('call_action',{actor_user_id:actor.userId,actor_session_id:actor.sessionId,action:body.action,target_call_id:body.call_id??null,target_user_id:body.target_user_id??null,call_kind:body.kind??null}),
  prepareRoom:room=>liveKit('CreateRoom',{name:room,empty_timeout:60,departure_timeout:20,max_participants:2},{roomCreate:true}),
  async joinToken(result){const cfg=liveKitConfiguration(readEnvironment);const now=Math.floor(Date.now()/1000);return {url:cfg.url,token:await signLiveKitJWT(cfg.apiKey,cfg.secret,{sub:result.identity,video:joinGrant(result.room_name,result.call.kind)},now),expires_at:new Date((now+120)*1000).toISOString()};},
  claimCleanup:token=>rpc('claim_call_cleanup',{worker_token:token}),
  finishCleanup:(job,succeeded,errorCode)=>rpc('finish_call_cleanup',{target_call_id:job.call_id,target_lease_id:job.lease_id,succeeded,error_code:succeeded?null:errorCode}),
  async cleanupRoom(job){
   liveKitConfiguration(readEnvironment);
   // Explicit future cutoff covers tokens minted in this same second. Cloud
   // accepts cutoffs within 60 seconds; these opaque identities are never reused.
   let failed=false;
   for(const identity of job.identities){
    try{await liveKit('RemoveParticipant',{room:job.room_name,identity,revoke_token_ts:String(Math.floor(Date.now()/1000)+2)},{roomAdmin:true,room:job.room_name},true);}
    catch{failed=true;}
   }
   // Still disconnect the room when a single revocation API request fails.
   // Keep the entire job pending until both revocations and deletion succeed.
   try{await liveKit('DeleteRoom',{room:job.room_name},{roomCreate:true},true);}catch{failed=true;}
   if(failed)fail(503,'rtc_cleanup_failed');
  },
 };
}
