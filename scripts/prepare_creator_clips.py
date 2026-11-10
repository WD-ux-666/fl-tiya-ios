#!/usr/bin/env python3
"""Inspect user-provided portrait MP4s and extract real frame covers locally.

No networking/auth/upload/approval. Uses existing macOS avconvert/Quick Look;
original video bytes remain unchanged in a private cache. CSV attribution is
preserved as user-provided metadata, without inventing a media license.
"""
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import uuid
sys.dont_write_bytecode=True
from prepare_seed_clips import atoms,child,private_directory
ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('/Users/shangbao666/Desktop/人物短视频_5条_20261105')
CACHE=Path('/Users/shangbao666/.codex/private/fl-tiya-ios/creator-clips-2026-11-05')
MANIFEST=ROOT/'supabase/content/development-creator-clips-2026-11-05.json'
OWNER='0a8b2ca1-9e56-4843-828c-07f560fabd2a'
PROJECT='gpstwmffctwqlcakmvgw'
MAX_BYTES=32*1024*1024

def require(value,message):
 if not value:raise RuntimeError(message)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def inspect_mp4(path):
 data=path.read_bytes();require(0<len(data)<=MAX_BYTES,'Video exceeds native byte bound')
 top=list(atoms(data));require(any(x[0]==b'ftyp' for x in top) and any(x[0]==b'mdat' for x in top),'Invalid MP4 media container')
 moov=next(x for x in top if x[0]==b'moov');tracks=[]
 for trak in atoms(data,moov[1],moov[2]):
  if trak[0]!=b'trak':continue
  mdia=child(data,trak,b'mdia');handler=child(data,mdia,b'hdlr') if mdia else None
  if not handler:continue
  kind=data[handler[1]+8:handler[1]+12];mdhd=child(data,mdia,b'mdhd');o=mdhd[1]
  if data[o]==1:scale=struct.unpack_from('>I',data,o+20)[0];duration=struct.unpack_from('>Q',data,o+24)[0]
  elif data[o]==0:scale,duration=struct.unpack_from('>II',data,o+12)
  else:raise RuntimeError('Unsupported MP4 header')
  minf=child(data,mdia,b'minf');stbl=child(data,minf,b'stbl');stsd=child(data,stbl,b'stsd');codec=data[stsd[1]+12:stsd[1]+16].decode('ascii')
  t={'kind':kind.decode('ascii'),'codec':codec,'duration_seconds':round(duration/scale,3)}
  if kind==b'vide':
   tkhd=child(data,trak,b'tkhd');w,h=struct.unpack_from('>II',data,tkhd[2]-8);t['dimensions']=[round(w/65536),round(h/65536)]
  tracks.append(t)
 video=next(t for t in tracks if t['kind']=='vide');require(video['codec'] in ('avc1','hvc1') and all(0<x<=4096 for x in video['dimensions']) and 0<video['duration_seconds']<=30,'Unexpected portrait AVC/HEVC geometry/duration')
 return {'video':video,'tracks':tracks}
def png_dimensions(path):
 d=path.read_bytes();require(d[:8]==b'\x89PNG\r\n\x1a\n' and len(d)<=2*1024*1024,'Invalid/oversized frame cover');dims=list(struct.unpack_from('>II',d,16));require(all(0<x<=4096 for x in dims),'Oversized cover dimensions');return dims

