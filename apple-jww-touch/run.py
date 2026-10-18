"""Native XCTest multi-finger input against hash-pinned public CAD in Simulator Safari."""
import base64,hashlib,io,json,os,re,subprocess,tarfile,threading,time,urllib.request,zipfile,plistlib,shutil,xml.etree.ElementTree as ET
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'output';OUT.mkdir(exist_ok=True);kind=os.environ['PROBE_DEVICE'];udid=None;sid=None;appium=None;scale=1;serial=0;latest={};events=[];errors=[]
report={'physicalDevice':False,'deviceKind':kind,'scope':'Apple Simulator Safari/XCTest native fingers; SHA-pinned public0.25.0 served on cloud loopback with test-only passive logs. Public JWWs; real Files picker attempted and separately assessed. Not physical devices or direct public URL.','cases':[]}
def save():(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
def cmd(args,label,timeout=60,check=True):
 global serial
 serial+=1
 try:p=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
 except subprocess.TimeoutExpired as e:
  (OUT/(str(serial)+'-'+label+'.log')).write_text('TIMEOUT '+str(timeout)+'s: '+str(args));raise
 (OUT/(str(serial)+'-'+label+'.log')).write_text(p.stdout+'\n'+p.stderr)
 if check and p.returncode:raise RuntimeError(label+' exit '+str(p.returncode))
 return p.stdout

def wait(predicate,seconds=15):
 end=time.time()+seconds
 while time.time()<end:
  if predicate():return
  time.sleep(.15)
 raise RuntimeError('Expected observed state did not arrive')
def req(method,path='',body=None,timeout=120):
 target='http://127.0.0.1:4723'+path;request=urllib.request.Request(target,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=timeout) as response:d=json.load(response)
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode()[:5000])
 value=d.get('value',d)
 if isinstance(value,dict) and value.get('error'):raise RuntimeError(str(value))
 return value

def call(method,path,body=None):return req(method,'/session/'+sid+path,body)
def native(points,dx=0,dy=0,release_order=0,observe=True):
 ups=sum(e['type']=='pointerup' for e in events)
 sources=[]
 for i,(x,y) in enumerate(points):
  sx,sy=round(x*scale+offset[0]),round(y*scale+offset[1]);actions=[{'type':'pointerMove','duration':0,'x':sx,'y':sy,'origin':'viewport'},{'type':'pointerDown','button':0},{'type':'pause','duration':150}]
  if dx or dy:actions.append({'type':'pointerMove','duration':500,'x':round(sx+dx*scale),'y':round(sy+dy*scale),'origin':'viewport'})
  else:actions.append({'type':'pause','duration':80})
  if len(points)==2:
   actions += [{'type':'pointerUp','button':0} if i==release_order else {'type':'pause','duration':0},{'type':'pause','duration':250},{'type':'pointerUp','button':0} if i!=release_order else {'type':'pause','duration':0}]
  else:actions.append({'type':'pointerUp','button':0})
  sources.append({'type':'pointer','id':'finger'+str(i),'parameters':{'pointerType':'touch'},'actions':actions})
 call('POST','/actions',{'actions':sources})
 if observe:
  wait(lambda:sum(e['type']=='pointerup' for e in events)>=ups+len(points),20)
  end=max(e['t'] for e in events if e['type']=='pointerup');wait(lambda:latest.get('t',0)>end,20)
 else:time.sleep(.45)
def tap(x,y,observe=True):native([[x,y]],observe=observe)
def control(name):r=latest['controls'][name];tap(r['x']+r['width']/2,r['y']+r['height']/2,observe=False)
def shot(name):
 if sid:(OUT/(name+'.png')).write_bytes(base64.b64decode(call('GET','/screenshot')))
 else:cmd(['xcrun','simctl','io',udid,'screenshot',str(OUT/(name+'.png'))],name,timeout=20,check=False)
