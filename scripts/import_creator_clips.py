#!/usr/bin/env python3
"""Reviewed five-file import and guarded catalog rotation, authorized project only.

Render modes write inert SQL. Upload uses a fresh existing development-owner
session and immutable paths; verification checks private boundary and hashes.
Approval/archive SQL is separately executed only after successful review/readback.
No credentials are printed or stored. Old media is never deleted.
"""
import argparse,hashlib,json,stat,sys
from pathlib import Path
sys.dont_write_bytecode=True
from import_development_clips import Client,request,digest
from prepare_creator_clips import CACHE,MANIFEST,OWNER,PROJECT,MAX_BYTES,inspect_mp4
ROOT=Path(__file__).resolve().parents[1]
CONTENT=ROOT/'supabase/content'
SNAPSHOT=CONTENT/'development-catalog-before-2026-11-05.json'
DENIED=(400,401,403,404)
EXPECTED={'bc761749-e6fd-5f5f-8a1d-4d396ac3d208','51628a69-1010-5201-b5bc-20346473161f','2e2427e1-3045-5770-8217-f47fe942efa1','3f6877fa-0e13-59d4-8316-afafba965d25','d18a4edb-2345-5269-b1ea-7cb96882f31b'}
BASE='https://'+PROJECT+'.supabase.co'
def require(v,m):
 if not v:raise RuntimeError(m)
def quote(v):return "'"+str(v).replace("'","''")+"'"
def files(manifest):
 require(manifest['project_ref']==PROJECT and manifest['cohort']=='development','Wrong project/cohort')
 require({c['id'] for c in manifest['clips']}==EXPECTED and len(manifest['clips'])==5,'Unexpected new registry')
 require(len(manifest['retained_ids'])==5 and len(manifest['archived_ids'])==7 and len(set(manifest['retained_ids']+manifest['archived_ids']))==12,'Unexpected retention registry')
 out={}
 for c in manifest['clips']:
  require(c['owner_id']==OWNER and c['game_id'] is None and c['content_category']=='lifestyle','False game/category assignment')
  require(c['visual_review']=='accepted','Review incomplete')
  folder=CACHE/c['id'];require(str(folder)==c['local_cache_directory'] and folder.is_dir() and not folder.is_symlink(),'Wrong private cache')
  require(digest(Path(c['local_source']).read_bytes())==c['source_sha256']==c['media_sha256'],'Original video changed')
  require(inspect_mp4(folder/'video.mp4')['video']['codec']==c['media_codec'],'Unexpected video codec')
  for name,key,bytes_key,sha_key,mime,limit in [('video.mp4','video_path','media_bytes','media_sha256','video/mp4',MAX_BYTES),('cover.png','thumbnail_path','thumbnail_bytes','thumbnail_sha256','image/png',2*1024*1024)]:
   p=folder/name;data=p.read_bytes();require(p.is_file() and not p.is_symlink() and 0<len(data)<=limit and len(data)==c[bytes_key] and digest(data)==c[sha_key],'Frozen media changed')
   require(c[key]==OWNER+'/'+c['id']+'/'+name,'Wrong immutable path');out[c[key]]=(data,mime)
 require(len(out)==10,'Expected10 unique objects');return out
def sql_header():return "-- Authorized project "+PROJECT+"; no credentials. Generated SQL is not upload evidence.\nbegin;\nset local lock_timeout='5s';\nset local statement_timeout='30s';\n"
def expected_sql(m):
 rows=[]
 for c in m['clips']:
  rows.append('('+','.join([quote(c['id'])+'::uuid',quote(OWNER)+'::uuid',quote(c['caption']),quote(c['video_path']),quote(c['thumbnail_path']),str(c['media_bytes']),str(c['thumbnail_bytes']),quote(c['media_sha256']),quote(c['thumbnail_sha256'])])+')')
 s="create temporary table expected_new(id uuid primary key,owner_id uuid,caption text,video_path text,thumbnail_path text,video_bytes bigint,cover_bytes bigint,video_sha text,cover_sha text) on commit drop;\ninsert into expected_new values\n"+',\n'.join(rows)+';\n'
 snap=json.loads(SNAPSHOT.read_text());require(snap['project_ref']==PROJECT and len(snap['posts'])==12 and len(snap['objects'])==24,'Wrong archive snapshot')
 require({p['id'] for p in snap['posts']}==set(m['retained_ids']+m['archived_ids']),'Archive snapshot IDs differ')
 s+='create temporary table expected_old as select * from jsonb_populate_recordset(null::public.video_posts,'+quote(json.dumps(snap['posts'],ensure_ascii=False))+'::jsonb);\n'
 s+='lock table public.video_posts in share row exclusive mode;\n'
 return s
