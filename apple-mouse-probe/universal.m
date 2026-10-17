// Isolated CoreSimulator XPC diagnostic. No host input or application focus.
// Protocol names were observed in the installed dtuhidd binary; connection
// API shape cross-checked against Meta idb and tmoonlight/acecode sources.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <xpc/xpc.h>
#import <unistd.h>
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
    for(NSString *service in @[@"com.apple.coredevice.feature.remote.universalhidservice",@"com.apple.coredevice.feature.remote.universalhid"]){
        printf("SERVICE %s\n",service.UTF8String);
        unsigned int port=((unsigned int(*)(id,SEL,id,NSError**))objc_msgSend)(device,NSSelectorFromString(@"lookup:error:"),service,&error);
        if(!port){printf("lookup failed %s\n",error.description.UTF8String);continue;}
        xpc_object_t ep=endpoint(port,0,0);xpc_connection_t c=ep?connect(ep):nil;if(!c)continue;
        enable(c);xpc_connection_set_event_handler(c,^(xpc_object_t e){show("unsolicited",e);});xpc_connection_resume(c);
        xpc_object_t barrier=dict();xpc_dictionary_set_bool(barrier,"isBarrier",true);request(c,barrier);
        xpc_object_t q=dict();xpc_dictionary_set_value(q,[service hasSuffix:@"universalhidservice"]?"connectedServices":"supportedDevices",dict());request(c,envelope(service,q));
        // Probe only the schema of a mouse service. Responses remain evidence,
        // never classified as actual mouse events reaching Safari.
        xpc_object_t mouse=dict(),type=dict(),body=dict(),msg=dict();
        xpc_dictionary_set_value(type,"mouse",mouse);
        xpc_dictionary_set_value(body,"deviceType",type);
        xpc_dictionary_set_value(msg,"connect",body);
        if([service hasSuffix:@"universalhid"])request(c,envelope(service,msg));
        xpc_connection_cancel(c);
    }
    return 0;
}}