def state():return json.loads(json.dumps(latest))
def check(name,b,a,passed):report['cases'].append({'name':name,'before':b,'after':a,'passed':bool(passed)});save();print(name,passed,flush=True)
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(html)
 def do_POST(self):
  global latest
  batch=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  for data in batch if isinstance(batch,list) else [batch]:
   if data['type']=='state':
    if data.get('t',0)>latest.get('t',-1):latest=data
   elif data['type']=='error':errors.append(data)
   else:events.append(data)
   with (OUT/'events.jsonl').open('a') as f:f.write(json.dumps(data)+'\n')
  self.send_response(200);self.end_headers()

def click_label(labels,contains=False):
 predicate=' OR '.join(('label CONTAINS '+json.dumps(s) if contains else 'label == '+json.dumps(s)) for s in labels)
 found=call('POST','/elements',{'using':'-ios predicate string','value':'visible == 1 AND ('+predicate+')'})
 if not found:return False
 eid=next(iter(found[0].values()));call('POST','/element/'+eid+'/click',{});time.sleep(.7);return True

def file_picker(sample):
 name=sample['name'];start=time.time();control('fileMenu');time.sleep(.5);control('open');time.sleep(1)
 visited={};trail=[]
 for step in range(14):
  if latest.get('title')==name+' − JWW':return {'passed':True,'seconds':time.time()-start,'trail':trail}
  xml=call('GET','/source');(OUT/(name+'-picker-'+str(step)+'.xml')).write_text(xml)
  if '保存していない変更を破棄しますか' in xml:
   call('POST','/alert/accept',{});trail.append('discard test edits');time.sleep(1);continue
  if click_label([name,name[:-4]],contains=True):trail.append(name);time.sleep(1);continue
  acted=False
  for labels in [['Choose File','Choose Files','ファイルを選択','ファイルを選ぶ'],['JWW Samples'],['On My iPhone','On My iPad','このiPhone内','このiPad内'],['Browse','ブラウズ']]:
   key=labels[0]
   if visited.get(key,0)>=2:continue
   if click_label(labels):visited[key]=visited.get(key,0)+1;trail.append(key);acted=True;break
  if not acted:
   shot(name+'-picker-stuck');break
 raise RuntimeError('File picker did not open '+name+' trail='+str(trail))

def prepare_files(config):
 byhash={}
 try:
  archivefile=OUT/'public-download.zip';cmd(['curl','--fail','--location','--max-time','40','--user-agent','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15','--referer','https://www.pref.aichi.jp/',config['zip'],'--output',str(archivefile)],'download-public');zf=zipfile.ZipFile(archivefile)
 except Exception as e:
  report['primaryDownloadError']=str(e);config['samples']=config['fallbackSamples'];zf=None
  import lhafile
  for index,s in enumerate(config['samples']):
   if not s.get('lha'):continue
   file=OUT/('public-'+str(index)+'.lzh');cmd(['curl','--fail','--location','--max-time','40',s['lha'],'--output',str(file)],'download-fallback');archive=lhafile.LhaFile(str(file))
   for name in archive.namelist():
    if name.lower().endswith('.jww'):
     data=archive.read(name);byhash[hashlib.sha256(data).hexdigest()]=data
 wanted={s['sha256'] for s in config['samples']}
 for entry in zf.infolist() if zf else []:
  if entry.filename.lower().endswith('.jww'):
   data=zf.read(entry);sha=hashlib.sha256(data).hexdigest()
   if sha in wanted:byhash[sha]=data
 app=OUT/'JWWFiles.app';app.mkdir();source=OUT/'files.m'
 source.write_text('#import <UIKit/UIKit.h>\n@interface A:UIResponder<UIApplicationDelegate>\n@property(strong,nonatomic) UIWindow *window;\n@end\n@implementation A\n-(BOOL)application:(UIApplication*)a didFinishLaunchingWithOptions:(NSDictionary*)o { self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[UIViewController new];self.window.rootViewController.view.backgroundColor=UIColor.whiteColor;[self.window makeKeyAndVisible];return YES;}\n@end\nint main(int argc,char**argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(A.class));}}')
 sdk=cmd(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],'sdk').strip();arch=cmd(['uname','-m'],'arch').strip()
 cmd(['xcrun','clang','-fobjc-arc','-target',arch+'-apple-ios17.0-simulator','-isysroot',sdk,'-framework','UIKit','-framework','Foundation',str(source),'-o',str(app/'JWWFiles')],'compile-files-helper',timeout=120)
 (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'JWWFiles','CFBundleIdentifier':'org.jwprobe.files','CFBundleName':'JWW Samples','CFBundleDisplayName':'JWW Samples','CFBundleVersion':'1','CFBundleShortVersionString':'1','CFBundlePackageType':'APPL','MinimumOSVersion':'17.0','UIDeviceFamily':[1,2],'UIFileSharingEnabled':True,'LSSupportsOpeningDocumentsInPlace':True,'UILaunchScreen':{}}))
 cmd(['codesign','--force','--sign','-',str(app)],'sign-files');documents=OUT/'fixture-files';documents.mkdir(exist_ok=True)
 for s in config['samples']:
  data=urllib.request.urlopen(s['url'],timeout=30).read() if s.get('url') else byhash[s['sha256']]
  if hashlib.sha256(data).hexdigest()!=s['sha256']:raise RuntimeError('Public sample hash mismatch')
  (documents/s['name']).write_bytes(data)
 report['samples']=config['samples'];save()

