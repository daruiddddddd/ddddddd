"""Native AXe one-finger input against hash-pinned public CAD in Simulator Safari."""
import base64,hashlib,io,json,os,re,subprocess,tarfile,threading,time,urllib.request
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'output';OUT.mkdir(exist_ok=True);kind=os.environ['PROBE_DEVICE'];udid=None;serial=0;latest={};events=[];errors=[]
report={'physicalDevice':False,'deviceKind':kind,'scope':'AXe native one-finger HID, Safari on Apple Simulator; public 0.24.0 application code with SHA verified, served on cloud loopback with passive logging and synthetic fixture load; not direct public URL or file picker','cases':[]}
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
def ax(args):cmd([str(axe),*args,'--udid',udid],'axe',timeout=45)
def tap(x,y):ax(['tap','-x',str(x+offset[0]),'-y',str(y+offset[1])]);time.sleep(.4)
def control(name):r=latest['controls'][name];tap(r['x']+r['width']/2,r['y']+r['height']/2)
def shot(name):cmd(['xcrun','simctl','io',udid,'screenshot',str(OUT/(name+'.png'))],name,check=False)
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
 raw=urllib.request.urlopen(urllib.request.Request('https://jw1036-rebuild-lab.ryu08ma.chatgpt.site/?v=0240',headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read().decode().replace('\r\n','\n').encode();prefix=raw[:238226]
 if hashlib.sha256(prefix).hexdigest()!='1ee65677f9ea11d0efff2758299a0dd0421a2f5e5f4e4d4e0fe918eddf969c63':raise RuntimeError('Public CAD hash mismatch')
 report['publicCodeSha256']=hashlib.sha256(prefix).hexdigest()
 fixture=json.loads((ROOT.parent/'apple-touch-probe/fixture.json').read_text())['base64']
 script=r'''<script>(()=>{
const post=o=>fetch('/events',{method:'POST',body:JSON.stringify(o)}).catch(()=>{});for(const type of ['pointerdown','pointermove','pointerup','pointercancel'])document.addEventListener(type,e=>post({type,pointerType:e.pointerType,isTrusted:e.isTrusted,x:e.clientX,y:e.clientY,id:e.pointerId,target:e.target.id,t:performance.now()}),{capture:true,passive:true});addEventListener('error',e=>post({type:'error',message:e.message}));addEventListener('unhandledrejection',e=>post({type:'error',message:String(e.reason)}));jwTest.openBytes(Uint8Array.from(atob('FIXTURE'),c=>c.charCodeAt(0)),'touch-input-fixture.jww');setInterval(()=>{const controls={};for(const [name,sel] of Object.entries({left:'#finger-left',right:'#finger-right',line:'[data-command="2"]'}))controls[name]=document.querySelector(sel).getBoundingClientRect().toJSON();post({type:'state',version:jwTest.version,count:jwTest.drawing?.doc.entities.length,view:jwTest.view,command:jwTest.command,lines:jwTest.drawing?.lines.map(e=>e.coordinates),rect:document.getElementById('canvas').getBoundingClientRect().toJSON(),controls,viewport:{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale},screen:{width:screen.width,height:screen.height},t:performance.now()});},200);})();</script>'''.replace('FIXTURE',fixture)
 html=prefix+script.encode();server=ThreadingHTTPServer(('127.0.0.1',8765),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
 archive=urllib.request.urlopen('https://github.com/cameroncooke/AXe/releases/download/v1.8.0/AXe-macOS-v1.8.0-universal.tar.gz').read()
 if hashlib.sha256(archive).hexdigest()!='7b76340b72e90d0f211bc7c4636f15009076eff07acef2f2b632b175debd8834':raise RuntimeError('AXe hash mismatch')
 tools=OUT/'axe-tools';tools.mkdir();tarfile.open(fileobj=io.BytesIO(archive)).extractall(tools,filter='data');axe=next(p for p in tools.rglob('axe') if p.is_file());axe.chmod(0o755)
 inventory=json.loads(cmd(['xcrun','simctl','list','-j'],'simulators'));runtimes={r['identifier']:r for r in inventory['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
 for rid in sorted(runtimes,key=lambda r:tuple(map(int,re.findall(r'\d+',runtimes[r]['version']))),reverse=True):
  devices=[d for d in inventory['devices'].get(rid,[]) if d.get('isAvailable') and d['name'].startswith('iPhone' if kind=='iphone' else 'iPad')]
  if devices:device=devices[-1];report['device']={**device,'runtime':runtimes[rid]['version']};udid=device['udid'];break
 if not udid:raise RuntimeError('No installed simulator')
 save();dev=cmd(['xcode-select','-p'],'developer').strip();hub=Path(dev).parent/'Applications/DeviceHub.app'
 if not hub.exists():raise RuntimeError('Xcode DeviceHub not found: '+str(hub))
 cmd(['open','-g',str(hub)],'hub');report['deviceHubStarted']=str(hub)
 time.sleep(5)
 cmd(['xcrun','simctl','boot',udid],'boot',check=False);cmd(['xcrun','simctl','bootstatus',udid,'-b'],'bootstatus',timeout=240)
 cmd(['xcrun','simctl','launch',udid,'com.apple.mobilesafari'],'safari-launch',timeout=120,check=False);cmd(['xcrun','simctl','openurl',udid,'http://127.0.0.1:8765/'],'safari-open',timeout=90);wait(lambda:latest.get('version')=='0.24.0-display',45)
 offset=[0,0];cal=[latest['screen']['width']*.55,latest['screen']['height']*.55];n=len(events);tap(*cal);wait(lambda:any(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events[n:]));e=next(e for e in events[n:] if e['type']=='pointerdown');offset=[cal[0]-e['x'],cal[1]-e['y']];report['calibration']={'input':cal,'received':e,'offset':offset};
 control('line');control('left');b=state();rect=b['rect'];left=max(rect['x']+20,0);right=min(rect['x']+rect['width']-20,b['viewport']['width']-25);top=max(rect['y']+50,180);p=[left+20,top+30];q=[right-20,top+100]
 tap(*p);tap(*q);wait(lambda:latest['count']!=b['count']);a=state();check('one-finger-draw-line',b,a,a['count']==b['count']+1);shot('draw-line')
 line=a['lines'][-1];control('line');control('right');b=state();tap(p[0]+2,p[1]+2);tap(q[0]+2,q[1]+2);wait(lambda:latest['count']!=b['count']);a=state();check('one-finger-right-endpoint-snap',b,a,a['count']==b['count']+1 and all(abs(x-y)<1e-7 for x,y in zip(line,a['lines'][-1])));shot('right-snap')
 control('line');control('left');b=state();x=left+30;y=top+140;ax(['swipe','--start-x',str(x+offset[0]),'--start-y',str(y+offset[1]),'--end-x',str(x+offset[0]),'--end-y',str(y-80+offset[1]),'--duration','0.8']);time.sleep(.7);a=state();check('one-finger-clock-AM0-text',b,a,a['command']==5 and a['count']==b['count']);shot('clock-text')
 report['trustedTouchDowns']=sum(e['type']=='pointerdown' and e.get('pointerType')=='touch' and e.get('isTrusted') for e in events);report['errors']=errors;report['passed']=len(report['cases'])==3 and all(c['passed'] for c in report['cases']) and report['trustedTouchDowns']>=7 and not errors
except Exception as e:report['passed']=False;report['error']=str(e)
finally:
 if udid:
  try:shot('final')
  except Exception as e:report['finalScreenshotError']=str(e)
  try:cmd(['xcrun','simctl','shutdown',udid],'shutdown',timeout=30,check=False)
  except Exception as e:report['cleanupError']=str(e)
 save()
print(json.dumps({'passed':report.get('passed'),'cases':len(report['cases']),'error':report.get('error')}));raise SystemExit(0 if report.get('passed') else 2)

