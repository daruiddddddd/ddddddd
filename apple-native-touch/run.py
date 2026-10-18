"""Native XCTest multi-finger input against hash-pinned public CAD in Simulator Safari."""
import base64,hashlib,io,json,os,re,subprocess,tarfile,threading,time,urllib.request
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'output';OUT.mkdir(exist_ok=True);kind=os.environ['PROBE_DEVICE'];udid=None;sid=None;appium=None;scale=1;serial=0;latest={};events=[];errors=[]
report={'physicalDevice':False,'deviceKind':kind,'scope':'XCTest native multi-finger touch, Safari on Apple Simulator; public 0.24.1 application code with SHA verified, served on cloud loopback with passive logging and synthetic fixture load; not direct public URL or file picker','cases':[]}
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
def req(method,path='',body=None,timeout=240):
 target='http://127.0.0.1:4723'+path;request=urllib.request.Request(target,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=timeout) as response:d=json.load(response)
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode()[:5000])
 value=d.get('value',d)
 if isinstance(value,dict) and value.get('error'):raise RuntimeError(str(value))
 return value

def call(method,path,body=None):return req(method,'/session/'+sid+path,body)
def native(points,dx=0,dy=0,release_order=0):
 sources=[]
 for i,(x,y) in enumerate(points):
  sx,sy=round(x*scale+offset[0]),round(y*scale+offset[1]);actions=[{'type':'pointerMove','duration':0,'x':sx,'y':sy,'origin':'viewport'},{'type':'pointerDown','button':0},{'type':'pause','duration':150}]
  if dx or dy:actions.append({'type':'pointerMove','duration':500,'x':round(sx+dx*scale),'y':round(sy+dy*scale),'origin':'viewport'})
  else:actions.append({'type':'pause','duration':80})
  if len(points)==2:
   actions += [{'type':'pointerUp','button':0} if i==release_order else {'type':'pause','duration':0},{'type':'pause','duration':250},{'type':'pointerUp','button':0} if i!=release_order else {'type':'pause','duration':0}]
  else:actions.append({'type':'pointerUp','button':0})
  sources.append({'type':'pointer','id':'finger'+str(i),'parameters':{'pointerType':'touch'},'actions':actions})
 call('POST','/actions',{'actions':sources});time.sleep(.45)
def tap(x,y):native([[x,y]])
def control(name):r=latest['controls'][name];tap(r['x']+r['width']/2,r['y']+r['height']/2)
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
  data=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  if data['type']=='state':latest=data
  elif data['type']=='error':errors.append(data)
  else:events.append(data)
  with (OUT/'events.jsonl').open('a') as f:f.write(json.dumps(data)+'\n')
  self.send_response(200);self.end_headers()
