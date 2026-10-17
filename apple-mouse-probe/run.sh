#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p output
sw_vers > output/host.txt
xcodebuild -version >> output/host.txt
xcrun simctl list -j > output/simulators.json
xcode-select -p > output/developer-dir.txt
python3 - <<'PY'
import json,re
from pathlib import Path
d=json.loads(Path('output/simulators.json').read_text())
runtimes={r['identifier']:r for r in d['runtimes'] if r.get('isAvailable') and 'iOS' in r['identifier']}
key=lambda s:tuple(int(x) for x in re.findall(r'\d+',runtimes[s].get('version','0')))
plan=[]
for kind,prefix in [('iphone','iPhone'),('ipad','iPad')]:
    for rid in sorted(runtimes,key=key,reverse=True):
        candidates=[x for x in d['devices'].get(rid,[]) if x.get('isAvailable') and x['name'].startswith(prefix)]
        if candidates:
            device=candidates[-1]
            plan.append({'kind':kind,'udid':device['udid'],'name':device['name'],'runtime':runtimes[rid]['version'],'physicalDevice':False})
            break
Path('output/plan.json').write_text(json.dumps(plan,indent=2))
Path('output/plan.tsv').write_text(''.join(f"{p['kind']}\t{p['udid']}\n" for p in plan))
if len(plan)!=2:raise SystemExit('Both iPhone/iPad installed runtimes are required; no older OS is silently substituted.')
PY
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreFoundation -framework IOKit injector.m -o output/injector 2>output/compile.log
python3 receiver.py >output/receiver.log 2>&1 &
receiver_pid=$!
current_device=''
cleanup(){ kill "$receiver_pid" 2>/dev/null || true; if [[ -n "$current_device" ]]; then xcrun simctl shutdown "$current_device" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT
while IFS=$'\t' read -r kind udid; do
  current_device="$udid"
  xcrun simctl boot "$udid" >"output/$kind-boot.log" 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >>"output/$kind-boot.log" 2>&1
  xcrun simctl openurl "$udid" "http://127.0.0.1:8765/?device=$kind"
  python3 - "$kind" <<'PY'
import sys,time
from pathlib import Path
p=Path('output')/(sys.argv[1]+'-events.jsonl')
for _ in range(40):
    if p.exists() and 'page-ready' in p.read_text():break
    time.sleep(1)
else:raise SystemExit('Safari receiver did not report ready')
PY
  output/injector "$(xcode-select -p)" "$udid" >"output/$kind-injector.log" 2>&1 || true
  sleep 2
  xcrun simctl io "$udid" screenshot "output/$kind-after.png" >"output/$kind-screenshot.log" 2>&1 || true
  xcrun simctl shutdown "$udid" >>"output/$kind-boot.log" 2>&1
  current_device=''
done < output/plan.tsv
python3 assess.py
