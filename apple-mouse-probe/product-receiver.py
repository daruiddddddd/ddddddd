"""Instrument the already-public CAD download; never publish its source to Git.

The test copy keeps the published input handlers intact. Instrumentation only
records DOM events, visible zoom text, and opens the public bundled test fixture.
"""
import hashlib,json,urllib.request
from http.server import ThreadingHTTPServer
from urllib.parse import urlparse
from receiver import Handler,OUT

url='https://jw1036-rebuild-lab.ryu08ma.chatgpt.site/?v=mouse-product-042'
request=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
with urllib.request.urlopen(request,timeout=30) as response:
    data=response.read().decode('utf-8').replace('\r\n','\n').encode('utf-8')
# Exact application prefix verified against the current published local build.
# Hosting may append its own challenge script; that suffix is not application code.
prefix=data[:252559]
digest=hashlib.sha256(prefix).hexdigest()
if digest!='70be8c5e6210c798f1d8d0d2b763b1c77e7de12c72e462f19772f44dbcd24720':
    raise RuntimeError('Public application changed; refusing to test an unidentified build')
(OUT/'product-source.json').write_text(json.dumps({'url':url,'normalizedApplicationPrefixBytes':len(prefix),'sha256':digest,'version':'0.21.0-pen','instrumentation':'Read-only event/visible zoom recorder; bundled public sample opened programmatically','publicSiteModified':False},indent=2))
SCRIPT=r'''<script>
(()=>{
 const device=new URLSearchParams(location.search).get('device'),session=crypto.randomUUID();
 let q=[],pending=null,sending=false,batch=0,lastZoom=null;
 const put=e=>q.push({...e,t:performance.now()});
 async function flush(){if(sending||(!pending&&!q.length))return;sending=true;if(!pending)pending={id:++batch,body:JSON.stringify(q.splice(0))};try{const r=await fetch('/events?device='+device+'&session='+session+'&batch='+pending.id,{method:'POST',headers:{'Content-Type':'application/json'},body:pending.body});if(!r.ok)throw Error(r.status);pending=null;}catch(e){}finally{sending=false;}}
 const canvas=document.getElementById('canvas');
 function view(){const zoom=document.getElementById('zoom').textContent;if(zoom!==lastZoom){lastZoom=zoom;put({type:'product-view',zoom,title:document.getElementById('title').textContent});}}
 for(const type of ['pointerdown','pointermove','pointerup','pointercancel','mousedown','mouseup','mousemove','wheel'])canvas.addEventListener(type,e=>{put({type,pointerType:e.pointerType,pointerId:e.pointerId,button:e.button,buttons:e.buttons,x:e.clientX,y:e.clientY,isTrusted:e.isTrusted,deltaX:e.deltaX,deltaY:e.deltaY,eventTimestamp:e.timeStamp});requestAnimationFrame(()=>requestAnimationFrame(view));},{passive:true});
 addEventListener('error',e=>put({type:'product-error',message:e.message}));
 addEventListener('unhandledrejection',e=>put({type:'product-error',message:String(e.reason)}));
 setInterval(flush,200);
 document.getElementById('sample').click();
 let tries=0;const timer=setInterval(()=>{if(document.getElementById('title').textContent.includes('操作検証図面')&&document.getElementById('zoom').textContent.startsWith('× ')){clearInterval(timer);const r=canvas.getBoundingClientRect();put({type:'page-ready',product:true,width:innerWidth,height:innerHeight,canvas:{x:r.x,y:r.y,width:r.width,height:r.height},userAgent:navigator.userAgent});view();flush();}else if(++tries>=100){clearInterval(timer);put({type:'product-error',message:'Bundled sample did not open'});flush();}},100);
})();</script>'''
HTML=prefix+SCRIPT.encode('utf-8')
class ProductHandler(Handler):
    def do_GET(self):
        if urlparse(self.path).path=='/product':
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(HTML)
        else:super().do_GET()
ThreadingHTTPServer(('127.0.0.1',8765),ProductHandler).serve_forever()
