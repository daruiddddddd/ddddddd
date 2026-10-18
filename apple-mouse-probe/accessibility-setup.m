// Test setup only, in the disposable Apple Simulator. Never ship this helper.
// AXSettings selectors cross-checked against nst/iOS-Runtime-Headers.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
int main(int argc,char **argv){@autoreleasepool{
    setvbuf(stdout,NULL,_IONBF,0);
    if(argc<2||argc>3)return 2;
    BOOL enabled=atoi(argv[1])!=0;
    void *handle=dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",RTLD_NOW|RTLD_GLOBAL);
    Class cls=NSClassFromString(@"AXSettings");
    SEL shared=NSSelectorFromString(@"sharedInstance"),setter=NSSelectorFromString(@"setAssistiveTouchEnabled:"),getter=NSSelectorFromString(@"assistiveTouchEnabled");
    if(!handle||![cls respondsToSelector:shared]){printf("AXSettings unavailable\n");return 3;}
    id settings=((id(*)(id,SEL))objc_msgSend)(cls,shared);
    // Test-only equivalent of the mouse-as-finger setting. Runtime header:
    // userlandkernel/ios17-dyld-headers, AccessibilityUtilities/AXSettings.h.
    // Save the actual prior value and restore it before disposing the simulator.
    NSString *mode=argc==3?@(argv[2]):@"";
    if(mode.length){
        SEL fg=NSSelectorFromString(@"assistiveTouchMouseBehavesLikeFinger");
        SEL fs=NSSelectorFromString(@"setAssistiveTouchMouseBehavesLikeFinger:");
        if(![settings respondsToSelector:fg]||![settings respondsToSelector:fs]){printf("Mouse-as-finger selectors unavailable\n");return 6;}
        NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"jwprobe-mouse-finger-original.json"];
        BOOL before=((BOOL(*)(id,SEL))objc_msgSend)(settings,fg),requested=NO;
        if([mode isEqualToString:@"no-finger"]){
            if([NSFileManager.defaultManager fileExistsAtPath:path]){printf("Original mouse setting already saved; refusing overwrite\n");return 7;}
            NSData *saved=[NSJSONSerialization dataWithJSONObject:@{@"original":@(before)} options:0 error:nil];
            if(![saved writeToFile:path atomically:YES])return 8;
        }else if([mode isEqualToString:@"restore-finger"]){
            NSData *saved=[NSData dataWithContentsOfFile:path];
            NSDictionary *previous=saved?[NSJSONSerialization JSONObjectWithData:saved options:0 error:nil]:nil;
            if(!previous[@"original"]){printf("No saved mouse setting; refusing guessed restore\n");return 9;}
            requested=[previous[@"original"] boolValue];
        }else return 10;
        ((void(*)(id,SEL,BOOL))objc_msgSend)(settings,fs,requested);
        BOOL after=((BOOL(*)(id,SEL))objc_msgSend)(settings,fg);
        printf("MouseBehavesLikeFinger before=%d requested=%d after=%d mode=%s\n",before,requested,after,mode.UTF8String);
        if(after!=requested)return 11;
        if([mode isEqualToString:@"restore-finger"])[NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
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
