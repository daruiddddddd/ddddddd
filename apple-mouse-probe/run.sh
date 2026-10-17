#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p output
printf 'Starting isolated simulator experiment\n'
sw_vers > output/host.txt
xcodebuild -version >> output/host.txt
cat output/host.txt
xcrun simctl list -j > output/simulators.json
xcode-select -p > output/developer-dir.txt
python3 - <<'PY'
import json,re,os
from pathlib import Path
d=json.loads(Path('output/simulators.json').read_text())
runtimes={r['identifier']:r for r in d['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
key=lambda s:tuple(int(x) for x in re.findall(r'\d+',runtimes[s].get('version','0')))
plan=[]
for kind,prefix in [('iphone','iPhone'),('ipad','iPad')]:
    if os.environ.get('PROBE_DEVICE') and kind!=os.environ['PROBE_DEVICE']:continue
    for rid in sorted(runtimes,key=key,reverse=True):
        candidates=[x for x in d['devices'].get(rid,[]) if x.get('isAvailable') and x['name'].startswith(prefix)]
        if candidates:
            device=candidates[-1]
            plan.append({'kind':kind,'udid':device['udid'],'name':device['name'],'runtime':runtimes[rid]['version'],'physicalDevice':False})
            break
Path('output/plan.json').write_text(json.dumps(plan,indent=2))
Path('output/plan.tsv').write_text(''.join(f"{p['kind']}\t{p['udid']}\n" for p in plan))
if len(plan)!=(1 if os.environ.get('PROBE_DEVICE') else 2):raise SystemExit('Requested installed runtime missing')
PY
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreFoundation -framework IOKit injector.m -o output/injector 2>output/compile.log || { cat output/compile.log; exit 1; }
bash build-native.sh >output/native-compile.log 2>&1 || { cat output/native-compile.log; exit 1; }
xcrun clang -fobjc-arc -fblocks -framework Foundation universal.m -o output/universal 2>output/universal-compile.log || { cat output/universal-compile.log; exit 1; }
cat output/plan.json
kit="$(xcode-select -p)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
if [[ ! -f "$kit" ]]; then kit="$(xcode-select -p)/../SharedFrameworks/SimulatorKit.framework/SimulatorKit"; fi
strings "$kit" | grep 'IndigoHIDMessage \*' >output/simulator-kit-prototypes.txt || true
python3 receiver.py >output/receiver.log 2>&1 &
receiver_pid=$!
current_device=''
cleanup(){ kill "$receiver_pid" 2>/dev/null || true; if [[ -n "$current_device" ]]; then python3 bounded.py 20 xcrun simctl shutdown "$current_device" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT
while IFS=$'\t' read -r kind udid; do
  current_device="$udid"
  printf '\nStarting %s %s\n' "$kind" "$udid"
  python3 bounded.py 30 xcrun simctl boot "$udid" >"output/$kind-boot.log" 2>&1 || true
  python3 bounded.py 180 xcrun simctl bootstatus "$udid" -b >>"output/$kind-boot.log" 2>&1 || true
  cat "output/$kind-boot.log"
  if [[ -d "$(xcode-select -p)/Applications/Simulator.app" ]]; then
    python3 bounded.py 20 open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$udid" >>"output/$kind-boot.log" 2>&1 || true
  fi
  python3 bounded.py 20 xcrun simctl io "$udid" screenshot "output/$kind-before.png" >>"output/$kind-boot.log" 2>&1 || true
  python3 - "$kind" "$udid" <<'PY'
import sys,time
import subprocess
from pathlib import Path
kind,udid=sys.argv[1:]
p=Path('output')/(kind+'-universal-events.jsonl')
with (Path('output')/(kind+'-open.log')).open('w') as log:
    for attempt in range(2):
        if p.exists() and 'page-ready' in p.read_text():break
        print('Opening Safari',kind,'attempt',attempt+1,flush=True)
        for args in [['launch',udid,'com.apple.mobilesafari'],['openurl',udid,'http://127.0.0.1:8765/?device='+kind+'-universal']]:
            try: subprocess.run(['xcrun','simctl',*args],stdout=log,stderr=log,timeout=30)
            except subprocess.TimeoutExpired: log.write('command timeout\n')
        for _ in range(20):
            if p.exists() and 'page-ready' in p.read_text():break
            time.sleep(1)
    print('Safari ready:',p.exists() and 'page-ready' in p.read_text(),flush=True)
PY
  if [[ "$kind" == "iphone" ]]; then
    python3 bounded.py 35 xcrun simctl spawn "$udid" "$(pwd)/output/accessibility-setup" 1 >"output/$kind-accessibility-setup.log" 2>&1 || true
  fi
  python3 bounded.py 65 output/universal "$(xcode-select -p)" "$udid" >"output/$kind-universal.log" 2>&1 || true
  python3 bounded.py 30 xcrun simctl openurl "$udid" "http://127.0.0.1:8765/?device=$kind" >"output/$kind-legacy-page.log" 2>&1 || true
  sleep 5
  python3 bounded.py 90 output/injector "$(xcode-select -p)" "$udid" >"output/$kind-injector.log" 2>&1 || true
  head -35 "output/$kind-injector.log"
  sleep 2
  python3 bounded.py 20 xcrun simctl io "$udid" screenshot "output/$kind-after.png" >"output/$kind-screenshot.log" 2>&1 || true
  python3 bounded.py 45 xcrun simctl install "$udid" output/NativeProbe.app >"output/$kind-native-install.log" 2>&1 || python3 bounded.py 45 xcrun simctl install "$udid" output/NativeProbe.app >>"output/$kind-native-install.log" 2>&1
  python3 bounded.py 30 xcrun simctl launch "$udid" org.jwprobe.nativeinput >"output/$kind-native-launch.log" 2>&1
  python3 - "$kind" <<'PY'
import sys,time
from pathlib import Path
p=Path('output')/(sys.argv[1]+'-native-events.jsonl')
for _ in range(30):
    if p.exists() and 'page-ready' in p.read_text():break
    time.sleep(1)
print('Native WKWebView ready:',p.exists() and 'page-ready' in p.read_text(),flush=True)
PY
  PROBE_DEVICE="$kind-native" python3 bounded.py 90 output/injector "$(xcode-select -p)" "$udid" >"output/$kind-native-injector.log" 2>&1 || true
  sleep 2
  python3 bounded.py 20 xcrun simctl io "$udid" screenshot "output/$kind-native.png" >>"output/$kind-screenshot.log" 2>&1 || true
  container="$(xcrun simctl get_app_container "$udid" org.jwprobe.nativeinput data)"
  cp "$container/Documents/native-events.jsonl" "output/$kind-native-api.jsonl"
  python3 bounded.py 20 xcrun simctl terminate "$udid" org.jwprobe.nativeinput >>"output/$kind-native-launch.log" 2>&1 || true
  if [[ "$kind" == "iphone" ]]; then
    for phase in locked trackpad; do
      extra=()
      target=0x36
      if [[ "$phase" == "locked" ]]; then extra=(--pointer-lock); else target=0x35; fi
      python3 bounded.py 30 xcrun simctl launch "$udid" org.jwprobe.nativeinput --probe-phase "$phase" "${extra[@]}" >"output/$kind-$phase-launch.log" 2>&1 || true
      sleep 5
      PROBE_DEVICE="$kind-$phase" PROBE_TARGET="$target" python3 bounded.py 90 output/injector "$(xcode-select -p)" "$udid" >"output/$kind-$phase-injector.log" 2>&1 || true
      sleep 2
      cp "$container/Documents/native-events.jsonl" "output/$kind-$phase-api.jsonl"
      python3 bounded.py 20 xcrun simctl terminate "$udid" org.jwprobe.nativeinput >>"output/$kind-$phase-launch.log" 2>&1 || true
    done
    python3 bounded.py 20 xcrun simctl spawn "$udid" "$(pwd)/output/accessibility-setup" 0 >"output/$kind-accessibility-restore.log" 2>&1 || true
  fi
  python3 bounded.py 20 xcrun simctl shutdown "$udid" >>"output/$kind-boot.log" 2>&1 || true
  current_device=''
done < output/plan.tsv
python3 assess.py
