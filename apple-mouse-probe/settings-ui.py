"""Change the observed Simulator Settings switch via AXe, then test both paths.

AXe touch events are used ONLY to configure Settings, never as mouse evidence.
No host desktop input, device app installation, or remote CAD service is used.
"""
import hashlib,json,os,subprocess,sys,tarfile,time,urllib.request
from pathlib import Path
kind,udid=sys.argv[1:];out=Path('output');serial=0
report={'physicalDeviceVerified':False,'publicHTMLFixed':False,'settingsUIChanged':False}
download='https://github.com/cameroncooke/AXe/releases/download/v1.8.0/AXe-macOS-v1.8.0-universal.tar.gz'
expected='7b76340b72e90d0f211bc7c4636f15009076eff07acef2f2b632b175debd8834'
def command(args,label,timeout=40,env=None,check=True):
 global serial
 serial+=1
 p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout,env=env)
 (out/f'ui-{serial:03d}-{label}.json').write_text(json.dumps({'args':args,'stdout':p.stdout,'stderr':p.stderr,'exit':p.returncode},indent=2))
 if check and p.returncode:raise RuntimeError(f'{label} exited {p.returncode}')
 return p
def sim(args,label,**kwargs):return command(['xcrun','simctl',*args],label,**kwargs)
def ax(args,label):return command([str(axe),*args,'--udid',udid],label,timeout=50)
def tree():
 raw=ax(['describe-ui'],'tree').stdout
 # AXe describes the actual UI as a JSON object or array.
 try:return json.loads(raw)
 except ValueError:raise RuntimeError('AXe returned no valid UI tree')
def nodes(t):
 if isinstance(t,list):
  for x in t:yield from nodes(x)
 elif isinstance(t,dict):
  yield t
  for x in t.get('children',[]):yield from nodes(x)
def label(n):return n.get('AXLabel',n.get('label',''))
def find(t,text):
 return [n for n in nodes(t) if label(n)==text]
def tap(n):
 f=n.get('frame')
 if not f or f.get('width',0)<=0 or f.get('height',0)<=0:raise RuntimeError('Observed element has no usable frame')
 ax(['tap','-x',str(f['x']+f['width']/2),'-y',str(f['y']+f['height']/2)],'tap-observed');time.sleep(1)
def value(n):
 v=n.get('AXValue',n.get('value'))
 if str(v).lower() in ('1','on','true'):return True
 if str(v).lower() in ('0','off','false'):return False
 raise RuntimeError('Unknown switch value: '+repr(v))
def locate_switch():
 sim(['launch',udid,'com.apple.Preferences'],'settings-launch')
 # This URL is optional; some runtimes reject it. The observed UI is authoritative.
 sim(['openurl',udid,'prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/AIR_TOUCH_TITLE'],'settings-open',check=False)
 time.sleep(3)
 for attempt in range(12):
  t=tree();matches=find(t,'Perform Touch Gestures')
  # Prefer the actual switch if a static text shares the label.
  switches=[n for n in matches if 'switch' in str(n.get('type','')).lower() or 'switch' in str(n.get('role','')).lower()]
  if len(switches)==1:return switches[0]
  if len(matches)==1 and ('value' in matches[0] or 'AXValue' in matches[0]):return matches[0]
  for target in ('AssistiveTouch','Touch','Accessibility'):
   candidates=[n for n in find(t,target) if n.get('frame') and 'statictext' not in str(n.get('type','')).lower() and 'back' not in str(n.get('role_description',n.get('roleDescription',''))).lower() and n.get('AXIdentifier',n.get('identifier'))!='BackButton']
   if len(candidates)==1 and 'switch' not in str(candidates[0].get('type','')).lower():tap(candidates[0]);break
  else:
   roots=t if isinstance(t,list) else [t]
   f=next((n.get('frame') for n in roots if n.get('frame') and n['frame'].get('height',0)>300),None)
   if not f:raise RuntimeError('No observed screen bounds for scrolling')
   x=f['x']+f['width']*.6
   ax(['swipe','--start-x',str(x),'--start-y',str(f['y']+f['height']*.8),'--end-x',str(x),'--end-y',str(f['y']+f['height']*.3),'--duration','0.5'],'scroll-observed')
   time.sleep(1)
 raise RuntimeError('Perform Touch Gestures switch not found in actual Settings UI')
original=None;axe=None;old_at=None
try:
 request=urllib.request.Request(download,headers={'User-Agent':'jw-input-probe'})
 data=urllib.request.urlopen(request,timeout=45).read()
 if hashlib.sha256(data).hexdigest()!=expected:raise RuntimeError('AXe release hash mismatch')
 archive=out/'axe.tar.gz';archive.write_bytes(data);folder=out/'axe-tool';folder.mkdir(exist_ok=True)
 with tarfile.open(archive) as tar:tar.extractall(folder,filter='data')
 candidates=[p for p in folder.rglob('axe') if p.is_file() and not p.is_symlink()]
 if len(candidates)!=1:raise RuntimeError('Ambiguous AXe executable')
 axe=candidates[0].resolve();report['axeSHA256']=expected
 developer=subprocess.check_output(['xcode-select','-p'],text=True).strip()
 # AXe v1.8.0 scripts/e2e-environment.sh requires Device Hub on Xcode 27.
 hub=Path(developer).parent/'Applications/DeviceHub.app'
 if not hub.is_dir():raise RuntimeError('Selected Xcode Device Hub is unavailable')
 command(['open','-g',str(hub)],'device-hub-start')
 time.sleep(5)
 report['deviceHubStarted']=True
 setup=sim(['spawn',udid,str((out/'accessibility-setup').resolve()),'1'],'at-on').stdout
 import re
 m=re.search(r'AssistiveTouch before=(\d)',setup)
 if not m:raise RuntimeError('Original AssistiveTouch value unavailable')
 old_at=m.group(1);time.sleep(15)
 command(['output/injector',developer,udid],'create-mouse',timeout=60,env=dict(os.environ,PROBE_CREATE_ONLY='1',PROBE_KEEP_SERVICES='1'))
 n=locate_switch();original=value(n);report['originalTouchGestures']=original
 if original:tap(n)
 after=value(locate_switch());report['touchGesturesAfter']=after
 if after:raise RuntimeError('UI switch did not turn off')
 report['settingsUIChanged']=original
 sim(['io',udid,'screenshot',str(out/'settings-finger-off.png')],'settings-screenshot',check=False)
 env=dict(os.environ,PROBE_NO_FINGER='0',PROBE_RAW_MOUSE='1')
 report['nativeExit']=command([sys.executable,'continuous-control.py',kind,udid],'native-raw',timeout=330,env=env,check=False).returncode
 env=dict(os.environ,PROBE_NO_FINGER='0',PROBE_RAW_MOUSE='0')
 report['safariExit']=command([sys.executable,'product-run.py',kind,udid],'safari-product',timeout=200,env=env,check=False).returncode
finally:
 if original is not None:
  try:
   sim(['spawn',udid,str((out/'accessibility-setup').resolve()),'1'],'restore-at-on')
   n=locate_switch()
   if value(n)!=original:tap(n)
   report['touchGesturesRestored']=value(locate_switch())==original
  except Exception as e:report['restoreError']=str(e)
 if old_at is not None:
  restored=sim(['spawn',udid,str((out/'accessibility-setup').resolve()),old_at],'restore-at',check=False)
  report['assistiveTouchRestored']=restored.returncode==0
 (out/'settings-ui-result.json').write_text(json.dumps(report,indent=2))