OLD_GUARD="""
 if (select count(*) from expected_old)<>12 or exists(select 1 from expected_old e left join public.video_posts p on p.id=e.id where p.id is null or to_jsonb(p) is distinct from to_jsonb(e)) then raise exception 'Old catalog differs from frozen snapshot';end if;
 if (select count(*) from public.video_posts where status='approved')<>12 then raise exception 'Approved baseline must be12';end if;
 if not private.account_is_eligible('0a8b2ca1-9e56-4843-828c-07f560fabd2a'::uuid) or not exists(select1 from private.accounts where user_id='0a8b2ca1-9e56-4843-828c-07f560fabd2a' and cohort='development' and state='active') then raise exception 'Expected eligible development owner';end if;
 if not exists(select 1 from storage.buckets where id='clips' and not public) then raise exception 'Expected private bucket';end if;
""".replace('select1','select 1')
def render_pending(m):
 sql=sql_header()+expected_sql(m)+"do $pending$ begin\n"+OLD_GUARD+"""
 if exists(select1 from public.video_posts p join expected_new e on p.id=e.id or p.video_path=e.video_path or p.thumbnail_path=e.thumbnail_path) then raise exception 'Pending path/ID already exists';end if;
 insert into public.video_posts(id,owner_id,game_id,content_category,caption,video_path,thumbnail_path)
 select id,owner_id,null,'lifestyle',caption,video_path,thumbnail_path from expected_new;
 if (select count(*) from public.video_posts p join expected_new e on e.id=p.id where p.status='pending')<>5 then raise exception 'Expected5 pending creator posts';end if;
end $pending$;
commit;
select id,status,content_category,game_id from public.video_posts where id in (select x->>'id' from jsonb_array_elements('""".replace('select1','select 1')+json.dumps([{'id':c['id']} for c in m['clips']])+"'::jsonb) x)::uuid[];\n"
 # Keep final result independent of temporary tables after commit.
 sql=sql[:sql.index('select id,status,content_category,game_id from public.video_posts where id in (select x')]+"select id,status,content_category,game_id from public.video_posts where id in ("+','.join(quote(c['id'])+'::uuid' for c in m['clips'])+") order by id;\n"
 (CONTENT/'development-creator-clips-2026-11-05-pending.sql').write_text(sql)
