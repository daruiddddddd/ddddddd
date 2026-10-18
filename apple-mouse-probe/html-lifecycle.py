"""Bounded isolated experiments: clean HID lifecycle and standalone Safari HTML.

No native bridge is installed in Safari. No inferred or synthetic DOM releases.
"""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
from assess import assess

kind, udid = sys.argv[1:]
out = Path('output')
developer = subprocess.check_output(['xcode-select', '-p'], text=True).strip()

def command(args, log, timeout=35, env=None):
    with (out / log).open('a') as stream:
        return subprocess.run([sys.executable, 'bounded.py', str(timeout), *args],
                              stdout=stream, stderr=stream, env=env).returncode

def sim(args, log, timeout=35):
    return command(['xcrun', 'simctl', *args], log, timeout)

def ready(channel):
    p = out / (channel + '-events.jsonl')
    for _ in range(30):
        if p.exists() and 'page-ready' in p.read_text():
            return True
        time.sleep(1)
    return False

def inject(channel):
    env = dict(os.environ, PROBE_DEVICE=channel, PROBE_RESET_SERVICES='1')
    return command(['output/injector', developer, udid], channel+'-injector.log', 90, env)

def read_events(channel):
    p = out / (channel + '-events.jsonl')
    return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []

report = {'physicalDeviceVerified': False, 'publicHTMLFixed': False, 'phases': {}}
if kind == 'iphone':
    sim(['spawn', udid, str(Path('output/accessibility-setup').resolve()), '1'], kind+'-accessibility-setup.log')
    time.sleep(20)

try:
    if sim(['install', udid, 'output/NativeProbe.app'], kind+'-native-install.log', 60):
        raise RuntimeError('Native diagnostic could not be installed')
    for phase in ['clean-first', 'clean-relaunch']:
        channel = kind+'-'+phase
        launch = sim(['launch', udid, 'org.jwprobe.nativeinput', '--probe-phase', phase, '--direct-buttons'], channel+'-launch.log')
        loaded = launch == 0 and ready(channel)
        entry = {'pageReady': loaded, 'scope': 'native diagnostic only'}
        if loaded:
            entry['injectorExit'] = inject(channel)
            time.sleep(2)
            container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, 'org.jwprobe.nativeinput', 'data'], text=True, timeout=20).strip()
            shutil.copyfile(Path(container)/'Documents/native-events.jsonl', out/(channel+'-api.jsonl'))
        sim(['terminate', udid, 'org.jwprobe.nativeinput'], channel+'-launch.log')
        report['phases'][phase] = entry
        print(channel, json.dumps(entry), flush=True)

    for policy in ['cad', 'compat', 'nocapture']:
        phase = 'html-'+policy
        channel = kind+'-'+phase
        # Relaunch Safari for every policy; clean HID service reset is identical.
        sim(['terminate', udid, 'com.apple.mobilesafari'], channel+'-open.log')
        sim(['launch', udid, 'com.apple.mobilesafari'], channel+'-open.log')
        sim(['openurl', udid, 'http://127.0.0.1:8765/?device='+channel+'&policy='+policy], channel+'-open.log')
        loaded = ready(channel)
        entry = {'pageReady': loaded, 'scope': 'standalone Safari HTML'}
        if loaded:
            entry['injectorExit'] = inject(channel)
            time.sleep(2)
        events = read_events(channel)
        entry['pointerAssessment'] = assess(events)
        # Preserve compatibility MouseEvents independently. A touch-generated
        # compatibility click is never promoted to a real mouse success.
        entry['compatibilityMouseEvents'] = [e for e in events if e.get('type') in ('mousedown','mouseup','mousemove')]
        entry['capabilities'] = [e for e in events if e.get('type') == 'page-ready']
        report['phases'][phase] = entry
        sim(['io', udid, 'screenshot', str(out/(channel+'.png'))], channel+'-screenshot.log', 20)
        print(channel, json.dumps(entry['pointerAssessment']), flush=True)
finally:
    if kind == 'iphone':
        sim(['spawn', udid, str(Path('output/accessibility-setup').resolve()), '0'], kind+'-accessibility-restore.log', 20)
    (out/(kind+'-html-lifecycle.json')).write_text(json.dumps(report, indent=2))

if not all(report['phases'].get('html-'+p,{}).get('pointerAssessment',{}).get('stationaryPartialReleaseObserved',False) for p in ['cad','compat','nocapture']):
    raise SystemExit(2)
