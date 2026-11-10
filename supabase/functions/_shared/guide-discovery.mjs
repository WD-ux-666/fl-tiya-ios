// One reviewed public adapter. Never accept source URLs or credentials from a request.
const SOURCE='steam_zzz_official_rss';
const RSS='https://steamcommunity.com/games/4162040/rss/';
const ROBOTS='https://steamcommunity.com/robots.txt';
const AGENT='FL-Tiya-GuideDiscovery';
const MAX_BYTES=524288;
const ITEM_URL=/^https:\/\/steamcommunity\.com\/games\/4162040\/announcements\/detail\/[0-9]{1,24}\/?$/;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FIELDS=new Set(['title','link','guid','pubDate','author']);
const SAFE_CODES=new Set(['source_too_large','source_invalid_encoding','source_timeout','source_http_error',
 'source_redirect','source_invalid_xml','robots_disallowed','source_unavailable']);
class DiscoveryError extends Error {
 constructor(code){ super(code);this.code=code; }
}
const fail=code=>{throw new DiscoveryError(code);};
const badText=value=>/[\u0000-\u001f\u007f<>]/.test(value);
function decodeXML(value){
 if(/&(?!(?:amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-f]+);)/i.test(value))throw Error('invalid_entity');
 return value.replace(/&([^;\s]{1,40});/g,(_all,entity)=>{
  const named={amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"};
  if(Object.hasOwn(named,entity))return named[entity];
  if(!/^#(?:[0-9]+|x[0-9a-f]+)$/i.test(entity))throw Error('invalid_entity');
  const n=entity[1]?.toLowerCase()==='x'?parseInt(entity.slice(2),16):Number(entity.slice(1));
  if(!Number.isInteger(n)||n<=0||n>0x10ffff||(n>=0xd800&&n<=0xdfff))throw Error('invalid_entity');
  return String.fromCodePoint(n);
 });
}
function classify(title){
 if(/^Version\s+\d/i.test(title))return 'news';
 if(/^How to Fix\b/i.test(title))return 'support';
 if(/\b(?:gameplay|beginner|combat|agent) guide\b/i.test(title))return 'guide';
 if(/\b(?:FAQ|character reference)\b/i.test(title))return 'reference';
 return 'news';
}
function normalizedItem(fields){
 try{
  const title=fields.title?.trim().replace(/\s+/g,' ');
  const link=fields.link?.trim(); const guid=fields.guid?.trim(); const date=fields.pubDate?.trim();
  const author=fields.author?.trim()||null;
  if(!title||title.length>200||badText(title)||!ITEM_URL.test(link??'')||!ITEM_URL.test(guid??'')||
   link.replace(/\/$/,'')!==guid.replace(/\/$/,'')||
   !/^[A-Za-z]{3}, \d{1,2} [A-Za-z]{3} \d{4} \d{2}:\d{2}:\d{2} (?:[+-]\d{4}|GMT)$/.test(date??'')||
   (author&&(author.length>120||badText(author))))return null;
  const parsed=new Date(date); if(!Number.isFinite(parsed.getTime())||parsed.getUTCFullYear()<2000||parsed.getUTCFullYear()>2100)return null;
  return {source_key:SOURCE,source_guid:guid.replace(/\/$/,''),source_url:link.replace(/\/$/,''),title,
   source_author:author,source_published_at:parsed.toISOString(),content_kind:classify(title)};
 }catch{return null;}
}

// A small non-validating XML reader for RSS metadata, with explicit structure and
// resource limits. It never resolves entities, fetches a DTD, or retains bodies.
export function parseGuideRSS(xml){
 if(typeof xml!=='string'||new TextEncoder().encode(xml).length>MAX_BYTES||/<!\s*(?:DOCTYPE|ENTITY)\b/i.test(xml))fail('source_invalid_xml');
 const stack=[];const result=[];const seen=new Set();let pos=0,items=0,nodes=0,current=null,rootSeen=false,channelSeen=false;
 const text=(value,cdata=false)=>{
  if(!stack.length&&value.trim())fail('source_invalid_xml');
  if(current&&stack.length===4&&FIELDS.has(stack[3])){
   try{current[stack[3]]+=(cdata?value:decodeXML(value));}catch{current.invalid=true;}
   if(current[stack[3]].length>5000)current.invalid=true;
  }
 };
 while(pos<xml.length){
  if(xml[pos]!=='<'){
   const end=xml.indexOf('<',pos); text(xml.slice(pos,end<0?xml.length:end));pos=end<0?xml.length:end;continue;
  }
  if(xml.startsWith('<!--',pos)){
   const end=xml.indexOf('-->',pos+4);if(end<0)fail('source_invalid_xml');pos=end+3;continue;
  }
  if(xml.startsWith('<![CDATA[',pos)){
   const end=xml.indexOf(']]>',pos+9);if(end<0||!stack.length)fail('source_invalid_xml');text(xml.slice(pos+9,end),true);pos=end+3;continue;
  }
  if(xml.startsWith('<?',pos)){
   const end=xml.indexOf('?>',pos+2);if(end<0||rootSeen)fail('source_invalid_xml');pos=end+2;continue;
  }
  let end=pos+1,quote=null;
  for(;end<xml.length;end++){
   const c=xml[end];if(quote){if(c===quote)quote=null;}else if(c==='"'||c==="'")quote=c;else if(c==='>')break;
  }
  if(end===xml.length||quote)fail('source_invalid_xml');
  const tag=xml.slice(pos,end+1);pos=end+1;
  const closing=/^<\/([A-Za-z_][\w.:-]*)\s*>$/.exec(tag);
  if(closing){
   const name=closing[1];if(stack.pop()!==name)fail('source_invalid_xml');
   if(name==='item'&&stack.join('/')==='rss/channel'){
    if(current&&!current.invalid){const item=normalizedItem(current);if(item&&!seen.has(item.source_url)){seen.add(item.source_url);result.push(item);}}
    current=null;
   }
   continue;
  }
  const opening=/^<([A-Za-z_][\w.:-]*)(?:\s+[A-Za-z_][\w.:-]*\s*=\s*(?:"[^"<>]*"|'[^'<>]*'))*\s*(\/?)>$/.exec(tag);
  if(!opening||++nodes>20000||stack.length>=16)fail('source_invalid_xml');
  const name=opening[1];
  if(!stack.length){if(rootSeen||name!=='rss')fail('source_invalid_xml');rootSeen=true;}
  if(stack.length===1){if(name!=='channel'||channelSeen)fail('source_invalid_xml');channelSeen=true;}
  if(current&&stack.length>=4&&FIELDS.has(stack[3]))current.invalid=true;
  if(name==='item'&&stack.join('/')==='rss/channel'){items++;current=items<=20?{}:null;}
  if(current&&stack.join('/')==='rss/channel/item'&&FIELDS.has(name)){
   if(Object.hasOwn(current,name))current.invalid=true;else current[name]='';
  }
  stack.push(name);
  if(opening[2]){
   stack.pop();
   if(name==='item'&&stack.join('/')==='rss/channel')current=null;
  }
 }
 if(stack.length||!rootSeen||!channelSeen)fail('source_invalid_xml');
 return result;
}

export function robotsAllowRSS(text){
 if(typeof text!=='string'||!text.trim())return false;
 const groups=[];let group={agents:[],rules:[]};let hasRules=false;
 for(const raw of text.split(/\r?\n/)){
  const line=raw.replace(/#.*$/,'').trim();if(!line)continue;
  const match=/^([a-z-]+)\s*:\s*(.*)$/i.exec(line);if(!match)continue;
  const key=match[1].toLowerCase(),value=match[2].trim();
  if(key==='user-agent'){
   if(hasRules){groups.push(group);group={agents:[],rules:[]};hasRules=false;}
   group.agents.push(value.toLowerCase());
  }else if(['allow','disallow'].includes(key)&&group.agents.length){hasRules=true;if(value)group.rules.push({allow:key==='allow',path:value});}
 }
 groups.push(group);
 if(!groups.some(g=>g.agents.some(Boolean)))return false;
 const product=AGENT.toLowerCase();
 const specific=groups.filter(g=>g.agents.some(a=>a&&a!=='*'&&product.includes(a)));
 const applicable=specific.length?specific:groups.filter(g=>g.agents.includes('*'));
 let best=-1,allowed=true;
 for(const {path,allow} of applicable.flatMap(g=>g.rules)){
  const escaped=path.replace(/[.+?^{}()|[\]\\]/g,'\\$&').replace(/\*/g,'.*').replace(/\$$/,'$');
  let matches=false;try{matches=new RegExp('^'+escaped).test('/games/4162040/rss/');}catch{return false;}
  if(matches){const length=path.replace(/[\*$]/g,'').length;if(length>best||(length===best&&allow)){best=length;allowed=allow;}}
 }
 return allowed;
}

export async function readBoundedText(response,limit,signal){
 if(Number(response.headers.get('content-length'))>limit){await response.body?.cancel();fail('source_too_large');}
 if(!response.body)return '';
 const reader=response.body.getReader(),chunks=[];let bytes=0;
 let onAbort;const aborted=new Promise((_,reject)=>{onAbort=()=>reject(new DiscoveryError('source_timeout'));if(signal?.aborted)onAbort();else signal?.addEventListener('abort',onAbort,{once:true});});
 try{
  while(true){const {done,value}=await (signal?Promise.race([reader.read(),aborted]):reader.read());if(done)break;bytes+=value.byteLength;
   if(bytes>limit){await reader.cancel();fail('source_too_large');}chunks.push(value);}
  const joined=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.length;}
  try{return new TextDecoder('utf-8',{fatal:true}).decode(joined);}catch{fail('source_invalid_encoding');}
 }finally{signal?.removeEventListener('abort',onAbort);reader.releaseLock();}
}
async function boundedFetch(url,fetchImpl,limit,options={}){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),12000);
 try{
  const response=await fetchImpl(url,{...options,redirect:'manual',signal:controller.signal});
  if(response.status>=300&&response.status<400){await response.body?.cancel();fail('source_redirect');}
  if(!response.ok){await response.body?.cancel();fail('source_http_error');}
  return await readBoundedText(response,limit,controller.signal);
 }catch(error){if(controller.signal.aborted)fail('source_timeout');throw error;}
 finally{clearTimeout(timer);}
}
export async function collectGuideCandidates(fetchImpl=fetch){
 const options={headers:{'User-Agent':AGENT+'/1.0','Accept':'application/rss+xml, application/xml, text/xml, text/plain'}};
 const robots=await boundedFetch(ROBOTS,fetchImpl,32768,options);
 if(!robotsAllowRSS(robots))fail('robots_disallowed');
 return parseGuideRSS(await boundedFetch(RSS,fetchImpl,MAX_BYTES,options));
}
const response=(status,body,headers={})=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store',...headers}});
const safeCode=error=>SAFE_CODES.has(error?.code)?error.code:'source_unavailable';
export function createGuideDiscoveryHandler(services){
 return async request=>{
  if(request.method!=='POST')return response(405,{error:'method_not_allowed'},{Allow:'POST'});
  const token=request.headers.get('x-fltiya-crawl-token')??'';
  if(!/^[a-f0-9]{64}$/.test(token))return response(401,{error:'unauthorized'});
  try{
   const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token));
   const hash=Array.from(new Uint8Array(digest),n=>n.toString(16).padStart(2,'0')).join('');
   const claim=await services.claim(hash);
   if(claim?.status==='unauthorized')return response(401,{error:'unauthorized'});
   if(claim?.status==='disabled')return response(503,{error:'discovery_disabled'});
   if(claim?.status==='rate_limited')return response(429,{error:'rate_limited'},{'Retry-After':'300'});
   if(claim?.status!=='claimed'||!UUID.test(claim.run_id??''))throw Error('invalid_claim');
   // The request body is intentionally not parsed. Source selection is fixed.
   let candidates=[],errors=[];
   try{candidates=await services.collect();}catch(error){errors=[{code:safeCode(error)}];}
   const finished=await services.finish(claim.run_id,candidates,errors);
   if(!['completed','failed','already_finished'].includes(finished?.status)||!Number.isInteger(finished.inserted_count))throw Error('invalid_finish');
   if(errors.length)return response(502,{status:'failed',run_id:claim.run_id,error:errors[0].code});
   return response(200,{status:finished.status,run_id:claim.run_id,candidates_inserted:finished.inserted_count});
  }catch{return response(503,{error:'discovery_unavailable'});}
 };
}
export function createGuideDiscoveryServices(readEnvironment,fetchImpl=fetch){
 async function rpc(name,body){
  const url=readEnvironment('SUPABASE_URL')?.replace(/\/$/,'');const key=readEnvironment('SUPABASE_SERVICE_ROLE_KEY');
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url??'')||!key)throw Error('unavailable');
  const text=await boundedFetch(url+'/rest/v1/rpc/'+name,fetchImpl,65536,{method:'POST',
   headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(body)});
  return JSON.parse(text);
 }
 return {claim:hash=>rpc('claim_guide_crawl',{p_token_hash:hash}),
  finish:(run,candidates,errors)=>rpc('finish_guide_crawl',{p_run_id:run,p_candidates:candidates,p_errors:errors}),
  collect:()=>collectGuideCandidates(fetchImpl)};
}
