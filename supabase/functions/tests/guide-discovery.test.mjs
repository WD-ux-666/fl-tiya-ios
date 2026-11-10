import test from 'node:test';
import assert from 'node:assert/strict';
const module = await import('../_shared/guide-discovery.mjs').catch(() => null);

test('guide discovery accepts safe official metadata and drops article bodies', () => {
 assert.equal(typeof module?.parseGuideRSS, 'function', 'The metadata-only RSS implementation is missing');
 const result = module.parseGuideRSS(feed(item()));
 assert.deepEqual(result, [{source_key:'steam_zzz_official_rss', source_guid:URL, source_url:URL,
  title:'Version 3.3 "Journey to the Sky" Update Announcement', source_author:'Overtimeboo',
  source_published_at:'2026-10-20T23:00:24.000Z', content_kind:'news'}]);
 assert.equal(JSON.stringify(result).includes('secret body'), false);
});

const URL='https://steamcommunity.com/games/4162040/announcements/detail/652616887841064662';
const item=(changes={})=>{
 const fields={title:'Version 3.3 &quot;Journey to the Sky&quot; Update Announcement',link:URL,
  guid:URL,pubDate:'Tue, 20 Oct 2026 23:00:24 +0000',author:'Overtimeboo',...changes};
 return '<item>'+Object.entries(fields).filter(([,v])=>v!==null).map(([k,v])=>`<${k}>${v}</${k}>`).join('')+
  '<description><![CDATA[<img src="https://evil.invalid/a">secret body]]></description></item>';
};
const feed=items=>`<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>ZZZ</title>${items}</channel></rss>`;