try:
 report['host']=cmd(['sw_vers'],'host')+cmd(['xcodebuild','-version'],'xcode')
 raw=urllib.request.urlopen(urllib.request.Request('https://jw1036-rebuild-lab.ryu08ma.chatgpt.site/?v=0241',headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read().decode().replace('\r\n','\n').encode();prefix=raw[:238408]
 if hashlib.sha256(prefix).hexdigest()!='374a206c0a07136e080fd036c1b67fac59b11132e02d721ceb7558a34cdcb7d7':raise RuntimeError('Public CAD hash mismatch')
 report['publicCodeSha256']=hashlib.sha256(prefix).hexdigest()
 fixture=json.loads((ROOT.parent/'apple-touch-probe/fixture.json').read_text())['base64']
 script=r'''<script>(()=>{
const post=o=>fetch('/events',{method:'POST',body:JSON.stringify(o)}).catch(()=>{});for(const type of ['pointerdown','pointermove','pointerup','pointercancel'])document.addEventListener(type,e=>post({type,pointerType:e.pointerType,isTrusted:e.isTrusted,x:e.clientX,y:e.clientY,id:e.pointerId,target:e.target.id,t:performance.now()}),{capture:true,passive:true});addEventListener('error',e=>post({type:'error',message:e.message}));addEventListener('unhandledrejection',e=>post({type:'error',message:String(e.reason)}));jwTest.openBytes(Uint8Array.from(atob('FIXTURE'),c=>c.charCodeAt(0)),'touch-input-fixture.jww');setInterval(()=>{const controls={};for(const [name,sel] of Object.entries({left:'#finger-left',right:'#finger-right',line:'[data-command="2"]'}))controls[name]=document.querySelector(sel).getBoundingClientRect().toJSON();post({type:'state',version:jwTest.version,count:jwTest.drawing?.doc.entities.length,view:jwTest.view,command:jwTest.command,lines:jwTest.drawing?.lines.map(e=>e.coordinates),rect:document.getElementById('canvas').getBoundingClientRect().toJSON(),controls,viewport:{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale},screen:{width:screen.width,height:screen.height},t:performance.now()});},200);})();</script>'''.replace('FIXTURE',fixture)
 html=prefix+script.encode();server=ThreadingHTTPServer(('127.0.0.1',8765),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
 inventory=json.loads(cmd(['xcrun','simctl','list','-j'],'simulators'));runtimes={r['identifier']:r for r in inventory['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
 for rid in sorted(runtimes,key=lambda r:tuple(map(int,re.findall(r'\d+',runtimes[r]['version']))),reverse=True):
  devices=[d for d in inventory['devices'].get(rid,[]) if d.get('isAvailable') and d['name'].startswith('iPhone' if kind=='iphone' else 'iPad')]
  if devices:device=devices[0];report['device']={**device,'runtime':runtimes[rid]['version']};udid=device['udid'];break
 if not udid:raise RuntimeError('No installed simulator')
 save();report['stage']='appium-start';save()
 cmd(['appium','--version'],'appium-version',timeout=60)
 cmd(['appium','driver','list','--installed'],'appium-drivers',timeout=60)
 appium_log=(OUT/'appium.log').open('w');appium=subprocess.Popen(['appium','server','--address','127.0.0.1','--port','4723','--log-timestamp','--log-level','debug'],stdout=appium_log,stderr=subprocess.STDOUT)
 ready=False
 for _ in range(180):
  if appium.poll() is not None:raise RuntimeError('Appium server exited '+str(appium.returncode))
  try:req('GET','/status',timeout=2);ready=True;break
  except Exception:time.sleep(1)
 if not ready:
  cmd(['ps','-axo','pid,ppid,etime,%cpu,command'],'server-processes',check=False)
  raise RuntimeError('Appium server startup failed before simulator; see appium.log and server-processes.log')
 cmd(['xcrun','simctl','boot',udid],'boot',check=False);cmd(['xcrun','simctl','bootstatus',udid,'-b'],'bootstatus',timeout=240)
 report['stage']='native-session';save()
 caps={'platformName':'iOS','appium:automationName':'XCUITest','appium:udid':udid,'appium:deviceName':device['name'],'appium:platformVersion':report['device']['runtime'],'appium:bundleId':'com.apple.mobilesafari','appium:noReset':True,'appium:newCommandTimeout':180,'appium:wdaLaunchTimeout':180000,'appium:waitForIdleTimeout':1,'appium:showXcodeLog':True}
 session=req('POST','/session',{'capabilities':{'alwaysMatch':caps,'firstMatch':[{}]}},timeout=780);sid=session['sessionId'];report['capabilities']=session.get('capabilities');report['stage']='open-safari';save()
 call('POST','/execute/sync',{'script':'mobile: deepLink','args':[{'url':'http://127.0.0.1:8765/','bundleId':'com.apple.mobilesafari'}]});wait(lambda:latest.get('version')=='0.24.1-touch',60)
 scale=latest['viewport']['scale'];report['stage']='touch-cases';save()
 offset=[0,0];cal=[latest['screen']['width']*.55,latest['screen']['height']*.55];n=len(events);native([[cal[0]/scale,cal[1]/scale]]);wait(lambda:any(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events[n:]));e=next(e for e in events[n:] if e['type']=='pointerdown');offset=[cal[0]-e['x']*scale,cal[1]-e['y']*scale];report['calibration']={'input':cal,'received':e,'offset':offset};
 control('line');control('left');b=state();rect=b['rect'];left=max(rect['x']+20,0);right=min(rect['x']+rect['width']-20,b['viewport']['width']-25);top=max(rect['y']+50,180);p=[left+20,top+30];q=[right-20,top+30]
 tap(*p);tap(*q);wait(lambda:latest['count']!=b['count']);a=state();check('one-finger-draw-line',b,a,a['count']==b['count']+1);shot('draw-line')
 line=a['lines'][-1];control('line');control('right');b=state();tap(p[0]+2,p[1]+2);tap(q[0]+2,q[1]+2);wait(lambda:latest['count']!=b['count']);a=state();check('one-finger-right-endpoint-snap',b,a,a['count']==b['count']+1 and all(abs(x-y)<1e-7 for x,y in zip(line,a['lines'][-1])));shot('right-snap')
 control('line');control('left')
 for order in [0,1]:
  b=state();native([[left+20,top+20],[left+45,top+45]],dx=100,dy=100,release_order=order);time.sleep(.5);a=state();expected=b['view']['ppu']*min(b['rect']['width']/100,b['rect']['height']/100);check('two-finger-range-zoom-release-'+str(order),b,a,a['count']==b['count'] and abs(a['view']['ppu']-expected)<1e-7*expected);shot('zoom-'+str(order))
 b=state();native([[left+25,top+25],[left+50,top+50]]);time.sleep(.5);a=state();check('two-finger-stationary-recenter',b,a,a['count']==b['count'] and a['view']['ppu']==b['view']['ppu'] and a['view']!=b['view'])
 control('line');control('left');b=state();native([[left+30,top+120]],dx=0,dy=-75);time.sleep(.5);a=state();check('one-finger-clock-AM0-text',b,a,a['command']==5 and a['count']==b['count']);shot('clock-text')
 report['trustedTouchDowns']=sum(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events);report['errors']=errors;report['passed']=len(report['cases'])==6 and all(c['passed'] for c in report['cases']) and report['trustedTouchDowns']>=7 and not errors
except Exception as e:report['passed']=False;report['error']=str(e)
finally:
 if sid:
  try:shot('final');call('DELETE','')
  except Exception as e:report['sessionCleanupError']=str(e)
  sid=None
 if appium:appium.terminate()
 if udid:
  try:shot('final')
  except Exception as e:report['finalScreenshotError']=str(e)
  try:cmd(['xcrun','simctl','shutdown',udid],'shutdown',timeout=30,check=False)
  except Exception as e:report['cleanupError']=str(e)
 save()
print(json.dumps({'passed':report.get('passed'),'cases':len(report['cases']),'error':report.get('error')}));raise SystemExit(0 if report.get('passed') else 2)
