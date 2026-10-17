"""Classify received events without equating simulator/HID delivery to hardware."""
import json,os
from pathlib import Path

def assess(events):
    pointers=[e for e in events if e.get('type','').startswith('pointer') and e.get('pointerType')=='mouse' and e.get('isTrusted') and e.get('x',-1)>=0 and e.get('y',-1)>=0]
    runs=[];active=None
    for e in pointers:
        b=e.get('buttons',0)
        if active is None and e['type']=='pointerdown':active={'states':[0], 'both':[], 'ended':False,'stationaryRelease':False}
        if active is None:continue
        if active['states'][-1]==3 and b in (1,2) and active['both']:
            x,y=active['both'][-1]
            active['stationaryRelease']=abs(e.get('x',0)-x)<1e-6 and abs(e.get('y',0)-y)<1e-6
        if active['states'][-1]!=b:active['states'].append(b)
        if b==3 and e['type']=='pointermove':active['both'].append((e.get('x',0),e.get('y',0)))
        if e['type']=='pointercancel':active=None;continue
        if b==0:
            active['ended']=e['type']=='pointerup';runs.append(active);active=None
    sequences=[];stationarySequences=[]
    for r in runs:
        pts=r['both']
        moved=len(pts)>=2 and max((x-pts[0][0])**2+(y-pts[0][1])**2 for x,y in pts)>=100
        if r['ended'] and moved:
            sequences.append(r['states'])
            if r['stationaryRelease']:stationarySequences.append(r['states'])
    required=[[0,1,3,1,0],[0,1,3,2,0],[0,2,3,2,0],[0,2,3,1,0]]
    right=any(r['states']==[0,2,0] and r['ended'] for r in runs)
    left=any(r['states']==[0,1,0] and r['ended'] for r in runs)
    wheel={str(d):any(e.get('type')=='wheel' and e.get('isTrusted') and e.get('deltaY',0)*d>0 for e in events) for d in [-1,1]}
    return {'pageLoaded':any(e.get('type')=='page-ready' for e in events),'totalReceivedEvents':len(events),'mousePointerEvents':len(pointers),'touchPointerEvents':sum(e.get('pointerType')=='touch' for e in events),'leftClickObserved':left,'rightClickObserved':right,'chords':[{'sequence':s,'observed':s in sequences,'stationaryReleaseObserved':s in stationarySequences} for s in required],'wheel':wheel,'coreMouseDeliveryObserved':bool(pointers) and left and right and all(s in sequences for s in required) and all(wheel.values()),'stationaryPartialReleaseObserved':all(s in stationarySequences for s in required),'clockDirectionsAndTimingVerified':False,'physicalAppleDeviceVerified':False,'jwBehaviorParityVerified':False,'scope':'Apple Simulator Safari only; experimental injection. No physical mouse claim. State sequences requiring extra movement are not exact-operation passes.'}

if __name__=='__main__':
    out=Path(__file__).resolve().parent/'output'
    report={}
    for kind in ['iphone','ipad']:
        if os.environ.get('PROBE_DEVICE') and kind!=os.environ['PROBE_DEVICE']:continue
        p=out/(kind+'-events.jsonl')
        report[kind]=assess([json.loads(s) for s in p.read_text().splitlines()] if p.exists() else [])
    (out/'assessment.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False,indent=2))
    if not all(r['coreMouseDeliveryObserved'] and r['stationaryPartialReleaseObserved'] for r in report.values()):raise SystemExit(2)

