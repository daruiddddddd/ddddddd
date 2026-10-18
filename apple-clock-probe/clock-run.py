"""Run actual HID clock gestures against the public CAD in iPad Simulator."""
import json,os,subprocess,sys,time
from pathlib import Path
kind,udid=sys.argv[1:];out=Path('output');channel=kind+'-html-cad'
def cmd(args,name,timeout=35,env=None):
    with (out/(kind+'-clock-'+name+'.log')).open('a') as log:
        return subprocess.run([sys.executable,'bounded.py',str(timeout),*args],stdout=log,stderr=log,env=env).returncode
def sim(args,name,timeout=35):return cmd(['xcrun','simctl',*args],name,timeout)
def rows():
    p=out/(channel+'-events.jsonl')
    return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
report={'physicalDeviceVerified':False,'allSourceJwParityVerified':False,'scope':'iPad Simulator actual HID input into hash-matched published CAD clock subset','device':kind}
try:
    if kind!='ipad':raise RuntimeError('This workflow is iPad only')
    sim(['terminate',udid,'com.apple.mobilesafari'],'terminate')
    if sim(['launch',udid,'com.apple.mobilesafari'],'launch'):raise RuntimeError('Safari launch failed')
    if sim(['openurl',udid,'http://127.0.0.1:8765/product?device='+channel],'open'):raise RuntimeError('Public-code page opening failed')
    for _ in range(45):
        if any(e.get('type')=='page-ready' and e.get('product') for e in rows()):break
        time.sleep(1)
    else:raise RuntimeError('Public CAD page not ready; no input trial')
    developer=subprocess.check_output(['xcode-select','-p'],text=True).strip()
    report['injectorExit']=cmd(['output/injector',developer,udid],'injector',360,dict(os.environ,PROBE_DEVICE=channel,PROBE_RESET_SERVICES='1'))
    time.sleep(2)
    report['screenshotExit']=sim(['io',udid,'screenshot',str(out/(kind+'-clock-final.png'))],'screenshot',20)
    log=(out/(kind+'-clock-injector.log')).read_text()
    report['cases']=[json.loads(line[len('CLOCK_RESULT '):]) for line in log.splitlines() if line.startswith('CLOCK_RESULT ')]
    data=rows();report['errors']=[e for e in data if e.get('type')=='product-error']
    report['mouseEvents']=sum(e.get('pointerType')=='mouse' and e.get('isTrusted') for e in data)
    report['touchEvents']=sum(e.get('pointerType')=='touch' for e in data)
    report['passed']=report['injectorExit']==0 and len(report['cases'])==9 and all(c.get('passed') for c in report['cases']) and not report['errors'] and report['mouseEvents']>0 and report['touchEvents']==0
except Exception as e:
    report['error']=str(e);report['passed']=False
finally:
    (out/(kind+'-clock-result.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report));raise SystemExit(0 if report.get('passed') else 2)

