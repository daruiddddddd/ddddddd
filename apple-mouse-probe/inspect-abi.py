"""Read only the two relevant SimulatorKit wrapper functions for diagnostics."""
import subprocess,re
from pathlib import Path
dev=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
kit=dev.parent/'SharedFrameworks/SimulatorKit.framework/SimulatorKit'
if not kit.exists():kit=dev/'Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit'
out=Path(__file__).resolve().parent/'output';out.mkdir(exist_ok=True)
(out/'binary-info.txt').write_text(subprocess.check_output(['file',str(kit)],text=True))
strings=subprocess.check_output(['strings',str(kit)],text=True)
(out/'hid-transport-strings.txt').write_text('\n'.join(s for s in strings.splitlines() if any(t.lower() in s.lower() for t in ['IndigoPointer','IndigoMouse','DTUHID','remote.hid','sendWithMessage','PointerService','MouseService','pointerEvent','mouseEvent','scrollEvent'])))
paths=list(Path('/Library/Developer/PrivateFrameworks/CoreSimulator.framework').rglob('*dtuhid*'))
(out/'dtuhid-inventory.txt').write_text('\n'.join(str(p) for p in paths))
for p in paths:
    if p.is_file() and p.name=='dtuhidd' and '/iphoneos/' in str(p):
        (out/'dtuhid-path.txt').write_text(str(p))
        data=subprocess.check_output(['strings',str(p)],text=True,errors='replace')
        (out/'dtuhid-strings.txt').write_text(data)
        (out/'dtuhid-libraries.txt').write_text(subprocess.check_output(['otool','-L',str(p)],text=True))
        symbols=subprocess.check_output(['nm','-a',str(p)],text=True,errors='replace')
        selected='\n'.join(s for s in symbols.splitlines() if any(t in s for t in ['UniversalHIDRequest','HIDDeviceType','PointerReport','ScrollReport']))
        (out/'dtuhid-symbols.txt').write_text(selected)
        (out/'dtuhid-symbols-demangled.txt').write_text(subprocess.check_output(['xcrun','swift-demangle'],input=selected,text=True))
        targets=['PointerReportV10buttonMasks5UInt8Vvg','PointerReportV1xSivg','PointerReportV1ySivg','PointerReportV5flagsAC5FlagsVvg','PointerReportV8reportIDAA0eG0VvgZ','PointerReportV07initialE8BitCountSivgZ','PointerReportV6accelXSdvg','PointerReportV6accelYSdvg','PointerReportV15remoteTimestamps6UInt64VSgvg','HIDDeviceTypeO4from']
        named=[]
        for row in symbols.splitlines():
            match=re.match(r'([0-9a-f]+) [Tt] (.+)',row)
            if match:named.append((int(match[1],16),match[2]))
        named.sort();ranges=[(0x10005824c,0x10005897c,'HIDDeviceType decoder implementation (Xcode27 build inspected)')]
        for idx,(address,name) in enumerate(named):
            if any(t in name for t in targets):
                end=next((a for a,n in named[idx+1:] if a>address),address+2048)
                ranges.append((address,min(end,address+2600),name))
        proc=subprocess.Popen(['otool','-tvV',str(p)],stdout=subprocess.PIPE,text=True)
        found=[];active=False;count=0;prefix=[]
        for line in proc.stdout:
            if len(prefix)<40:prefix.append(line)
            match=re.match(r'([0-9a-f]{16})\s',line)
            if match:
                address=int(match[1],16)
                for start,end,name in ranges:
                    if start<=address<end:
                        if address==start:found.append(name+':\n')
                        found.append(line)
            if line.rstrip().endswith(':'):
                active=any(t in line for t in targets) or ('PointerReport' in line and '.getter' in line) or ('HIDDeviceType' in line and 'init(from:' in line);count=0
            if active and count<650:found.append(line);count+=1
        proc.wait()
        (out/'pointer-report-layout.txt').write_text(''.join(found))
        (out/'dtuhid-disassembly-prefix.txt').write_text(''.join(prefix))
        if not found:raise SystemExit('Pointer report disassembly missing')
        break
for name in ['IndigoHIDMessageForPointerEventFromHIDEventRef','IndigoHIDMessageForScrollEventFromHIDEventRef','IndigoHIDMessageToCreatePointerService','IndigoHIDMessageToCreateMouseService','_hidEventFilterCallback']:
    p=subprocess.Popen(['xcrun','otool','-tvV',str(kit)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    lines=[]
    for line in p.stdout:
        if name in line and line.rstrip().endswith(':'):lines.append(line);continue
        if not lines:continue
        if line.rstrip().endswith(':'):break
        lines.append(line)
        if len(lines)>=520:break
    p.terminate()
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait()
    (out/(name+'.txt')).write_text(''.join(lines))
    print(name,len(lines),'diagnostic lines')
    if len(lines)<10:raise SystemExit('No usable disassembly was returned')