def install_files():
 cmd(['xcrun','simctl','install',udid,str(OUT/'JWWFiles.app')],'install-files',timeout=120);container=Path(cmd(['xcrun','simctl','get_app_container',udid,'org.jwprobe.files','data'],'files-container',timeout=120).strip());documents=container/'Documents';documents.mkdir(exist_ok=True)
 for source in (OUT/'fixture-files').iterdir():shutil.copy2(source,documents/source.name)
 cmd(['xcrun','simctl','launch',udid,'org.jwprobe.files'],'register-files',timeout=120);time.sleep(1)

try:
 config=json.loads((ROOT/'config.json').read_text());report['host']=cmd(['sw_vers'],'host')+cmd(['xcodebuild','-version'],'xcode')
 raw=urllib.request.urlopen(urllib.request.Request(config['url'],headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read().decode().replace('\r\n','\n').encode();prefix=raw[:config['codeBytes']]
 if hashlib.sha256(prefix).hexdigest()!=config['codeSha256']:raise RuntimeError('Public application changed')
 report['publicCodeSha256']=config['codeSha256'];html=prefix+(ROOT/'instrument.js').read_bytes();server=ThreadingHTTPServer(('127.0.0.1',8765),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
 inventory=json.loads(cmd(['xcrun','simctl','list','-j'],'simulators'));runtimes={r['identifier']:r for r in inventory['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
 for rid in sorted(runtimes,key=lambda r:tuple(map(int,re.findall(r'\d+',runtimes[r]['version']))),reverse=True):
  devices=[d for d in inventory['devices'].get(rid,[]) if d.get('isAvailable') and d['name'].startswith('iPhone' if kind=='iphone' else 'iPad')]
  if devices:device=devices[0];report['device']={**device,'runtime':runtimes[rid]['version']};udid=device['udid'];break
 if not udid:raise RuntimeError('No simulator')
 report['stage']='prepare-public-files';save();prepare_files(config)
 report['stage']='appium-start';save();appium_log=(OUT/'appium.log').open('w');appium=subprocess.Popen(['appium','server','--address','127.0.0.1','--port','4723','--keep-alive-timeout','0','--log-timestamp','--log-level','debug'],stdout=appium_log,stderr=subprocess.STDOUT)
 for _ in range(180):
  try:req('GET','/status',timeout=2);break
  except Exception:time.sleep(1)
 else:raise RuntimeError('Appium server startup failed')
 cmd(['xcrun','simctl','boot',udid],'boot',check=False);cmd(['xcrun','simctl','bootstatus',udid,'-b'],'bootstatus',timeout=240);install_files()
 report['stage']='native-session';save();caps={'platformName':'iOS','appium:automationName':'XCUITest','appium:udid':udid,'appium:deviceName':device['name'],'appium:platformVersion':report['device']['runtime'],'appium:bundleId':'com.apple.mobilesafari','appium:noReset':True,'appium:newCommandTimeout':180,'appium:wdaLaunchTimeout':180000,'appium:waitForIdleTimeout':1,'appium:showXcodeLog':True}
 session=req('POST','/session',{'capabilities':{'alwaysMatch':caps,'firstMatch':[{}]}},timeout=780);sid=session['sessionId']
 report['stage']='open-safari';save();call('POST','/execute/sync',{'script':'mobile: deepLink','args':[{'url':'http://127.0.0.1:8765/','bundleId':'com.apple.mobilesafari'}]});wait(lambda:latest.get('version')==config['version'],60)
 scale=latest['viewport']['scale'];offset=[0,0];cal=[latest['screen']['width']*.55,latest['screen']['height']*.55];n=len(events);native([[cal[0]/scale,cal[1]/scale]]);wait(lambda:any(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events[n:]));e=next(e for e in events[n:] if e['type']=='pointerdown');offset=[cal[0]-e['x']*scale,cal[1]-e['y']*scale];report['calibration']={'input':cal,'received':e,'offset':offset};report['stage']='files-and-touch';save()
 for sample in config['samples']:
  picker=file_picker(sample);wait(lambda:latest.get('display')==sample['display']);report.setdefault('filePicker',[]).append({'name':sample['name'],**picker});b=state();check(sample['name']+'-open',{},b,b['count']==sample['entities'] and b['omissions']==sample['omissions']);shot(sample['name']+'-opened')
  control('line');control('left');b=state();rect=b['rect'];left=max(rect['x']+20,0);right=min(rect['x']+rect['width']-20,b['viewport']['width']-25);top=max(rect['y']+50,180)
  for order in [0,1]:
   b=state();native([[left+20,top+20],[left+45,top+45]],dx=100,dy=100,release_order=order);time.sleep(.5);a=state();expected=b['view']['ppu']*min(b['rect']['width']/100,b['rect']['height']/100);check(sample['name']+'-zoom-'+str(order),b,a,a['count']==b['count'] and abs(a['view']['ppu']-expected)<expected*1e-6);shot(sample['name']+'-zoom-'+str(order))
   b=state();native([[left+20,top+140],[left+45,top+165]],dx=100,dy=-100);time.sleep(.5);a=state();check(sample['name']+'-whole-'+str(order),b,a,a['count']==b['count'] and a['view']['x']==0 and a['view']['y']==0)
  b=state();native([[left+50,top+60],[left+75,top+85]]);time.sleep(.5);a=state();check(sample['name']+'-recenter',b,a,a['count']==b['count'] and a['view']['ppu']==b['view']['ppu'] and a['view']!=b['view'])
  b=state();native([[left+130,top+140],[left+155,top+165]],dx=-80,dy=-80);time.sleep(.5);a=state();check(sample['name']+'-half',b,a,a['count']==b['count'] and abs(a['view']['ppu']-b['view']['ppu']/2)<1e-8)
  control('line');b=state();tap(left+30,top+30);tap(right-25,top+65);wait(lambda:latest['count']!=b['count']);a=state();check(sample['name']+'-draw',b,a,a['count']==b['count']+1);control('undo');wait(lambda:latest['count']==b['count']);a=state();check(sample['name']+'-undo',b,a,a['count']==b['count']);shot(sample['name']+'-final')
 report['trustedTouchDowns']=sum(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events);report['fileChanges']=[e for e in events if e['type']=='file-change'];report['errors']=errors;report['passed']=len(report['cases'])==27 and all(c['passed'] for c in report['cases']) and len(report['fileChanges'])==3 and all(e['isTrusted'] for e in report['fileChanges']) and not errors
except Exception as e:report['passed']=False;report['error']=str(e)
finally:
 if sid:
  try:shot('final');call('DELETE','')
  except Exception as e:report['sessionCleanupError']=str(e)
 if appium:appium.terminate()
 if udid:
  try:cmd(['xcrun','simctl','shutdown',udid],'shutdown',timeout=30,check=False)
  except Exception as e:report['cleanupError']=str(e)
 save()
print(json.dumps({'passed':report.get('passed'),'cases':len(report['cases']),'error':report.get('error')}));raise SystemExit(0 if report.get('passed') else 2)