def prepare():
 private_directory(CACHE);rows=list(csv.DictReader((SOURCE/'来源清单.csv').open(encoding='utf-8-sig',newline='')));require(len(rows)==5,'Expected five local sources')
 existing=json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {};prior={c['id']:c for c in existing.get('clips',[])};clips=[]
 for r in rows:
  src=SOURCE/r['文件名'];require(src.parent==SOURCE and src.is_file() and not src.is_symlink(),'Unexpected local source');details=inspect_mp4(src);require(src.stat().st_size==int(r['文件大小_字节']),'CSV size mismatch');require(abs(details['video']['duration_seconds']-float(r['时长_秒']))<.12,'CSV duration mismatch')
  pid=str(uuid.uuid5(uuid.NAMESPACE_URL,r['原视频链接']));folder=CACHE/pid;private_directory(folder);media=folder/'video.mp4';cover=folder/'cover.png'
  if media.exists():require(sha(media)==sha(src),'Existing immutable cache differs')
  else:shutil.copyfile(src,media)
  media.chmod(0o600)
  if not cover.exists():
   q=folder/'cover-work';private_directory(q);subprocess.run(['/usr/bin/qlmanage','-t','-s','640','-o',str(q),str(media)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=35);os.replace(q/'video.mp4.png',cover);q.rmdir()
  cover.chmod(0o600);dims=png_dimensions(cover);samples=[]
  for label,at in [('start',.5),('middle',details['video']['duration_seconds']/2),('end',details['video']['duration_seconds']-.6)]:
   sample=folder/(label+'.mp4');frame=folder/(label+'.png')
   if not frame.exists():
    if not sample.exists():subprocess.run(['/usr/bin/avconvert','--source',str(media),'--preset','Preset640x480','--output',str(sample),'--start',str(round(at,3)),'--duration','0.25'],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45)
    sample.chmod(0o600);q=folder/(label+'-work');private_directory(q);subprocess.run(['/usr/bin/qlmanage','-t','-s','640','-o',str(q),str(sample)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=35);os.replace(q/(sample.name+'.png'),frame);q.rmdir()
   frame.chmod(0o600);png_dimensions(frame);samples.append({'label':label,'requested_seconds':round(at,3),'local_file':str(frame),'sha256':sha(frame)})
  title=r['创作者']+' — '+r['原视频标题'].strip();caption=title+'\nCreator: '+r['创作者']+'.\nSource: '+r['原视频链接']+'\nUser-provided video; original audio/video unchanged; real frame cover extracted.';require(len(caption)<=500,'Caption too long')
  c={'id':pid,'owner_id':OWNER,'game_id':None,'content_category':'lifestyle','title':title,'creator':r['创作者'],'source_title':r['原视频标题'].strip(),'source_url':r['原视频链接'],'source_date_csv':r['发布日期'],'source_platform':r['平台'],'source_metadata_provenance':'User-provided source CSV; no independent identity/license attestation','upload_authorization':'User explicitly requested upload and publication of these local files on 2026-11-05','license':'No additional license asserted; original creator rights retained','local_source':str(src),'source_sha256':sha(src),'source_bytes':src.stat().st_size,'media_sha256':sha(media),'media_bytes':media.stat().st_size,'media_type':'video/mp4','media_codec':details['video']['codec'],'duration_seconds':details['video']['duration_seconds'],'media_dimensions':details['video']['dimensions'],'tracks':details['tracks'],'thumbnail_sha256':sha(cover),'thumbnail_bytes':cover.stat().st_size,'thumbnail_dimensions':dims,'thumbnail_media_type':'image/png','video_path':OWNER+'/'+pid+'/video.mp4','thumbnail_path':OWNER+'/'+pid+'/cover.png','caption':caption,'local_cache_directory':str(folder),'decoded_review_samples':samples,'visual_review':prior.get(pid,{}).get('visual_review','pending'),'audio_review':'Track/container inspected; audio not listened to','preparation_status':'prepared-awaiting-visual-review'};clips.append(c);print(json.dumps({'creator':c['creator'],'id':pid,'bytes':c['media_bytes'],'duration':c['duration_seconds'],'dimensions':c['media_dimensions'],'cover':str(cover)},ensure_ascii=False),flush=True)
  MANIFEST.write_text(json.dumps({'project_ref':PROJECT,'cohort':'development','source_directory':str(SOURCE),'source_csv_sha256':sha(SOURCE/'来源清单.csv'),'clips':clips},ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':
 os.umask(0o077)
 try:prepare()
 except Exception as e:print('Preparation stopped:',type(e).__name__,str(e));raise SystemExit(1)
