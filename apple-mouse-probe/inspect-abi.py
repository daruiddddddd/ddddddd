"""Read only the two relevant SimulatorKit wrapper functions for diagnostics."""
import subprocess
from pathlib import Path
dev=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
kit=dev.parent/'SharedFrameworks/SimulatorKit.framework/SimulatorKit'
if not kit.exists():kit=dev/'Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit'
out=Path(__file__).resolve().parent/'output';out.mkdir(exist_ok=True)
(out/'binary-info.txt').write_text(subprocess.check_output(['file',str(kit)],text=True))
strings=subprocess.check_output(['strings',str(kit)],text=True)
(out/'hid-transport-strings.txt').write_text('\n'.join(s for s in strings.splitlines() if any(t.lower() in s.lower() for t in ['IndigoPointer','IndigoMouse','DTUHID','remote.hid','sendWithMessage','PointerService','MouseService','pointerEvent','mouseEvent','scrollEvent'])))
for p in Path('/Library/Developer/PrivateFrameworks/CoreSimulator.framework').rglob('*dtuhid*'):
    if p.is_file() and p.name=='dtuhidd' and '/iOS/' in str(p):
        (out/'dtuhid-path.txt').write_text(str(p))
        data=subprocess.check_output(['strings',str(p)],text=True,errors='replace')
        (out/'dtuhid-strings.txt').write_text(data)
        (out/'dtuhid-libraries.txt').write_text(subprocess.check_output(['otool','-L',str(p)],text=True))
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