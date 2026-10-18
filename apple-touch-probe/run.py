"""Native XCTest finger actions into public Safari; JS only observes and loads the isolated seven-line fixture."""
import base64,hashlib,json,os,re,subprocess,time,traceback,urllib.request,urllib.error
from pathlib import Path
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'output';OUT.mkdir(exist_ok=True)
kind=os.environ['PROBE_DEVICE'];url='https://jw1036-rebuild-lab.ryu08ma.chatgpt.site/?v=0241'
report={'deviceKind':kind,'publicURL':url,'physicalDevice':False,'scope':'Apple Simulator Safari, public URL, native XCTest touch actions; fixture loading via JS only; not file-picker verification','cases':[]};sid=None;appium=None;udid=None;webctx=None;offset=[0,0];scale=1

def save(): (OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
def command(args,label,timeout=180,check=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=timeout);(OUT/(label+'.log')).write_text(p.stdout+'\n'+p.stderr)
 if check and p.returncode:raise RuntimeError(label+' exit '+str(p.returncode))
 return p.stdout

def req(method,path='',body=None,timeout=240):
 target='http://127.0.0.1:4723'+path;request=urllib.request.Request(target,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(request,timeout=timeout) as response:d=json.load(response)
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode()[:5000])
 value=d.get('value',d)
 if isinstance(value,dict) and value.get('error'):raise RuntimeError(str(value))
 return value

def call(method,path,body=None):return req(method,'/session/'+sid+path,body)
def context(name):call('POST','/context',{'name':name})
def js(code,args=[]):
 context(webctx)
 encoded=call('POST','/execute/sync',{'script':'return JSON.stringify((function(){'+code+'}).apply(null,arguments));','args':args})
 return json.loads(encoded) if encoded is not None else None
def state():return js("return {version:jwTest.version,count:jwTest.drawing?.doc.entities.length,view:jwTest.view,command:jwTest.command,lines:jwTest.drawing?.lines.map(e=>e.coordinates),message:document.getElementById('message').textContent,clock:document.getElementById('clock').innerText,rect:document.getElementById('canvas').getBoundingClientRect().toJSON(),viewport:{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale},events:window.touchEvidence||[]};")
def screenshot(name):
 context('NATIVE_APP');(OUT/(name+'.png')).write_bytes(base64.b64decode(call('GET','/screenshot')))
def native(points,dx=0,dy=0,release_order=0):
 context('NATIVE_APP');sources=[]
 for i,(x,y) in enumerate(points):
  sx,sy=round(x*scale+offset[0]),round(y*scale+offset[1]);actions=[{'type':'pointerMove','duration':0,'x':sx,'y':sy,'origin':'viewport'},{'type':'pointerDown','button':0},{'type':'pause','duration':150}]
  if dx or dy:actions.append({'type':'pointerMove','duration':500,'x':round(sx+dx*scale),'y':round(sy+dy*scale),'origin':'viewport'})
  else:actions.append({'type':'pause','duration':80})
  if len(points)==2:
   actions += [{'type':'pointerUp','button':0} if i==release_order else {'type':'pause','duration':0},{'type':'pause','duration':250},{'type':'pointerUp','button':0} if i!=release_order else {'type':'pause','duration':0}]
  else:actions.append({'type':'pointerUp','button':0})
  sources.append({'type':'pointer','id':'finger'+str(i),'parameters':{'pointerType':'touch'},'actions':actions})
 call('POST','/actions',{'actions':sources});time.sleep(.45)
def tap_selector(selector):
 r=js('return document.querySelector(arguments[0]).getBoundingClientRect().toJSON()', [selector]);native([(r['x']+r['width']/2,r['y']+r['height']/2)])
def load():
 data=json.loads((ROOT/'fixture.json').read_text());js("jwTest.openBytes(Uint8Array.from(atob(arguments[0]),c=>c.charCodeAt(0)),'touch-input-fixture.jww');return true;",[data['base64']]);time.sleep(.2);tap_selector('[data-command="2"]');tap_selector('#finger-left');js('window.touchEvidence=[];return true;')
def result(name,before,after,passed,extra=None):
 events=after['events'];trusted=sum(e['type']=='pointerdown' and e['pointerType']=='touch' and e['isTrusted'] for e in events)
 report['cases'].append({'name':name,'passed':bool(passed and trusted),'trustedTouchDowns':trusted,'before':before,'after':after,**(extra or {})});save();print(name,report['cases'][-1]['passed'],flush=True)

try:
 report['host']=command(['sw_vers'],'host')+command(['xcodebuild','-version'],'xcode')
 inventory=json.loads(command(['xcrun','simctl','list','-j'],'simulators'));runtimes={r['identifier']:r for r in inventory['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
 prefix='iPhone' if kind=='iphone' else 'iPad'
 for rid in sorted(runtimes,key=lambda r:tuple(map(int,re.findall(r'\d+',runtimes[r]['version']))),reverse=True):
  candidates=[d for d in inventory['devices'].get(rid,[]) if d.get('isAvailable') and d['name'].startswith(prefix)]
  if candidates:device=candidates[-1];runtime=runtimes[rid];break
 else:raise RuntimeError('No matching installed Simulator')
 udid=device['udid'];report['device']={**device,'runtime':runtime['version']};save()
 dev=command(['xcode-select','-p'],'developer').strip();hub=Path(dev).parent/'Applications/DeviceHub.app'
 if hub.exists():command(['open','-a',str(hub)],'device-hub',check=False)
 command(['appium','--version'],'appium-version',timeout=60)
 command(['appium','driver','list','--installed'],'appium-drivers',timeout=60)
 appium_log=(OUT/'appium.log').open('w');appium=subprocess.Popen(['appium','server','--address','127.0.0.1','--port','4723','--log-timestamp','--log-level','debug'],stdout=appium_log,stderr=subprocess.STDOUT)
 ready=False
 for _ in range(180):
  if appium.poll() is not None:raise RuntimeError('Appium server exited '+str(appium.returncode))
  try:req('GET','/status',timeout=2);ready=True;break
  except Exception:time.sleep(1)
 if not ready:
  command(['ps','-axo','pid,ppid,etime,%cpu,command'],'server-processes',check=False)
  raise RuntimeError('Appium server startup failed before simulator; see appium.log and server-processes.log')
 command(['xcrun','simctl','boot',udid],'boot',check=False);command(['xcrun','simctl','bootstatus',udid,'-b'],'bootstatus',timeout=300)
 caps={'platformName':'iOS','browserName':'Safari','appium:automationName':'XCUITest','appium:udid':udid,'appium:deviceName':device['name'],'appium:platformVersion':runtime['version'],'appium:newCommandTimeout':180,'appium:wdaLaunchTimeout':180000,'appium:safariInitialUrl':url,'appium:showXcodeLog':True,'appium:webviewConnectTimeout':120000}
 session=req('POST','/session',{'capabilities':{'alwaysMatch':caps,'firstMatch':[{}]}},timeout=780);sid=session['sessionId'];report['capabilities']=session.get('capabilities');save()
 contexts=call('GET','/contexts');webctx=next(c for c in contexts if c.startswith('WEBVIEW'));context(webctx);call('POST','/url',{'url':url})
 for _ in range(40):
  try:
   if js('return window.jwTest?.version')=='0.24.1-touch':break
  except Exception:pass
  time.sleep(1)
 else:raise RuntimeError('Public application unavailable or version mismatch')
 js("window.touchEvidence=[];for(const type of ['pointerdown','pointermove','pointerup','pointercancel'])document.addEventListener(type,e=>touchEvidence.push({type,pointerType:e.pointerType,pointerId:e.pointerId,isTrusted:e.isTrusted,x:e.clientX,y:e.clientY,target:e.target.id,t:performance.now()}),{capture:true,passive:true});window.probeErrors=[];addEventListener('error',e=>probeErrors.push(e.message));return true;")
 # Establish native-to-DOM coordinates using an actual trusted touch, never a guessed success.
 viewport=js('return {width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale};');scale=viewport['scale'];context('NATIVE_APP');window=call('GET','/window/rect');cal=[window['width']*.55,window['height']*.55];native([(cal[0]/scale,cal[1]/scale)])
 events=js('return window.touchEvidence');downs=[e for e in events if e['type']=='pointerdown' and e['isTrusted'] and e['pointerType']=='touch']
 if not downs:raise RuntimeError('Calibration native touch did not reach Safari DOM')
 received=downs[-1];offset=[cal[0]-received['x']*scale,cal[1]-received['y']*scale];report['calibration']={'native':cal,'received':received,'offset':offset,'scale':scale};save()
 load();b=state();rect=b['rect'];vw=b['viewport'];left=max(rect['x']+20,0);right=min(rect['x']+rect['width']-20,vw['width']-25);top=max(rect['y']+50,180);bottom=min(rect['y']+rect['height']-40,vw['height']-60)
 if right-left<100 or bottom-top<160:raise RuntimeError('Insufficient visible canvas area')
 p=[left+20,top+30];q=[right-20,top+30];native([p]);native([q]);a=state();result('one-finger-two-taps-draw-line',b,a,a['count']==b['count']+1);screenshot('single-finger-line')
 # Right-mode one-finger taps must acquire the exact endpoints of the line just drawn.
 line=a['lines'][-1];tap_selector('[data-command="2"]');tap_selector('#finger-right');js('window.touchEvidence=[];return true;');b=state();native([[p[0]+2,p[1]+2]]);native([[q[0]+2,q[1]+2]]);a=state();new=a['lines'][-1];result('one-finger-right-mode-endpoint-snap',b,a,a['count']==b['count']+1 and all(abs(x-y)<1e-7 for x,y in zip(line,new)))
 for order in [0,1]:
  load();b=state();points=[[left+20,top+20],[left+45,top+45]];native(points,dx=min(100,right-left-70),dy=100,release_order=order);a=state();result('two-finger-range-zoom-release-'+str(order),b,a,a['view']['ppu']>b['view']['ppu'] and a['count']==b['count']);screenshot('two-finger-zoom-'+str(order))
 load();b=state();native([[left+25,top+25],[left+50,top+50]]);a=state();result('two-finger-stationary-recenter',b,a,a['view']!=b['view'] and a['count']==b['count'] and a['view']['ppu']==b['view']['ppu'])
 load();b=state();native([[left+30,top+120]],dx=0,dy=-75);a=state();result('one-finger-clock-drag',b,a,a['command']==5 and a['count']==b['count']);screenshot('clock-after')
 report['rangeReleaseOrdersMatch']=report['cases'][2]['after']['view']==report['cases'][3]['after']['view'];report['errors']=js('return window.probeErrors');report['passed']=report['rangeReleaseOrdersMatch'] and len(report['cases'])==6 and all(c['passed'] for c in report['cases']) and not report['errors']
except Exception as e:
 report['error']=str(e);report['traceback']=traceback.format_exc();report['passed']=False
 if sid:
  try:screenshot('failure')
  except Exception as q:report['screenshotError']=str(q)
finally:
 save()
 if sid:
  try:call('DELETE','')
  except Exception:pass
 if appium:appium.terminate()
 if udid:
  try:command(['xcrun','simctl','shutdown',udid],'shutdown',timeout=30,check=False)
  except Exception:pass
print(json.dumps({'passed':report.get('passed'),'cases':len(report['cases']),'error':report.get('error')}));raise SystemExit(0 if report.get('passed') else 2)