def render_approve(m):
 archives=','.join(quote(x)+'::uuid' for x in m['archived_ids']);final=','.join(quote(x)+'::uuid' for x in m['retained_ids']+[c['id'] for c in m['clips']]);sql=sql_header()+expected_sql(m)+"do $approve$ declare n integer; begin\n"+OLD_GUARD+"""
 if (select count(*) from public.video_posts p join expected_new e on e.id=p.id where p.status='pending' and p.owner_id=e.owner_id and p.game_id is null and p.content_category='lifestyle' and p.caption=e.caption and p.video_path=e.video_path and p.thumbnail_path=e.thumbnail_path and p.approved_at is null)<>5 then raise exception 'Pending creator rows differ';end if;
 if exists(select 1 from expected_new e where not exists(select 1 from storage.objects o where o.bucket_id='clips' and o.name=e.video_path and o.owner_id=e.owner_id::text and (o.metadata->>'size')::bigint=e.video_bytes and o.metadata->>'mimetype'='video/mp4') or not exists(select 1 from storage.objects o where o.bucket_id='clips' and o.name=e.thumbnail_path and o.owner_id=e.owner_id::text and (o.metadata->>'size')::bigint=e.cover_bytes and o.metadata->>'mimetype'='image/png')) then raise exception 'Missing/mismatched immutable objects';end if;
 insert into private.video_reviews(post_id,decision,reviewer_reference,notes)
 select id,'approved','user-provided-creator-import-2026-11-05','User explicitly requested these local files for test catalog. CSV creator/source attribution retained; no CC/public-release license asserted. Original MP4 byte SHA256='||video_sha||'; cover SHA256='||cover_sha||'. Start/middle/end decoded samples and cover reviewed; audio not listened to. Complete authenticated readbacks matched manifest.' from expected_new;
 update public.video_posts set status='approved',approved_at=statement_timestamp() where id in(select id from expected_new);
 get diagnostics n=row_count;if n<>5 then raise exception 'Expected5 creator approvals';end if;
 insert into private.video_reviews(post_id,decision,reviewer_reference,notes)
 select id,'rejected','user-catalog-archive-2026-11-05','Catalog archive requested by user to replace7 older/niche clips. NOT a safety rejection. Original row and review history frozen in development-catalog-before-2026-11-05.json; private video/cover objects retained.' from public.video_posts where id in ("""+archives+");\nupdate public.video_posts set status='rejected',approved_at=null where id in ("+archives+");\nget diagnostics n=row_count;if n<>7 then raise exception 'Expected7 archived posts';end if;\nif (select count(*) from public.video_posts where status='approved')<>10 or exists(select1 from public.video_posts where status='approved' and id not in ("+final+")) then raise exception 'Final approved catalog differs from exact10';end if;\nend $approve$;\ncommit;\nselect status,count(*) from public.video_posts group by status order by status;\n"
 (CONTENT/'development-creator-clips-2026-11-05-approve.sql').write_text(sql.replace('select1','select 1'))
 # Inert compensating action. Restores old approval timestamps and archives the
 # new5; no row/object deletion and no automatic execution by this helper.
 review_count=len(json.loads(SNAPSHOT.read_text())['reviews'])+12
 restore=sql_header()+expected_sql(m)+"do $restore$ begin\nif (select count(*) from private.video_reviews where post_id in(select id from expected_old union select id from expected_new))<>"+str(review_count)+" then raise exception 'Target review history changed since refresh';end if;\nif (select count(*) from public.video_posts where status='approved')<>10 or exists(select 1 from public.video_posts where status='approved' and id not in ("+final+")) then raise exception 'Current approved IDs differ from exact final10';end if;\nif exists(select 1 from expected_old e left join public.video_posts p on p.id=e.id where p.id is null or (to_jsonb(p)-'status'-'approved_at') is distinct from (to_jsonb(e)-'status'-'approved_at')) then raise exception 'Old immutable catalog fields changed';end if;\nif (select count(*) from public.video_posts where id in ("+archives+") and status='rejected' and approved_at is null)<>7 then raise exception 'Archive state changed after refresh';end if;\nif exists(select 1 from expected_old e join public.video_posts p on p.id=e.id where p.id not in ("+archives+") and to_jsonb(p) is distinct from to_jsonb(e)) then raise exception 'Retained catalog rows changed';end if;\nif (select count(*) from public.video_posts p join expected_new e on p.id=e.id where p.owner_id=e.owner_id and p.caption=e.caption and p.video_path=e.video_path and p.thumbnail_path=e.thumbnail_path and p.game_id is null and p.content_category='lifestyle' and p.status='approved' and p.approved_at is not null)<>5 then raise exception 'New creator row state/metadata changed';end if;\nif (select count(*) from private.video_reviews where reviewer_reference='user-provided-creator-import-2026-11-05' and post_id in(select id from expected_new))<>5 or (select count(*) from private.video_reviews where reviewer_reference='user-catalog-archive-2026-11-05' and post_id in ("+archives+"))<>7 then raise exception 'Original rotation audit missing or duplicated';end if;\nupdate public.video_posts p set status=e.status,approved_at=e.approved_at from expected_old e where p.id=e.id and p.id in ("+archives+");\ninsert into private.video_reviews(post_id,decision,reviewer_reference,notes) select id,'approved','catalog-refresh-compensation-2026-11-05','Explicit compensating restoration from frozen pre-refresh snapshot.' from expected_old where id in ("+archives+");\ninsert into private.video_reviews(post_id,decision,reviewer_reference,notes) select id,'rejected','catalog-refresh-compensation-2026-11-05','New creator clip archived during explicit catalog restoration; media retained.' from expected_new;\nupdate public.video_posts set status='rejected',approved_at=null where id in(select id from expected_new);\nif (select count(*) from public.video_posts where status='approved')<>12 then raise exception 'Restoration expected12 approved';end if;\nend $restore$;\ncommit;\n"
 (CONTENT/'development-creator-clips-2026-11-05-restore.sql').write_text(restore)
