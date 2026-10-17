// Experimental SimulatorKit pointer route. No host desktop input/focus changes.
// API declarations and selectors are based on the references in README.txt.
// A successful send is NOT proof that Safari received a mouse event.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <math.h>
typedef CFTypeRef Event;
typedef Event (*MouseFn)(CFAllocatorRef,uint64_t,double,double,double,uint32_t,uint32_t);
typedef Event (*ScrollFn)(CFAllocatorRef,uint64_t,double,double,double,uint32_t);
typedef void *(*WrapFn)(Event,uint32_t);
typedef void *(*ServiceFn)(void);
typedef uint32_t (*TypeFn)(Event);
static id client;
static MouseFn mouseEvent;
static ScrollFn scrollEvent;
static WrapFn wrapMouse,wrapScroll;
static TypeFn eventType;
static int sent=0,rejected=0;
static void settle(double seconds){[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];}
static void deliver(void *p){
    if(!p){rejected++;fprintf(stderr,"wrapper returned nil\n");return;}
    SEL s=NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    ((void(*)(id,SEL,void*,BOOL,id,id))objc_msgSend)(client,s,p,YES,nil,nil);
    sent++;settle(0.04);
}
static void mouse(double dx,double dy,uint32_t buttons){
    Event e=mouseEvent(kCFAllocatorDefault,mach_absolute_time(),dx,dy,0,buttons,0);
    if(!e){rejected++;return;}
    printf("mouse dx=%g dy=%g buttons=%u hidType=%u\n",dx,dy,buttons,eventType?eventType(e):0);
    deliver(wrapMouse(e,0x36));CFRelease(e);
}
static void center(void){mouse(-4000,-4000,0);mouse(200,300,0);}
int main(int argc,const char **argv){@autoreleasepool{
    if(argc!=3){fprintf(stderr,"usage: injector developer-dir simulator-udid\n");return 2;}
    NSString *dev=@(argv[1]),*udid=@(argv[2]);
    void *core=dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW|RTLD_GLOBAL);
    NSString *path=[dev stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"];
    void *kit=dlopen(path.UTF8String,RTLD_NOW|RTLD_GLOBAL);
    void *io=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_NOW|RTLD_GLOBAL);
    if(!core||!kit||!io){fprintf(stderr,"framework unavailable: %s\n",dlerror());return 3;}
    mouseEvent=(MouseFn)dlsym(io,"IOHIDEventCreateMouseEvent");
    scrollEvent=(ScrollFn)dlsym(io,"IOHIDEventCreateScrollEvent");
    eventType=(TypeFn)dlsym(io,"IOHIDEventGetType");
    wrapMouse=(WrapFn)dlsym(kit,"IndigoHIDMessageForPointerEventFromHIDEventRef");
    wrapScroll=(WrapFn)dlsym(kit,"IndigoHIDMessageForScrollEventFromHIDEventRef");
    printf("symbols mouse=%d scroll=%d pointerWrapper=%d scrollWrapper=%d\n",mouseEvent!=NULL,scrollEvent!=NULL,wrapMouse!=NULL,wrapScroll!=NULL);
    if(!mouseEvent||!wrapMouse){fprintf(stderr,"required pointer symbols unavailable\n");return 4;}
    Class contextClass=NSClassFromString(@"SimServiceContext");
    SEL ctxSel=NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:");
    NSError *error=nil;
    if(![contextClass respondsToSelector:ctxSel])return 5;
    id context=((id(*)(id,SEL,id,NSError**))objc_msgSend)(contextClass,ctxSel,dev,&error);
    SEL setSel=NSSelectorFromString(@"defaultDeviceSetWithError:");
    if(![context respondsToSelector:setSel])return 6;
    id set=((id(*)(id,SEL,NSError**))objc_msgSend)(context,setSel,&error),device=nil;
    for(id candidate in [set valueForKey:@"availableDevices"]){if([[[candidate valueForKey:@"UDID"] UUIDString] isEqualToString:udid]){device=candidate;break;}}
    Class hid=NSClassFromString(@"_TtC12SimulatorKit24SimDeviceLegacyHIDClient");
    SEL init=NSSelectorFromString(@"initWithDevice:error:");
    if(!device||!hid||![hid instancesRespondToSelector:init]){fprintf(stderr,"device/HID client unavailable\n");return 7;}
    client=((id(*)(id,SEL,id,NSError**))objc_msgSend)([hid alloc],init,device,&error);
    SEL sendSel=NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    if(![client respondsToSelector:sendSel]){fprintf(stderr,"send selector unavailable\n");return 8;}
    for(const char **name=(const char*[]){"IndigoHIDMessageToCreatePointerService","IndigoHIDMessageToCreateMouseService",NULL};*name;name++){
        ServiceFn f=(ServiceFn)dlsym(kit,*name);printf("service %s available=%d\n",*name,f!=NULL);if(f)deliver(f());
    }
    settle(1);
    center();
    for(uint32_t button=1;button<=2;button++){
        printf("BEGIN single-button %u\n",button);center();mouse(0,0,button);mouse(0,0,0);
        for(int hour=1;hour<=12;hour++){
            center();mouse(0,0,button);
            double a=(hour*30-90)*M_PI/180.;
            for(int step=0;step<4;step++)mouse(16*cos(a),16*sin(a),button);
            mouse(0,0,0);
        }
    }
    const uint32_t chords[4][5]={{0,1,3,1,0},{0,1,3,2,0},{0,2,3,2,0},{0,2,3,1,0}};
    for(int i=0;i<4;i++){
        printf("BEGIN chord %u %u %u %u %u\n",chords[i][0],chords[i][1],chords[i][2],chords[i][3],chords[i][4]);center();
        for(int j=1;j<5;j++){mouse(0,0,chords[i][j]);if(chords[i][j]==3)for(int k=0;k<4;k++)mouse(12,10,3);}
    }
    center();
    if(scrollEvent&&wrapScroll){for(int d=-1;d<=1;d+=2){Event e=scrollEvent(kCFAllocatorDefault,mach_absolute_time(),0,d*120,0,0);if(e){deliver(wrapScroll(e,0x36));CFRelease(e);}}}
    mouse(0,0,0);settle(1);
    ServiceFn remove=(ServiceFn)dlsym(kit,"IndigoHIDMessageToRemovePointerService");if(remove)deliver(remove());
    printf("sent=%d rejected=%d; inspect Safari receiver logs before drawing any conclusion\n",sent,rejected);
    return rejected?9:0;
}}
