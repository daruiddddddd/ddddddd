// Test setup only, in the disposable Apple Simulator. Never ship this helper.
// AXSettings selectors cross-checked against nst/iOS-Runtime-Headers.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
int main(int argc,char **argv){@autoreleasepool{
    setvbuf(stdout,NULL,_IONBF,0);
    if(argc!=2)return 2;
    BOOL enabled=atoi(argv[1])!=0;
    void *handle=dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",RTLD_NOW|RTLD_GLOBAL);
    Class cls=NSClassFromString(@"AXSettings");
    SEL shared=NSSelectorFromString(@"sharedInstance"),setter=NSSelectorFromString(@"setAssistiveTouchEnabled:"),getter=NSSelectorFromString(@"assistiveTouchEnabled");
    if(!handle||![cls respondsToSelector:shared]){printf("AXSettings unavailable\n");return 3;}
    id settings=((id(*)(id,SEL))objc_msgSend)(cls,shared);
    if(![settings respondsToSelector:setter]||![settings respondsToSelector:getter]){printf("AssistiveTouch selectors unavailable\n");return 4;}
    BOOL old=((BOOL(*)(id,SEL))objc_msgSend)(settings,getter);
    printf("AssistiveTouch before=%d requested=%d\n",old,enabled);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(settings,setter,enabled);
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:3];
    while([until timeIntervalSinceNow]>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    BOOL after=((BOOL(*)(id,SEL))objc_msgSend)(settings,getter);
    printf("AssistiveTouch setting after=%d publicRunning=%d\n",after,UIAccessibilityIsAssistiveTouchRunning());
    return after==enabled?0:5;
}}
