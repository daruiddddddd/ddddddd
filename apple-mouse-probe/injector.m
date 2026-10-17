// Experimental SimulatorKit pointer route. No host desktop input/focus changes.
// API declarations and selectors are based on the references in README.txt.
// A successful send is NOT proof that Safari received a mouse event.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <math.h>
#import <unistd.h>
#import <CoreGraphics/CoreGraphics.h>
typedef CFTypeRef Event;
typedef Event (*MouseFn)(CFAllocatorRef,uint64_t,double,double,double,uint32_t,uint32_t);
typedef Event (*ScrollFn)(CFAllocatorRef,uint64_t,double,double,double,uint32_t);
typedef void *(*WrapFn)(Event,uint32_t);
typedef void *(*ServiceFn)(void);
typedef uint32_t (*TypeFn)(Event);
typedef Event (*CreateFn)(CFAllocatorRef,uint32_t,uint64_t,uint32_t);
typedef void (*AppendFn)(Event,Event,uint32_t);
typedef void (*SetIntFn)(Event,uint32_t,int64_t);
typedef void (*SetFloatFn)(Event,uint32_t,double);
typedef int64_t (*GetIntFn)(Event,uint32_t);
static id client;
static MouseFn mouseEvent;
static ScrollFn scrollEvent;
static WrapFn wrapMouse,wrapScroll;
static TypeFn eventType;
static CreateFn createEvent;
static AppendFn appendEvent;
static SetIntFn setInt;
static SetFloatFn setFloat;
static GetIntFn getInt;
static uint32_t previousButtons=0;
static int sent=0,rejected=0;
static int callbacks=0;
static int callbackErrors=0;
static void settle(double seconds){
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while([until timeIntervalSinceNow]>0){
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
        usleep(1000);
    }
}
static void deliver(void *p){
    if(!p){rejected++;fprintf(stderr,"wrapper returned nil\n");return;}
    SEL s=NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    void (^done)(NSError*)=^(NSError *error){callbacks++;if(error){callbackErrors++;fprintf(stderr,"HID callback error %s\n",error.description.UTF8String);}};
    ((void(*)(id,SEL,void*,BOOL,id,id))objc_msgSend)(client,s,p,YES,dispatch_get_main_queue(),done);
    sent++;settle(0.12);
}
static void mouse(double dx,double dy,uint32_t buttons){
    if(dx==0 && dy==0 && buttons==previousButtons)return;
    Event e=mouseEvent(kCFAllocatorDefault,mach_absolute_time(),dx,dy,0,buttons,0);
    if(!e){rejected++;return;}
    // SimulatorKit rejects leaf pointer events. Include the raw motion and
    // changed button children, with number/state fields from IOHIDEventTypes.
    Event motion=(dx!=0||dy!=0)?mouseEvent(kCFAllocatorDefault,mach_absolute_time(),dx,dy,0,buttons,0):NULL;
    if(motion){appendEvent(e,motion,0);CFRelease(motion);}
    for(uint32_t n=1;n<=2;n++){
        uint32_t mask=1u<<(n-1);
        if(((buttons^previousButtons)&mask)==0)continue;
        Event b=createEvent(kCFAllocatorDefault,2,mach_absolute_time(),1);
        if(b){setInt(b,0x20000,buttons);setInt(b,0x20001,n);setInt(b,0x20002,1);setFloat(b,0x20003,(buttons&mask)?1:0);setInt(b,0x20004,(buttons&mask)?1:0);if(getInt)printf("button child mask=%lld number=%lld state=%lld\n",(long long)getInt(b,0x20000),(long long)getInt(b,0x20001),(long long)getInt(b,0x20004));appendEvent(e,b,0);CFRelease(b);}
    }
    previousButtons=buttons;
    printf("mouse dx=%g dy=%g buttons=%u hidType=%u\n",dx,dy,buttons,eventType?eventType(e):0);
    deliver(wrapMouse(e,0x36));CFRelease(e);
}
static BOOL calibrationFailed=NO;
static void center(void){
    if(calibrationFailed)return;
    NSString *kind=@(getenv("PROBE_DEVICE")?:"ipad");
    NSURL *url=[NSURL URLWithString:[@"http://127.0.0.1:8765/latest?device=" stringByAppendingString:kind]];
    for(int i=0;i<24;i++){
        NSData *data=[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1] returningResponse:NULL error:NULL];
        NSDictionary *position=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        double x=[position[@"x"] doubleValue],y=[position[@"y"] doubleValue];
        double width=[position[@"width"] doubleValue],height=[position[@"height"] doubleValue];
        if(position[@"x"] && x>100 && y>100 && x<width-150 && y<height-150){printf("Page mouse position confirmed x=%g y=%g\n",x,y);return;}
        mouse(60,70,0);settle(.25);
    }
    calibrationFailed=YES;printf("Page mouse position unavailable; do not interpret button tests as a platform result\n");
}
int main(int argc,const char **argv){@autoreleasepool{
    setvbuf(stdout,NULL,_IONBF,0);
    setvbuf(stderr,NULL,_IONBF,0);
    if(argc!=3){fprintf(stderr,"usage: injector developer-dir simulator-udid\n");return 2;}
    NSString *dev=@(argv[1]),*udid=@(argv[2]);
    void *core=dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW|RTLD_GLOBAL);
    if(!core)fprintf(stderr,"CoreSimulator load failed: %s\n",dlerror());
    NSArray *kitPaths=@[[[dev stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"SharedFrameworks/SimulatorKit.framework/SimulatorKit"],[dev stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"]];
    void *kit=NULL;
    for(NSString *path in kitPaths){
        if(![[NSFileManager defaultManager] fileExistsAtPath:path])continue;
        printf("Loading %s\n",path.UTF8String);
        kit=dlopen(path.UTF8String,RTLD_NOW|RTLD_GLOBAL);
        if(kit)break;
        fprintf(stderr,"SimulatorKit load failed: %s\n",dlerror());
    }
    void *io=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_NOW|RTLD_GLOBAL);
    if(!core||!kit||!io){fprintf(stderr,"framework unavailable: %s\n",dlerror());return 3;}
    mouseEvent=(MouseFn)dlsym(io,"IOHIDEventCreateMouseEvent");
    scrollEvent=(ScrollFn)dlsym(io,"IOHIDEventCreateScrollEvent");
    eventType=(TypeFn)dlsym(io,"IOHIDEventGetType");
    createEvent=(CreateFn)dlsym(io,"IOHIDEventCreate");
    appendEvent=(AppendFn)dlsym(io,"IOHIDEventAppendEvent");
    setInt=(SetIntFn)dlsym(io,"IOHIDEventSetIntegerValue");
    setFloat=(SetFloatFn)dlsym(io,"IOHIDEventSetFloatValue");
    getInt=(GetIntFn)dlsym(io,"IOHIDEventGetIntegerValue");
    wrapMouse=(WrapFn)dlsym(kit,"IndigoHIDMessageForPointerEventFromHIDEventRef");
    wrapScroll=(WrapFn)dlsym(kit,"IndigoHIDMessageForScrollEventFromHIDEventRef");
    printf("symbols mouse=%d scroll=%d pointerWrapper=%d scrollWrapper=%d\n",mouseEvent!=NULL,scrollEvent!=NULL,wrapMouse!=NULL,wrapScroll!=NULL);
    if(!mouseEvent||!wrapMouse||!createEvent||!appendEvent||!setInt||!setFloat){fprintf(stderr,"required pointer symbols unavailable\n");return 4;}
    Class contextClass=NSClassFromString(@"SimServiceContext");
    SEL ctxSel=NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:");
    NSError *error=nil;
    if(![contextClass respondsToSelector:ctxSel]){fprintf(stderr,"context selector unavailable\n");return 5;}
    printf("Creating CoreSimulator context\n");
    id context=((id(*)(id,SEL,id,NSError**))objc_msgSend)(contextClass,ctxSel,dev,&error);
    SEL setSel=NSSelectorFromString(@"defaultDeviceSetWithError:");
    if(![context respondsToSelector:setSel]){fprintf(stderr,"device set selector unavailable: %s\n",error.description.UTF8String);return 6;}
    printf("Resolving device set\n");
    id set=((id(*)(id,SEL,NSError**))objc_msgSend)(context,setSel,&error),device=nil;
    for(id candidate in [set valueForKey:@"availableDevices"]){if([[[candidate valueForKey:@"UDID"] UUIDString] isEqualToString:udid]){device=candidate;break;}}
    Class hid=NSClassFromString(@"_TtC12SimulatorKit24SimDeviceLegacyHIDClient");
    SEL init=NSSelectorFromString(@"initWithDevice:error:");
    if(!device||!hid||![hid instancesRespondToSelector:init]){fprintf(stderr,"device/HID client unavailable\n");return 7;}
    printf("Initializing HID client\n");
    client=((id(*)(id,SEL,id,NSError**))objc_msgSend)([hid alloc],init,device,&error);
    SEL sendSel=NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    if(![client respondsToSelector:sendSel]){fprintf(stderr,"send selector unavailable\n");return 8;}
    for(const char **name=(const char*[]){"IndigoHIDMessageToCreatePointerService","IndigoHIDMessageToCreateMouseService",NULL};*name;name++){
        ServiceFn f=(ServiceFn)dlsym(kit,*name);printf("service %s available=%d\n",*name,f!=NULL);if(f)deliver(f());
    }
    settle(3);
    center();
    for(uint32_t button=1;button<=2;button++){
        printf("BEGIN single-button %u\n",button);center();mouse(0,0,button);mouse(0,0,0);
    }
    const uint32_t chords[4][5]={{0,1,3,1,0},{0,1,3,2,0},{0,2,3,2,0},{0,2,3,1,0}};
    for(int i=0;i<4;i++){
        printf("BEGIN chord %u %u %u %u %u\n",chords[i][0],chords[i][1],chords[i][2],chords[i][3],chords[i][4]);center();
        for(int j=1;j<5;j++){mouse(0,0,chords[i][j]);if(chords[i][j]==3)for(int k=0;k<4;k++)mouse(12,10,3);if(j==3){settle(.5);mouse(2,0,chords[i][j]);settle(.5);}}
    }
    center();
    if(scrollEvent&&wrapScroll){for(int d=-1;d<=1;d+=2){Event e=scrollEvent(kCFAllocatorDefault,mach_absolute_time(),0,d*120,0,0);if(e){deliver(wrapScroll(e,0x36));CFRelease(e);}}}
    mouse(0,0,0);settle(2);
    // Positive control only. Touch reception is never classified as mouse parity.
    typedef void *(*TouchFn)(CGPoint*,CGPoint*,uint32_t,NSUInteger,CGSize,uint32_t);
    TouchFn touch=(TouchFn)dlsym(kit,"IndigoHIDMessageForMouseNSEvent");
    if(touch&&calibrationFailed){printf("BEGIN touch positive control; excluded from mouse pass\n");CGPoint p=CGPointMake(.5,.4);CGSize size=CGSizeMake(1,1);deliver(touch(&p,NULL,0x32,1,size,0));settle(.15);deliver(touch(&p,NULL,0x32,2,size,0));settle(2);}
    ServiceFn remove=(ServiceFn)dlsym(kit,"IndigoHIDMessageToRemovePointerService");if(remove)deliver(remove());
    printf("sent=%d rejected=%d callbacks=%d callbackErrors=%d; inspect Safari receiver logs before drawing any conclusion\n",sent,rejected,callbacks,callbackErrors);
    return rejected?9:0;
}}