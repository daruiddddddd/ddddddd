"""Read only the two relevant SimulatorKit wrapper functions for diagnostics."""
import subprocess
from pathlib import Path
dev=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
kit=dev.parent/'SharedFrameworks/SimulatorKit.framework/SimulatorKit'
if not kit.exists():kit=dev/'Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit'
out=Path(__file__).resolve().parent/'output';out.mkdir(exist_ok=True)
for name in ['IndigoHIDMessageForPointerEventFromHIDEventRef','IndigoHIDMessageForScrollEventFromHIDEventRef']:
    p=subprocess.Popen(['xcrun','otool','-arch','arm64','-tvV','-p','_'+name,str(kit)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    lines=[]
    for line in p.stdout:
        lines.append(line)
        if len(lines)>=240:break
    p.terminate()
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait()
    (out/(name+'.txt')).write_text(''.join(lines))
    print(name,len(lines),'diagnostic lines')
