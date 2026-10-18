"""Loopback-only Safari receiver. It never generates input events."""
import json, threading, time, os
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output'
OUT.mkdir(exist_ok=True)
LOCK = threading.Lock()
STATE = {}
ACKED_BATCHES = {}
HTML = r'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Apple mouse input receiver</title><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;touch-action:none;font:16px system-ui;background:#edf5fb}canvas{position:absolute;inset:0;width:100%;height:100%;touch-action:none;outline:none}pre{position:absolute;pointer-events:none;white-space:pre-wrap;padding:20px}</style>
<canvas id="surface" tabindex="0"></canvas><pre id="state">Waiting for real incoming Safari events. Simulator only.</pre><script>
const params=new URLSearchParams(location.search),device=params.get('device'),policy=params.get('policy')||'cad';let queue=[],count=0,sending=false,batch=0,pending=null;
const recorderSession=crypto.randomUUID();
async function flush(){
 if(sending||(!pending&&!queue.length))return;
 sending=true;
 if(!pending)pending={id:++batch,body:JSON.stringify(queue.splice(0))};
 // One upload at a time preserves browser event order. Retrying the exact
 // batch is idempotent even when its earlier response was lost.
 try {const r=await fetch('/events?device='+device+'&session='+recorderSession+'&batch='+pending.id,{method:'POST',headers:{'Content-Type':'application/json'},body:pending.body});if(!r.ok)throw Error('recording HTTP '+r.status);pending=null;}
 catch(error){document.querySelector('#state').textContent='Recording retry: '+error.message;}
 finally {sending=false;}
}
queue.push({type:'page-ready',surface:'canvas',policy,recorderSession,recorderVersion:2,userAgent:navigator.userAgent,width:innerWidth,height:innerHeight,t:performance.now(),capabilities:{pointerLock:typeof document.body.requestPointerLock,pointerRawUpdate:'onpointerrawupdate' in window,coalescedEvents:typeof PointerEvent.prototype.getCoalescedEvents}});
// Match the existing CAD's input surface policy without sending synthetic input.
const surface=document.querySelector('#surface');
for(const type of ['pointerdown','pointermove','pointerup'])surface.addEventListener(type,e=>{
 // Compare compatibility MouseEvents with the CAD's current suppression policy.
 // This is a receiver-only experiment; it does not modify the CAD's controls.
 if(policy==='cad')e.preventDefault();
 if(type==='pointerdown'){surface.focus({preventScroll:true});if(policy!=='nocapture')surface.setPointerCapture(e.pointerId);}
},{passive:false});
// Native API transport is recorded separately. It never impersonates a trusted
// browser PointerEvent or fabricates a button release from time or motion.
window.nativeMouseInput=item=>{queue.push({...item,t:performance.now()});};
for(const type of ['pointerdown','pointermove','pointerrawupdate','pointerup','pointercancel','gotpointercapture','lostpointercapture','mousedown','mouseup','mousemove','wheel','contextmenu'])document.addEventListener(type,e=>{const item={type,pointerType:e.pointerType,button:e.button,buttons:e.buttons,x:e.clientX,y:e.clientY,deltaX:e.deltaX,deltaY:e.deltaY,isTrusted:e.isTrusted,fromTouch:e.sourceCapabilities?.firesTouchEvents,eventTimestamp:e.timeStamp,t:performance.now()};queue.push(item);if(e.getCoalescedEvents)for(const c of e.getCoalescedEvents())queue.push({type:'coalesced',parent:type,pointerType:c.pointerType,button:c.button,buttons:c.buttons,x:c.clientX,y:c.clientY,isTrusted:c.isTrusted,timestamp:c.timeStamp,t:performance.now()});document.querySelector('#state').textContent='Received '+(++count)+' events\n'+JSON.stringify(item,null,2);if(type==='contextmenu'||type==='wheel')e.preventDefault();},{passive:false});
setInterval(flush,200);flush();
</script>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        parsed=urlparse(self.path)
        if parsed.path=='/latest':
            device=parse_qs(parsed.query).get('device',[''])[0]
            with LOCK: body=json.dumps(STATE.get(device,{})).encode()
            self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body);return
        self.send_response(200)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(HTML.encode())
    def do_POST(self):
        parsed=urlparse(self.path)
        device=parse_qs(parsed.query).get('device',[''])[0]
        allowed={k+p for k in ('iphone','ipad') for p in ('','-native','-universal','-locked','-trackpad','-off-before','-off-after','-native-on','-policy-default','-policy-direct','-universal-on','-repeat-first','-repeat-reused','-repeat-recreated','-universal-native-first','-universal-native-relaunch','-clean-first','-clean-relaunch','-html-cad','-html-compat','-html-nocapture')}
        if parsed.path!='/events' or device not in allowed:
            self.send_error(400);return
        size=int(self.headers.get('Content-Length','0'))
        if size>1048576:
            self.send_error(413);return
        try:
            events=json.loads(self.rfile.read(size))
            if not isinstance(events,list):raise ValueError('Expected event array')
            query=parse_qs(parsed.query)
            session=query.get('session',[''])[0]
            batch=int(query.get('batch',['0'])[0])
            with LOCK, (OUT/(device+'-events.jsonl')).open('a',encoding='utf-8') as f:
                if session:
                    key=(device,session)
                    previous=ACKED_BATCHES.get(key,0)
                    if batch<=previous:
                        self.send_response(204);self.end_headers();return
                    if batch!=previous+1:
                        self.send_error(409,'Recording batch gap');return
                for e in events:
                    f.write(json.dumps(e,ensure_ascii=False)+'\n')
                    state=STATE.setdefault(device,{})
                    if e.get('type')=='page-ready':state.update(width=e['width'],height=e['height'])
                    if e.get('pointerType')=='mouse' and e.get('isTrusted') and e.get('x',-1)>=0 and e.get('y',-1)>=0:state.update(x=e['x'],y=e['y'],buttons=e.get('buttons'),t=e.get('t'))
                    if os.environ.get('PROBE_RAW_MOUSE')=='1' and e.get('origin')=='public-native-api' and e.get('api')=='GCMouse' and e.get('type')=='native-move':
                        state.update(x=e['x'],y=e['y'],buttons=e['buttons'],t=e['t'],coordinateSource='GCMouse-relative')
                if session:ACKED_BATCHES[key]=batch
            self.send_response(204);self.end_headers()
        except (ValueError,TypeError):
            self.send_error(400)

if __name__=='__main__':
    ThreadingHTTPServer(('127.0.0.1',8765),Handler).serve_forever()