if(module) {
 test('authors are metadata and do not determine publisher identity',()=>{
  assert.equal(module.parseGuideRSS(feed(item({author:'shijie.hong'})))[0].source_author,'shijie.hong');
  assert.equal(module.parseGuideRSS(feed(item({author:null})))[0].source_author,null);
 });
 test('missing, malformed, duplicate, unsafe and non-app metadata is skipped',()=>{
  for(const changes of [{title:null},{link:null},{guid:null},{pubDate:null},{pubDate:'yesterday'},
   {title:'&unknown;'},{title:'bare & invalid'},{title:'<![CDATA[<script>bad</script>]]>'},{title:'A'.repeat(201)},
   {link:URL+'?url=https://evil.invalid'},{link:URL.replace('4162040','570')},
   {link:URL.replace('https:','http:')},{link:URL.replace('steamcommunity.com','steamcommunity.com.evil.invalid')},
   {guid:'https://evil.invalid/'},{author:'bad\u0001author'}]) assert.deepEqual(module.parseGuideRSS(feed(item(changes))),[],JSON.stringify(changes));
  assert.deepEqual(module.parseGuideRSS(feed(item().replace('</item>','<title>Duplicate</title></item>'))),[]);
 });
 test('parser rejects declarations, entity expansion and malformed XML',()=>{
  for(const xml of ['<!DOCTYPE rss [<!ENTITY x "boom">]>'+feed(item()), '<!ENTITY x "boom">'+feed(item()),
   feed(item()).replace('</channel>','</rss>'), '<rss/>', '<rss><channel>'+item(), '<feed/>'])
   assert.throws(()=>module.parseGuideRSS(xml));
 });
 test('item bound, entity decoding and duplicate suppression are observable',()=>{
  const items=Array.from({length:25},(_,i)=>item({link:URL.replace(/\d+$/,'')+String(7000+i),guid:URL.replace(/\d+$/,'')+String(7000+i)})).join('');
  assert.equal(module.parseGuideRSS(feed(items)).length,20);
  assert.equal(module.parseGuideRSS(feed(item()+item())).length,1);
  assert.equal(module.parseGuideRSS(feed(item({title:'<![CDATA[Plain & simple]]>'})))[0].title,'Plain & simple');
 });
 test('classification never converts update announcements into guides',()=>{
  const titles=[['Version 3.3 Update — New Agent Guides','news'],['Combat Gameplay Guide','guide'],
   ['How to Fix the Issue of Linking the Wrong HoYoverse Account','support'],['Official FAQ','reference']];
  for(const [title,kind] of titles) assert.equal(module.parseGuideRSS(feed(item({title})))[0].content_kind,kind);
 });
 test('robots uses matching user-agent, longest path and allow on equal match',()=>{
  assert.equal(module.robotsAllowRSS('User-agent: *\nDisallow: /actions/\n'),true);
  assert.equal(module.robotsAllowRSS('<html>temporarily unavailable</html>'),false);
  assert.equal(module.robotsAllowRSS('User-agent: *\nDisallow: /games/\n'),false);
  assert.equal(module.robotsAllowRSS('User-agent: *\nDisallow: /games/\nAllow: /games/4162040/rss/\n'),true);
  assert.equal(module.robotsAllowRSS('User-agent: *\nDisallow: /\nUser-agent: FL-Tiya-GuideDiscovery\nAllow: /games/4162040/rss/\n'),true);
  assert.equal(module.robotsAllowRSS('User-agent: *\nDisallow: /*/4162040/*\n'),false);
 });
 test('stream limit counts received bytes even without Content-Length',async()=>{
  const response=new Response(new ReadableStream({start(c){c.enqueue(new Uint8Array(300000));c.enqueue(new Uint8Array(300000));c.close();}}));
  await assert.rejects(module.readBoundedText(response,524288),{code:'source_too_large'});
 });
 test('an aborted body read fails promptly instead of awaiting an endless stream',async()=>{
  const controller=new AbortController();controller.abort();
  await assert.rejects(module.readBoundedText(new Response(new ReadableStream({start(){}})),524288,controller.signal),{code:'source_timeout'});
 });
 test('declared oversize and invalid UTF-8 are rejected',async()=>{
  await assert.rejects(module.readBoundedText(new Response('x',{headers:{'Content-Length':'524289'}}),524288),{code:'source_too_large'});
  await assert.rejects(module.readBoundedText(new Response(new Uint8Array([255])),524288),{code:'source_invalid_encoding'});
 });
 test('the collector fetches only robots and fixed RSS and respects restrictions',async()=>{
  const urls=[];
  const fetcher=async (url,options)=>{urls.push(url); assert.equal(options.redirect,'manual');
   assert.equal(options.headers.apikey,undefined); return new Response(url.endsWith('robots.txt')?'User-agent: *\nDisallow: /games/':feed(item()));};
  await assert.rejects(module.collectGuideCandidates(fetcher),{code:'robots_disallowed'});
  assert.deepEqual(urls,['https://steamcommunity.com/robots.txt']);
 });
 test('redirects and non-success replies are never followed',async()=>{
  for(const status of [301,302,307,403,429]){
   let count=0; await assert.rejects(module.collectGuideCandidates(async()=>{count++;return new Response('',{status,headers:{Location:'https://evil.invalid/'}});}));
   assert.equal(count,1);
  }
 });
 test('collector ignores RSS bodies and returns the same bounded metadata',async()=>{
  const result=await module.collectGuideCandidates(async u=>new Response(u.endsWith('robots.txt')?'User-agent: *\nDisallow: /actions/':feed(item())));
  assert.equal(result.length,1); assert.equal(result[0].source_url,URL); assert.equal(result[0].summary,undefined);
 });
 test('unauthenticated or wrong-method requests cause no privileged side effect',async()=>{
  const handler=module.createGuideDiscoveryHandler({claim:()=>{throw Error('must not run');}});
  assert.equal((await handler(new Request('https://example.invalid/',{method:'GET'}))).status,405);
  assert.equal((await handler(new Request('https://example.invalid/',{method:'POST'}))).status,401);
  assert.equal((await handler(new Request('https://example.invalid/',{method:'POST',headers:{'x-fltiya-crawl-token':'short'}}))).status,401);
 });
 test('invalid, disabled and rate-limited token claims never collect',async()=>{
  for(const [status,http] of [['unauthorized',401],['disabled',503],['rate_limited',429]]){
   const handler=module.createGuideDiscoveryHandler({claim:async()=>({status}),collect:()=>{throw Error('must not fetch');}});
   assert.equal((await handler(request())).status,http);
  }
 });
 test('a valid claim ignores arbitrary body URLs and only finishes pending metadata',async()=>{
  let claimed,finished;
  const handler=module.createGuideDiscoveryHandler({claim:async h=>{claimed=h;return {status:'claimed',run_id:RUN};},
   collect:async()=>module.parseGuideRSS(feed(item())),finish:async(...args)=>{finished=args;return {status:'completed',inserted_count:1};}});
  const response=await handler(request('{"url":"https://evil.invalid/"}'));
  assert.equal(response.status,200); assert.match(claimed,/^[a-f0-9]{64}$/); assert.notEqual(claimed,'a'.repeat(64));
  assert.equal(finished[0],RUN); assert.equal(finished[1][0].source_url,URL);assert.deepEqual(finished[2],[]);
  assert.equal(finished[1][0].status,undefined);assert.equal(finished[1][0].body_html,undefined);
 });
 test('source errors finalize the run with safe codes, never exception details',async()=>{
  let recorded;const handler=module.createGuideDiscoveryHandler({claim:async()=>({status:'claimed',run_id:RUN}),
   collect:async()=>{throw Error('token or upstream private body');},finish:async(...args)=>{recorded=args;return {status:'failed',inserted_count:0};}});
  const response=await handler(request()); assert.equal(response.status,502);
  assert.deepEqual(recorded,[RUN,[],[{code:'source_unavailable'}]]);
  assert.equal((await response.text()).includes('private body'),false);
 });
 test('service calls use only automatic environment credentials and fixed RPC paths',async()=>{
  const calls=[];const services=module.createGuideDiscoveryServices(name=>({SUPABASE_URL:'https://gpstwmffctwqlcakmvgw.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-server-key'}[name]),async(url,options)=>{
   calls.push({url,options});return new Response(JSON.stringify(url.endsWith('claim_guide_crawl')?{status:'claimed',run_id:RUN}:{status:'completed',inserted_count:0}));});
  await services.claim('b'.repeat(64));await services.finish(RUN,[],[]);
  assert.deepEqual(calls.map(x=>x.url),['https://gpstwmffctwqlcakmvgw.supabase.co/rest/v1/rpc/claim_guide_crawl','https://gpstwmffctwqlcakmvgw.supabase.co/rest/v1/rpc/finish_guide_crawl']);
  assert.equal(calls[0].options.headers.apikey,'test-server-key');assert.equal(calls[0].options.redirect,'manual');
  assert.deepEqual(JSON.parse(calls[0].options.body),{p_token_hash:'b'.repeat(64)});
 });
}
const RUN='be058550-318b-44b6-b1e5-b325141c5575';
const request=(body='')=>new Request('https://example.invalid/collect-guide-candidates',{method:'POST',headers:{'x-fltiya-crawl-token':'a'.repeat(64)},body});
