"""Separate elapsed-time/input-service effects from app relaunch effects."""
import json, os, shutil, subprocess, sys, time, plistlib
from pathlib import Path

kind, udid=sys.argv[1:]
out=Path('output')
developer=subprocess.check_output(['xcode-select','-p'],text=True).strip()
report={'physicalDeviceVerified':False,'publicHTMLFixed':False,'segments':[]}
raw_mouse=os.environ.get('PROBE_RAW_MOUSE')=='1'
no_finger=os.environ.get('PROBE_NO_FINGER')=='1'
report['coordinateMode']='GCMouse-relative' if raw_mouse else 'UIKit'

def command(args,log,timeout=35,env=None):
    with (out/log).open('a') as f:
        return subprocess.run([sys.executable,'bounded.py',str(timeout),*args],stdout=f,stderr=f,env=env).returncode

def sim(args,log,timeout=35):
    return command(['xcrun','simctl',*args],log,timeout)

def ready(channel):
    p=out/(channel+'-events.jsonl')
    for _ in range(30):
        if p.exists() and 'page-ready' in p.read_text(): return True
        time.sleep(1)
    return False

def rows(path):
    return path.read_text().splitlines() if path.exists() else []

def app_container():
    try:
        return Path(subprocess.check_output(['xcrun','simctl','get_app_container',udid,'org.jwprobe.nativeinput','data'],text=True,timeout=20).strip())
    except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
        # Read the selected disposable simulator's container metadata only.
        # run44 timed out after input, losing API logs despite successful cleanup.
        root=Path.home()/'Library/Developer/CoreSimulator/Devices'/udid/'data/Containers/Data/Application'
        matches=[]
        for metadata in root.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
            try:
                if plistlib.loads(metadata.read_bytes()).get('MCMMetadataIdentifier')=='org.jwprobe.nativeinput':matches.append(metadata.parent)
            except (ValueError,OSError,plistlib.InvalidFileException):pass
        if len(matches)!=1:raise RuntimeError('Cannot identify a unique probe container for log recovery')
        print('Recovered exact probe container from simulator metadata',flush=True)
        return matches[0]

try:
    if kind=='iphone':
        # The simulator's mouse service received no input at all with AT off in
        # run43. Keep raw coordinates and compare AT on; never infer missing edges.
        setup=sim(['spawn',udid,str(Path('output/accessibility-setup').resolve()),'1']+(['no-finger'] if no_finger else []),kind+'-accessibility-setup.log')
        if setup:raise RuntimeError('Accessibility setup failed; do not interpret mouse results')
        time.sleep(20)
    if sim(['install',udid,'output/NativeProbe.app'],kind+'-native-install.log',60):
        raise RuntimeError('Native diagnostic install failed')
    container=app_container()
    channel=kind+'-clean-first'
    dom_offset=api_offset=0
    for index,phase in enumerate(['continuous-first','continuous-same-process','continuous-relaunch']):
        label=kind+'-'+phase
        if index!=1:
            if index==2: channel=kind+'-clean-relaunch'
            launch=sim(['launch',udid,'org.jwprobe.nativeinput','--probe-phase',channel[len(kind)+1:],'--direct-buttons']+(['--raw-mouse'] if raw_mouse else []),label+'-launch.log')
            if launch or not ready(channel): raise RuntimeError('Native page did not load: '+phase)
            dom_offset=api_offset=0
        started=time.time()
        env=dict(os.environ,PROBE_DEVICE=channel)
        if index<2: env['PROBE_KEEP_SERVICES']='1'
        if index>0: env['PROBE_REUSE_SERVICES']='1'
        code=command(['output/injector',developer,udid],label+'-injector.log',90,env)
        time.sleep(2)
        api_file=container/'Documents/native-events.jsonl'
        api=rows(api_file);dom=rows(out/(channel+'-events.jsonl'))
        shutil.copyfile(api_file,out/(label+'-api-cumulative.jsonl'))
        shutil.copyfile(out/(channel+'-events.jsonl'),out/(label+'-events-cumulative.jsonl'))
        # Derived slices keep the original cumulative raw files alongside them.
        # A repeated page header is metadata for viewport-based assessment only.
        page=next((line for line in dom if json.loads(line).get('type')=='page-ready'),None)
        dom_slice=dom[dom_offset:]
        if page and not any(json.loads(line).get('type')=='page-ready' for line in dom_slice):dom_slice.insert(0,page)
        (out/(label+'-api.jsonl')).write_text('\n'.join(api[api_offset:])+'\n')
        (out/(label+'-events.jsonl')).write_text('\n'.join(dom_slice)+'\n')
        report['segments'].append({'phase':phase,'channel':channel,'startedWall':started,'finishedWall':time.time(),'injectorExit':code,'sameApplicationProcess':index==1,'apiLines':[api_offset,len(api)],'domLines':[dom_offset,len(dom)]})
        api_offset=len(api);dom_offset=len(dom)
        print(json.dumps(report['segments'][-1]),flush=True)
        if index in (1,2):sim(['terminate',udid,'org.jwprobe.nativeinput'],label+'-launch.log')
finally:
    sim(['terminate',udid,'org.jwprobe.nativeinput'],kind+'-final-terminate.log')
    if kind=='iphone':sim(['spawn',udid,str(Path('output/accessibility-setup').resolve()),'0']+(['restore-finger'] if no_finger else []),kind+'-accessibility-restore.log',20)
    (out/(kind+'-continuous-control.json')).write_text(json.dumps(report,indent=2))
if len(report['segments'])!=3:raise SystemExit(2)
