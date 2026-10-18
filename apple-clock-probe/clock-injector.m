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
static uint32_t target=0x36;
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
    printf("mouse time=%.6f dx=%g dy=%g buttons=%u hidType=%u\n",NSDate.date.timeIntervalSince1970,dx,dy,buttons,eventType?eventType(e):0);
    deliver(wrapMouse(e,target));CFRelease(e);
}
static BOOL calibrationFailed=NO;
static NSDictionary *readPage(NSString *path){
    NSURL *url=[NSURL URLWithString:[@"http://127.0.0.1:8765" stringByAppendingString:path]];
    NSData *data=[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:2] returningResponse:NULL error:NULL];
    return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:@{};
}
static BOOL moveTo(double x,double y,uint32_t buttons){
    for(int i=0;i<24;i++){
        NSDictionary *p=readPage(@"/latest?device=ipad-html-cad");
        double age=NSDate.date.timeIntervalSince1970-[p[@"positionWall"] doubleValue];
        BOOL fresh=p[@"x"]&&p[@"positionWall"]&&[p[@"positionValid"] boolValue]&&age>=0&&age<2;
        if(fresh){
            double dx=x-[p[@"x"] doubleValue],dy=y-[p[@"y"] doubleValue];
            if(fabs(dx)<2&&fabs(dy)<2)return YES;
            mouse(fmax(-30,fmin(30,dx*.5)),fmax(-30,fmin(30,dy*.5)),buttons);
        }else if(!p[@"x"])mouse(40,50,buttons);
        else {printf("Clock pointer feedback stale age=%g\n",age);mouse(1,0,buttons);}
        settle(.2);
    }
    calibrationFailed=YES;printf("Clock position unavailable; abort remaining gestures\n");return NO;
}
static CGPoint anchor(void){
    NSDictionary *s=readPage(@"/clock-state"),*r=s[@"canvas"];
    return CGPointMake([r[@"x"] doubleValue]+[r[@"width"] doubleValue]*.45,[r[@"y"] doubleValue]+[r[@"height"] doubleValue]*.45);
}
static int caseFailures=0;
static void outcome(NSString *name,NSDictionary *before,NSDictionary *held,int expected,NSString *property,BOOL cancel,BOOL view){
    settle(.6);NSDictionary *after=readPage(@"/clock-state");
    BOOL sameEntities=[after[@"entityCount"] isEqual:before[@"entityCount"]];
    BOOL pass=!calibrationFailed&&after[@"command"]&&[after[@"command"] intValue]==expected&&sameEntities&&[after[@"visibility"] isEqual:@"visible"];
    NSString *expectedLabel=[name containsString:@"text"]?@"文字":[name containsString:@"AM1"]?@"線・矩形":[name containsString:@"ortho"]?@"水平・垂直":[name containsString:@"dimension"]?@"寸法":cancel?@"キャンセル":nil;
    BOOL preview=expectedLabel?[held[@"clock"][@"label"] isEqual:expectedLabel]&&![held[@"clock"][@"display"] isEqual:@"none"]:[held[@"clock"][@"display"] isEqual:@"none"];
    pass=pass&&preview;
    if(property)pass=pass&&[after[property] boolValue]!=[before[property] boolValue];
    if(cancel)pass=pass&&[after[@"view"] isEqual:before[@"view"]];
    if(view)pass=pass&&![after[@"view"] isEqual:before[@"view"]];
    if(!pass)caseFailures++;
    NSDictionary *result=@{@"name":name,@"passed":@(pass),@"before":before?:@{},@"held":held?:@{},@"after":after?:@{},@"expectedCommand":@(expected),@"expectedPreview":expectedLabel?:@"clock hidden",@"previewMatched":@(preview),@"entityCountUnchanged":@(sameEntities),@"wall":@(NSDate.date.timeIntervalSince1970)};
    printf("CLOCK_RESULT %s\n",[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] encoding:NSUTF8StringEncoding].UTF8String);
}
static void clockCase(NSString *name,int hour,BOOL opposite,BOOL returnCenter,BOOL cancel,int expected,NSString *property){
    if(calibrationFailed)return;
    CGPoint p=anchor();if(!moveTo(p.x,p.y,0))return;
    settle(.3);NSDictionary *before=readPage(@"/clock-state");
    mouse(0,0,1);settle(.3);
    double angle=hour*M_PI/6,tx=p.x+90*sin(angle),ty=p.y-90*cos(angle);
    if(!moveTo(tx,ty,1)){mouse(0,0,0);return;}
    if(opposite){mouse(0,0,3);settle(.4);mouse(0,0,1);settle(.4);}
    if(returnCenter){if(!moveTo(p.x,p.y,1)){mouse(0,0,0);return;}settle(.3);if(!cancel&&!moveTo(tx,ty,1)){mouse(0,0,0);return;}}
    settle(.4);NSDictionary *held=readPage(@"/clock-state");
    mouse(0,0,0);outcome(name,before,held,expected,property,cancel,NO);
}
static void center(void){
    if(calibrationFailed)return;
    NSString *kind=@(getenv("PROBE_DEVICE")?:"ipad");
    NSURL *url=[NSURL URLWithString:[@"http://127.0.0.1:8765/latest?device=" stringByAppendingString:kind]];
    // Fresh feedback must come from the selected input route. Old DOM positions
    // cannot calibrate a native UIKit route, or silently mask a lost release.
    mouse(1,0,0);settle(.3);
    for(int i=0;i<24;i++){
        NSData *data=[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1] returningResponse:NULL error:NULL];
        NSDictionary *position=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
        double x=[position[@"x"] doubleValue],y=[position[@"y"] doubleValue];
        double width=[position[@"width"] doubleValue],height=[position[@"height"] doubleValue];
        double age=NSDate.date.timeIntervalSince1970-[position[@"positionWall"] doubleValue];
        BOOL fresh=position[@"positionWall"] && age>=0 && age<2;
        BOOL neutral=position[@"buttons"] && [position[@"buttons"] unsignedIntegerValue]==0;
        if(position[@"x"] && width>0 && height>0 && fresh && [position[@"positionValid"] boolValue] && neutral){
            double ex=width*.4-x,ey=height*.4-y;
            if(fabs(ex)<8 && fabs(ey)<8){printf("Page mouse position confirmed x=%g y=%g age=%.3f buttons=0 source=%s\n",x,y,age,[position[@"coordinateSource"] UTF8String]);return;}
            mouse(fmax(-60,fmin(60,ex*.5)),fmax(-60,fmin(60,ey*.5)),0);
        } else if(!position[@"x"])mouse(60,70,0);
        else {printf("Waiting for fresh neutral feedback age=%.3f buttons=%u valid=%d\n",age,[position[@"buttons"] unsignedIntValue],[position[@"positionValid"] boolValue]);}
        settle(.25);
    }
    calibrationFailed=YES;printf("Page mouse position unavailable; do not interpret button tests as a platform result\n");
}
int main(int argc,const char **argv){@autoreleasepool{
    setvbuf(stdout,NULL,_IONBF,0);
    setvbuf(stderr,NULL,_IONBF,0);
    if(argc!=3){fprintf(stderr,"usage: injector developer-dir simulator-udid\n");return 2;}
    if(getenv("PROBE_TARGET"))target=(uint32_t)strtoul(getenv("PROBE_TARGET"),NULL,0);
    if(target!=0x35&&target!=0x36)return 2;
    printf("Input service target=%u\n",target);
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
    // A recreated phase must remove BOTH services. Previously only the pointer
    // service was removed, leaving the independent mouse service alive.
    if(getenv("PROBE_RESET_SERVICES")){
        for(const char **name=(const char*[]){"IndigoHIDMessageToRemoveMouseService","IndigoHIDMessageToRemovePointerService",NULL};*name;name++){
            ServiceFn f=(ServiceFn)dlsym(kit,*name);printf("reset service %s available=%d\n",*name,f!=NULL);
            if(!f)return 10;deliver(f());
        }
        settle(2);
    }
    if(getenv("PROBE_REUSE_SERVICES"))printf("Reusing previously created pointer/mouse services\n");
    else for(const char **name=(const char*[]){"IndigoHIDMessageToCreatePointerService","IndigoHIDMessageToCreateMouseService",NULL};*name;name++){
        if(strcmp(getenv("PROBE_MOUSE_ONLY")?:"","1")==0 && strcmp(*name,"IndigoHIDMessageToCreatePointerService")==0){printf("Skipping separate pointer service: mouse-only control\n");continue;}
        ServiceFn f=(ServiceFn)dlsym(kit,*name);printf("service %s available=%d\n",*name,f!=NULL);if(f)deliver(f());
    }
    settle(3);
    if(getenv("PROBE_CREATE_ONLY")){printf("Services created only; no input injected\n");return 0;}
    clockCase(@"left-AM0-text",0,NO,NO,NO,5,nil);
    clockCase(@"left-AM1-line",1,NO,NO,NO,2,nil);
    clockCase(@"left-AM1-repeat-rectangle",1,NO,NO,NO,3,nil);
    clockCase(@"left-AM1-repeat-line",1,NO,NO,NO,2,nil);
    clockCase(@"left-PM3-opposite-button-ortho",3,YES,NO,NO,2,@"ortho");
    clockCase(@"left-PM11-opposite-button-dimension",11,YES,NO,NO,7,nil);
    clockCase(@"return-center-cancel",3,NO,YES,YES,7,nil);
    // The early opposite button must remain Jw two-button view operation.
    if(!calibrationFailed){
        CGPoint p=anchor();if(moveTo(p.x,p.y,0)){
            settle(.3);NSDictionary *before=readPage(@"/clock-state");
            mouse(0,0,1);mouse(0,0,3);moveTo(p.x+70,p.y+70,3);settle(.4);
            NSDictionary *held=readPage(@"/clock-state");mouse(0,0,1);settle(.4);mouse(0,0,0);
            outcome(@"early-chord-view",before,held,7,nil,NO,YES);
        }
    }
    // Independent center-return switch: PM3 applies in a line command.
    // Reset to line through the actual toolbar command using a clock gesture;
    // the reset is intentionally included as part of the ninth test trace.
    if(!calibrationFailed){
        CGPoint p=anchor();if(moveTo(p.x,p.y,0)){
            mouse(0,0,1);moveTo(p.x+45,p.y-78,1);mouse(0,0,0);settle(.5);
        }
    }
    clockCase(@"left-PM3-return-center-ortho",3,NO,YES,NO,2,@"ortho");
    mouse(0,0,0);settle(2);
    if(calibrationFailed)printf("ABORT: no button, scroll, or touch injection after calibration failure\n");
    if(!getenv("PROBE_KEEP_SERVICES"))for(const char **name=(const char*[]){"IndigoHIDMessageToRemoveMouseService","IndigoHIDMessageToRemovePointerService",NULL};*name;name++){
        ServiceFn remove=(ServiceFn)dlsym(kit,*name);printf("cleanup service %s available=%d\n",*name,remove!=NULL);
        if(remove)deliver(remove());else rejected++;
    }
    printf("sent=%d rejected=%d callbacks=%d callbackErrors=%d; inspect Safari receiver logs before drawing any conclusion\n",sent,rejected,callbacks,callbackErrors);
    return calibrationFailed?12:rejected?9:caseFailures?13:0;
}}

