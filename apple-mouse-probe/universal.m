// Isolated CoreSimulator XPC diagnostic. No host input or application focus.
// Protocol names were observed in the installed dtuhidd binary; connection
// API shape cross-checked against Meta idb and tmoonlight/acecode sources.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <xpc/xpc.h>
#import <unistd.h>
#import <math.h>
static void pauseFor(double seconds){NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];while([until timeIntervalSinceNow]>0){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}}
static xpc_object_t dict(void){return xpc_dictionary_create(NULL,NULL,0);}
static xpc_object_t envelope(NSString *service, xpc_object_t payload){
    xpc_object_t message=dict();
    xpc_dictionary_set_string(message,"messageType","Request");
    xpc_dictionary_set_string(message,"featureIdentifier",service.UTF8String);
    xpc_dictionary_set_bool(message,"isBarrier",false);
    xpc_dictionary_set_value(message,"payload",payload);
    return message;
}
static void show(const char *label,xpc_object_t object){
    char *s=xpc_copy_description(object);printf("%s %s\n",label,s?s:"nil");free(s);
}
static xpc_object_t request(xpc_connection_t c,xpc_object_t object){
    dispatch_semaphore_t sem=dispatch_semaphore_create(0);
    __block xpc_object_t result=nil;
    show("request",object);
    xpc_connection_send_message_with_reply(c,object,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(xpc_object_t reply){result=reply;dispatch_semaphore_signal(sem);});
    if(dispatch_semaphore_wait(sem,dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC))){printf("reply timeout\n");return nil;}
    show("reply",result);return result;
}
static xpc_object_t operation(const char *name,xpc_object_t body){xpc_object_t p=dict();xpc_dictionary_set_value(p,name,body);return p;}
static xpc_object_t codedString(const char *value){xpc_object_t v=dict();xpc_dictionary_set_string(v,"string",value);return v;}
static xpc_object_t codedInt(int64_t value){xpc_object_t v=dict();xpc_dictionary_set_int64(v,"int",value);return v;}
static uint64_t findMouse(xpc_object_t response){
    xpc_object_t list=xpc_dictionary_get_value(response,"connectedServices");
    if(!list || xpc_get_type(list)!=XPC_TYPE_ARRAY)return 0;
    for(size_t i=0;i<xpc_array_get_count(list);i++){
        xpc_object_t item=xpc_array_get_value(list,i);const char *product=xpc_dictionary_get_string(item,"Product");
        if(product && strcmp(product,"Jw independent input probe")==0)return xpc_dictionary_get_uint64(item,"_ServiceID");
    }
    return 0;
}
static void pointer(xpc_connection_t c,NSString *service,uint64_t sid,int dx,int dy,uint8_t buttons){
    // PointerReport layout verified from the installed dtuhidd binary: 17 bytes,
    // report id 5, signed x/y, 16.16 accel x/y, button byte at offset 11.
    uint8_t bytes[17]={5,(uint8_t)dx,(uint8_t)dy};
    int32_t ax=dx*65536,ay=dy*65536;memcpy(bytes+3,&ax,4);memcpy(bytes+7,&ay,4);bytes[11]=buttons;
    xpc_object_t body=dict();xpc_dictionary_set_data(body,"_0",bytes,sizeof(bytes));xpc_dictionary_set_uint64(body,"_1",sid);
    printf("POINTER time=%.6f service=%llu dx=%d dy=%d buttons=%u\n",NSDate.date.timeIntervalSince1970,(unsigned long long)sid,dx,dy,buttons);
    xpc_connection_send_message(c,envelope(service,operation("send",body)));pauseFor(.2);
}
static void centerPointer(xpc_connection_t c,NSString *service,uint64_t sid){
    NSString *kind=@(getenv("PROBE_DEVICE")?:"ipad");
    NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:8765/latest?device=%@-universal",kind]];
    for(int i=0;i<20;i++){
        NSData *data=[NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1] returningResponse:nil error:nil];
        NSDictionary *p=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        if(p[@"x"]){double ex=[p[@"width"] doubleValue]*.4-[p[@"x"] doubleValue],ey=[p[@"height"] doubleValue]*.4-[p[@"y"] doubleValue];if(fabs(ex)<8&&fabs(ey)<8)return;pointer(c,service,sid,(int)round(fmax(-60,fmin(60,ex*.5))),(int)round(fmax(-60,fmin(60,ey*.5))),0);}
        else pointer(c,service,sid,30,40,0);
        pauseFor(.25);
    }
}
static void tryIndependentMouse(xpc_connection_t c,NSString *service){
    // Descriptor shape comes from the service's actual connectedServices reply.
    xpc_object_t descriptor=dict(),storage=dict(),pair=dict(),pairs=xpc_array_create(NULL,0);
    xpc_dictionary_set_int64(pair,"DeviceUsagePage",1);xpc_dictionary_set_int64(pair,"DeviceUsage",2);xpc_array_append_value(pairs,pair);
    xpc_dictionary_set_string(descriptor,"Product","Jw independent input probe");
    xpc_dictionary_set_string(descriptor,"DeviceTypeHint","Mouse");
    xpc_dictionary_set_uint64(descriptor,"PrimaryUsagePage",1);xpc_dictionary_set_uint64(descriptor,"PrimaryUsage",2);
    xpc_dictionary_set_uint64(descriptor,"_ServiceID",0xff0001);xpc_dictionary_set_value(descriptor,"DeviceUsagePairs",pairs);
    xpc_dictionary_set_value(storage,"Product",codedString("Jw independent input probe"));
    xpc_dictionary_set_value(storage,"DeviceTypeHint",codedString("Mouse"));
    xpc_dictionary_set_value(storage,"Transport",codedString("CoreDevice"));
    xpc_dictionary_set_value(storage,"PrimaryUsagePage",codedInt(1));xpc_dictionary_set_value(storage,"PrimaryUsage",codedInt(2));
    xpc_object_t idvalue=dict();xpc_dictionary_set_uint64(idvalue,"uint",0xff0001);xpc_dictionary_set_value(storage,"_ServiceID",idvalue);
    xpc_dictionary_set_value(descriptor,"_CoreDevice_codablePropertyStorage",storage);
    xpc_object_t body=dict();xpc_dictionary_set_value(body,"_0",descriptor);request(c,envelope(service,operation("createService",body)));
    pauseFor(2);
    xpc_object_t response=request(c,envelope(service,operation("connectedServices",dict())));
    uint64_t sid=response?findMouse(response):0;
    if(!sid){printf("Independent mouse not listed; no reports sent\n");return;}
    centerPointer(c,service,sid);
    for(int b=1;b<=2;b++){pointer(c,service,sid,0,0,b);pointer(c,service,sid,0,0,0);}
    const uint8_t chords[4][5]={{0,1,3,1,0},{0,1,3,2,0},{0,2,3,2,0},{0,2,3,1,0}};
    for(int i=0;i<4;i++){centerPointer(c,service,sid);for(int j=1;j<5;j++){pointer(c,service,sid,0,0,chords[i][j]);if(j==2)for(int k=0;k<4;k++)pointer(c,service,sid,10,8,3);if(j==3)pauseFor(1);}}
    pointer(c,service,sid,0,0,0);pauseFor(1);
    xpc_object_t remove=dict();xpc_dictionary_set_uint64(remove,"_0",sid);request(c,envelope(service,operation("removeService",remove)));
}
int main(int argc,const char **argv){@autoreleasepool{
    setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);
    if(argc!=3)return 2;
    printf("Loading CoreSimulator and SimulatorKit\n");
    void *core=dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator",RTLD_NOW|RTLD_GLOBAL);if(!core)return 3;
    NSString *kit=[[@(argv[1]) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"SharedFrameworks/SimulatorKit.framework/SimulatorKit"];
    dlopen(kit.UTF8String,RTLD_NOW|RTLD_GLOBAL);
    NSError *error=nil;
    printf("Creating context\n");
    id context=((id(*)(id,SEL,id,NSError**))objc_msgSend)(NSClassFromString(@"SimServiceContext"),NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:"),@(argv[1]),&error);
    printf("Resolving device\n");
    id set=((id(*)(id,SEL,NSError**))objc_msgSend)(context,NSSelectorFromString(@"defaultDeviceSetWithError:"),&error),device=nil;
    for(id candidate in [set valueForKey:@"availableDevices"]){if([[[candidate valueForKey:@"UDID"] UUIDString] isEqualToString:@(argv[2])]){device=candidate;break;}}
    NSString *version=[[NSBundle bundleForClass:NSClassFromString(@"SimDevice")] infoDictionary][@"CFBundleVersion"];
    printf("CoreSimulator version %s\n",version.UTF8String);
    if(!device)return 4;
    typedef xpc_object_t (*EndpointFn)(unsigned int,uint64_t,uint64_t);
    typedef xpc_connection_t (*ConnectFn)(xpc_object_t);
    typedef void (*EnableFn)(xpc_connection_t);
    EndpointFn endpoint=(EndpointFn)dlsym(RTLD_DEFAULT,"xpc_endpoint_create_mach_port_4sim");
    ConnectFn connect=(ConnectFn)dlsym(RTLD_DEFAULT,"xpc_connection_create_from_endpoint");
    EnableFn enable=(EnableFn)dlsym(RTLD_DEFAULT,"xpc_connection_enable_sim2host_4sim");
    if(!endpoint||!connect||!enable)return 5;
    for(NSString *service in @[@"com.apple.coredevice.feature.remote.universalhidservice"]){
        printf("SERVICE %s\n",service.UTF8String);
        unsigned int port=((unsigned int(*)(id,SEL,id,NSError**))objc_msgSend)(device,NSSelectorFromString(@"lookup:error:"),service,&error);
        if(!port){printf("lookup failed %s\n",error.description.UTF8String);continue;}
        xpc_object_t ep=endpoint(port,0,0);xpc_connection_t c=ep?connect(ep):nil;if(!c)continue;
        enable(c);xpc_connection_set_event_handler(c,^(xpc_object_t e){show("unsolicited",e);});xpc_connection_resume(c);
        xpc_object_t barrier=dict();xpc_dictionary_set_bool(barrier,"isBarrier",true);request(c,barrier);
        xpc_object_t q=dict();xpc_dictionary_set_value(q,[service hasSuffix:@"universalhidservice"]?"connectedServices":"supportedDevices",dict());request(c,envelope(service,q));
        tryIndependentMouse(c,service);
        xpc_connection_cancel(c);
    }
    return 0;
}}