def metadata(client,m):
 ids=','.join(c['id'] for c in m['clips']);status,data=client.call('/rest/v1/video_posts?select=id,owner_id,game_id,content_category,caption,video_path,thumbnail_path,status,game:games(name)&id=in.('+ids+')');require(status==200,'Metadata HTTP '+str(status));return json.loads(data)
def upload(m,uploads):
 c=Client(m,'Development Alpha')
 try:
  require(c.base==BASE and c.user_id==OWNER,'Wrong uploader');rows=metadata(c,m);require(len(rows)==5 and all(r['status']=='pending' for r in rows),'Expected own5 pending rows')
  for path,(data,mime) in uploads.items():
   status,existing=c.call('/storage/v1/object/clips/'+path)
   if status==200:require(digest(existing)==digest(data),'Immutable object collision')
   else:
    require(status in (400,404),'Unexpected lookup HTTP '+str(status));status,_=request(BASE+'/storage/v1/object/clips/'+path,headers={'apikey':c.key,'Authorization':'Bearer '+c.token,'Content-Type':mime,'x-upsert':'false'},data=data,method='POST');require(status in (200,400,409),'Upload HTTP '+str(status))
   status,back=c.call('/storage/v1/object/clips/'+path);require(status==200 and digest(back)==digest(data),'Uploaded SHA mismatch');print(json.dumps({'path':path,'http':status,'bytes':len(back),'sha256':digest(back),'immutable_upload_verified':True}),flush=True)
 finally:c.close()
def verify(m,uploads,approved):
 c=Client(m,'Development Beta');results=[]
 try:
  rows=metadata(c,m);require((len(rows)==5 and all(r['status']=='approved' and r['content_category']=='lifestyle' and r['game_id'] is None and r['game'] is None for r in rows)) if approved else rows==[],'Peer metadata boundary failed')
  for path,(data,mime) in uploads.items():
   status,body=c.call('/storage/v1/object/clips/'+path);require(status==200 and digest(body)==digest(data) if approved else status in DENIED,'Peer media boundary failed');results.append({'path':path,'peer_http':status,'sha256_match':approved})
  report={'stage':'approved' if approved else 'pending','peer_rows':len(rows),'objects':results}
  if approved:
   status,payload=c.call('/rest/v1/video_posts?select=id,owner_id,game_id,content_category,caption,video_path,thumbnail_path,status,created_at,approved_at,game:games(name)&status=eq.approved&order=created_at.desc,id.desc&limit=50');home=json.loads(payload);expected=set(m['retained_ids'])|EXPECTED
   require(status==200 and len(home)==10 and {x['id'] for x in home}==expected,'Development Home is not exact10')
   require(sum(x['content_category']=='lifestyle' and x['game_id'] is None and x['game'] is None for x in home)==5,'Wrong Lifestyle shape')
   require(sum(x['content_category']=='gaming' and x['game_id'] is not None and x['game'] is not None for x in home)==5,'Wrong gaming shape')
   archived=','.join(m['archived_ids']);status,payload=c.call('/rest/v1/video_posts?select=id&id=in.('+archived+')');require(status==200 and json.loads(payload)==[],'Archived peer metadata visible')
   snapshot=json.loads(SNAPSHOT.read_text());archive_results=[]
   for post in snapshot['posts']:
    if post['id'] not in m['archived_ids']:continue
    for path in (post['video_path'],post['thumbnail_path']):
     status,_=c.call('/storage/v1/object/clips/'+path);require(status in DENIED,'Archived media remained peer readable');archive_results.append({'path':path,'peer_http':status})
   report.update({'home_rows':len(home),'home_categories':{'gaming':5,'lifestyle':5},'archived_metadata_rows':0,'archived_objects':archive_results})
  print(json.dumps(report),flush=True)
 finally:c.close()
def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['render-pending','render-approve','upload','verify-pending','verify-approved']);a=p.parse_args();m=json.loads(MANIFEST.read_text());u=files(m)
 if a.action=='render-pending':render_pending(m)
 elif a.action=='render-approve':render_approve(m)
 elif a.action=='upload':upload(m,u)
 else:verify(m,u,a.action=='verify-approved')
if __name__=='__main__':
 try:main()
 except Exception as e:print('Creator import stopped:',type(e).__name__,str(e));raise SystemExit(1)
