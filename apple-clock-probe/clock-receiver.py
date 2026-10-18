"""Fetch a hash-pinned public CAD and observe actual Simulator Safari input.

Only the bundled public fixture is opened programmatically. jwTest is read only;
commands and clock gestures must arrive through the Simulator mouse device.
"""
import hashlib,json,os,urllib.request
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse
from receiver import Handler,OUT

url=os.environ['CLOCK_PUBLIC_URL']
expected=os.environ['CLOCK_PUBLIC_SHA256']
length=int(os.environ['CLOCK_PUBLIC_BYTES'])
with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=40) as response:
    downloaded=response.read().decode('utf-8').replace('\r\n','\n').encode()
prefix=downloaded[:length]
digest=hashlib.sha256(prefix).hexdigest()
if len(prefix)!=length or digest!=expected:raise RuntimeError('Published CAD hash mismatch; no input trial')
(OUT/'clock-source.json').write_text(json.dumps({'url':url,'version':'0.22.0-clock','normalizedApplicationPrefixBytes':length,'sha256':digest,'physicalDeviceVerified':False,'scope':'Published code fetched and served on cloud loopback; not direct public URL on Apple hardware','instrumentation':'Passive DOM/jwTest observation; bundled public sample opening only'},indent=2))
SCRIPT=r'''<script>(()=>{
 const channel=new URLSearchParams(location.search).get('device'),session=crypto.randomUUID();
 const canvas=document.getElementById('canvas');let q=[],pending=null,sending=false,batch=0,ready=false;
 const put=e=>q.push({...e,t:performance.now()});
 async function flush(){if(sending||(!pending&&!q.length))return;sending=true;if(!pending)pending={id:++batch,body:JSON.stringify(q.splice(0))};try{const r=await fetch('/events?device='+channel+'&session='+session+'&batch='+pending.id,{method:'POST',headers:{'Content-Type':'application/json'},body:pending.body});if(!r.ok)throw Error(r.status);pending=null;}catch(e){}finally{sending=false;}}
 function state(){const r=canvas.getBoundingClientRect(),c=document.getElementById('clock'),j=window.jwTest;return {type:'clock-state',version:j?.version,command:j?.command,ortho:document.getElementById('ortho').checked,fifteen:document.getElementById('fifteen').checked,entityCount:j?.drawing?.doc?.entities?.length,view:j?.view,zoom:document.getElementById('zoom').textContent,clock:{label:c.querySelector('span').textContent,display:getComputedStyle(c).display},canvas:{x:r.x,y:r.y,width:r.width,height:r.height},focused:document.hasFocus(),visibility:document.visibilityState};}
 for(const type of ['pointerdown','pointermove','pointerup','pointercancel','mousedown','mouseup','mousemove','wheel','contextmenu'])canvas.addEventListener(type,e=>put({type,pointerType:e.pointerType,pointerId:e.pointerId,button:e.button,buttons:e.buttons,x:e.clientX,y:e.clientY,isTrusted:e.isTrusted,eventTimestamp:e.timeStamp}),{passive:true});
 addEventListener('error',e=>put({type:'product-error',message:e.message}));
 addEventListener('unhandledrejection',e=>put({type:'product-error',message:String(e.reason)}));
 setInterval(()=>{if(ready)put(state());flush();},150);
 document.getElementById('sample').click();
 let tries=0;const timer=setInterval(()=>{if(window.jwTest?.drawing&&document.getElementById('title').textContent.includes('操作検証図面')){clearInterval(timer);ready=true;put({type:'page-ready',product:true,width:innerWidth,height:innerHeight,userAgent:navigator.userAgent});put(state());flush();}else if(++tries>=100){clearInterval(timer);put({type:'product-error',message:'Bundled public fixture did not open'});flush();}},100);
})();</script>'''
HTML=prefix+SCRIPT.encode()
class ClockHandler(Handler):
    def do_GET(self):
        path=urlparse(self.path).path
        if path=='/product':
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(HTML)
        elif path=='/clock-state':
            p=OUT/'ipad-html-cad-events.jsonl'
            states=[]
            if p.exists():
                for line in p.read_text().splitlines():
                    try:row=json.loads(line)
                    except ValueError:continue
                    if row.get('type')=='clock-state':states.append(row)
            body=json.dumps(states[-1] if states else {}).encode()
            self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
        else:super().do_GET()
ThreadingHTTPServer(('127.0.0.1',8765),ClockHandler).serve_forever()

