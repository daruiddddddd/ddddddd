"""Exercise actual public CAD code in standalone Simulator Safari."""
import json,os,subprocess,sys,time
from pathlib import Path
kind,udid=sys.argv[1:];out=Path('output');channel=kind+'-html-cad'
def cmd(args,name,timeout=35,env=None):
 with (out/(kind+'-product-'+name+'.log')).open('a') as log:
  return subprocess.run([sys.executable,'bounded.py',str(timeout),*args],stdout=log,stderr=log,env=env).returncode
def sim(args,name,timeout=35):return cmd(['xcrun','simctl',*args],name,timeout)
def rows():
 p=out/(channel+'-events.jsonl')
 return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
report={'physicalDeviceVerified':False,'sourceJwParityVerified':False,'scope':'Published CAD input/visible zoom only, public sample fixture; see product-source.json for exact version/hash','device':kind}
try:
 if kind=='iphone':
  setup=sim(['spawn',udid,str(Path('output/accessibility-setup').resolve()),'1']+(['no-finger'] if os.environ.get('PROBE_NO_FINGER')=='1' else []),'accessibility')
  if setup:raise RuntimeError('Accessibility setup failed; mouse test invalid')
  time.sleep(20)
 sim(['terminate',udid,'com.apple.mobilesafari'],'terminate')
 if sim(['launch',udid,'com.apple.mobilesafari'],'launch'):
  raise RuntimeError('Safari launch failed; input not injected')
 sim(['openurl',udid,'http://127.0.0.1:8765/product?device='+channel],'open')
 for _ in range(45):
  if any(e.get('type')=='page-ready' and e.get('product') for e in rows()):break
  time.sleep(1)
 else:raise RuntimeError('Actual CAD page not ready; inspect receiver log')
 developer=subprocess.check_output(['xcode-select','-p'],text=True).strip()
 env=dict(os.environ,PROBE_DEVICE=channel,PROBE_CHORDS_ONLY='1',PROBE_RESET_SERVICES='1')
 report['injectorExit']=cmd(['output/injector',developer,udid],'injector',90,env)
 time.sleep(3)
 report['screenshotExit']=sim(['io',udid,'screenshot',str(out/(kind+'-product-final.png'))],'screenshot',20)
 data=rows();report['views']=[e for e in data if e.get('type')=='product-view'];report['errors']=[e for e in data if e.get('type')=='product-error']
 report['mouseEvents']=sum(e.get('pointerType')=='mouse' for e in data);report['touchEvents']=sum(e.get('pointerType')=='touch' for e in data)
 report['calibrationFailed']='unavailable; do not interpret' in (out/(kind+'-product-injector.log')).read_text()
 report['fourZoomChangesObserved']=len(report['views'])==5 and not report['errors'] and not report['calibrationFailed']
finally:
 if kind=='iphone':sim(['spawn',udid,str(Path('output/accessibility-setup').resolve()),'0']+(['restore-finger'] if os.environ.get('PROBE_NO_FINGER')=='1' else []),'restore',20)
 (out/(kind+'-product-result.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report));raise SystemExit(0 if report.get('fourZoomChangesObserved') else 2)

