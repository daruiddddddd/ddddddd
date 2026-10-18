// Independent diagnostic: public UIKit / GameController API and WKWebView.
// No synthetic DOM events, no inferred releases, no product drawings.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <WebKit/WebKit.h>

static NSFileHandle *logFile;
static NSMutableSet<GCMouse *> *observedMice;
static NSMutableDictionary<NSValue *,NSNumber *> *buttonStates;
static dispatch_queue_t mouseQueue;
static dispatch_queue_t logQueue;
static WKWebView *bridgeView;
static CGPoint bridgePoint;
static BOOL hasBridgePoint=NO;
static NSUInteger bridgeButtons=0;
static BOOL rawMouseMode=NO;
static NSUInteger nextMouseId=0;
static NSMapTable<GCMouse *,NSNumber *> *mouseIdentities;
static NSMutableDictionary<NSNumber *,NSNumber *> *sampledMasks;
static NSUInteger observationSequence=0;
static void record(NSDictionary *data) {
    NSMutableDictionary *row=[data mutableCopy];
    row[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
    row[@"wall"]=@(NSDate.date.timeIntervalSince1970);
    // Preserve the callback-entry timestamp, but do not encode or write files
    // on the input queue. A busy renderer/logger must not hold up mouse edges.
    @synchronized(logFile){
    row[@"observationSequence"]=@(++observationSequence);
    dispatch_async(logQueue,^{
        NSData *bytes=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
        [logFile writeData:bytes]; [logFile writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    });
    }
}
static void bridge(NSDictionary *data) {
    if(!bridgeView || !hasBridgePoint)return;
    NSMutableDictionary *row=[data mutableCopy];
    row[@"x"]=@(bridgePoint.x); row[@"y"]=@(bridgePoint.y);
    row[@"buttons"]=@(bridgeButtons); row[@"nativeWall"]=@(NSDate.date.timeIntervalSince1970);
    row[@"origin"]=@"public-native-api";
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    [bridgeView evaluateJavaScript:[NSString stringWithFormat:@"window.nativeMouseInput && window.nativeMouseInput(%@)",json] completionHandler:^(id result,NSError *error){if(error)record(@{@"source":@"bridge",@"type":@"error",@"error":error.description});}];
}
static NSUInteger buttons(GCMouseInput *input) {
    return (input.leftButton.isPressed?1:0)|(input.rightButton.isPressed?2:0)|(input.middleButton.isPressed?4:0);
}
static NSUInteger receivedButtons(GCMouseInput *input){@synchronized(buttonStates){return [buttonStates[[NSValue valueWithNonretainedObject:input]] unsignedIntegerValue];}}
static NSNumber *identityForMouse(GCMouse *mouse){
    NSNumber *identity=[mouseIdentities objectForKey:mouse];
    if(!identity){identity=@(++nextMouseId);[mouseIdentities setObject:identity forKey:mouse];}
    return identity;
}
static void observeMouse(GCMouse *mouse) {
    if(!mouse || [observedMice containsObject:mouse])return;
    [observedMice addObject:mouse]; mouse.handlerQueue=mouseQueue;
    NSUInteger mouseId=identityForMouse(mouse).unsignedIntegerValue;
    record(@{@"source":@"GCMouse",@"type":@"connected",@"mouseId":@(mouseId),@"identity":[NSString stringWithFormat:@"%p",mouse],@"category":mouse.productCategory?:@"",@"vendor":mouse.vendorName?:@""});
    GCMouseInput *input=mouse.mouseInput;
    record(@{@"source":@"diagnostic",@"type":@"binding",@"mouseId":@(mouseId),@"inputIdentity":[NSString stringWithFormat:@"%p",input],@"profileIdentity":[NSString stringWithFormat:@"%p",mouse.physicalInputProfile],@"current":@(mouse==GCMouse.current)});
    // Independent observations only. They never feed the CAD or bridge.
    input.valueDidChangeHandler=^(GCPhysicalInputProfile *profile,GCControllerElement *element){
        NSString *name=element==input.leftButton?@"left":element==input.rightButton?@"right":element==input.middleButton?@"middle":@"other";
        record(@{@"source":@"diagnostic",@"type":@"profile-change",@"mouseId":@(mouseId),@"name":name,@"elementIdentity":[NSString stringWithFormat:@"%p",element],@"polledButtons":@(buttons(input)),@"profileTimestampRaw":@(profile.lastEventTimestamp)});
    };
    @synchronized(buttonStates){buttonStates[[NSValue valueWithNonretainedObject:input]]=@(buttons(input));}
    input.mouseMovedHandler=^(GCMouseInput *m,float dx,float dy){
        NSUInteger snapshot=receivedButtons(m);
        record(@{@"source":@"GCMouse",@"type":@"move",@"mouseId":@(mouseId),@"dx":@(dx),@"dy":@(dy),@"buttons":@(snapshot)});
        if(rawMouseMode)dispatch_async(dispatch_get_main_queue(),^{
            if(!bridgeView || bridgeView.bounds.size.width<=0)return;
            if(!hasBridgePoint){bridgePoint=CGPointMake(bridgeView.bounds.size.width*.4,bridgeView.bounds.size.height*.4);hasBridgePoint=YES;}
            // Raw GCMouse Y is positive upward; UIKit/CSS Y is downward.
            // This virtual cursor uses real deltas, not inferred button states.
            bridgePoint.x=fmin(bridgeView.bounds.size.width-1,fmax(0,bridgePoint.x+dx));
            bridgePoint.y=fmin(bridgeView.bounds.size.height-1,fmax(0,bridgePoint.y-dy));
            bridgeButtons=snapshot;
            bridge(@{@"type":@"native-move",@"api":@"GCMouse",@"mouseId":@(mouseId),@"dx":@(dx),@"dy":@(dy),@"coordinateMode":@"relative-api"});
        });
    };
    for(NSDictionary *entry in @[@{@"name":@"left",@"button":input.leftButton?:NSNull.null},@{@"name":@"right",@"button":input.rightButton?:NSNull.null},@{@"name":@"middle",@"button":input.middleButton?:NSNull.null}]) {
        if(entry[@"button"]==NSNull.null)continue;
        GCControllerButtonInput *button=entry[@"button"];
        NSString *name=entry[@"name"];
        if([NSProcessInfo.processInfo.arguments containsObject:@"--direct-buttons"])
            button.preferredSystemGestureState=GCSystemGestureStateDisabled;
        record(@{@"source":@"GCMouse",@"type":@"button-policy",@"mouseId":@(mouseId),@"name":name,@"boundToSystemGesture":@(button.isBoundToSystemGesture),@"preferredSystemGestureState":@(button.preferredSystemGestureState)});
        button.valueChangedHandler=^(GCControllerButtonInput *b,float value,BOOL pressed){
            record(@{@"source":@"diagnostic",@"type":@"button-value",@"mouseId":@(mouseId),@"name":name,@"pressed":@(pressed),@"value":@(value),@"polledButtons":@(buttons(input)),@"profileTimestampRaw":@(input.lastEventTimestamp)});
        };
        button.pressedChangedHandler=^(GCControllerButtonInput *b,float value,BOOL pressed){
            // Use the delivered edge, not a later poll of the device. UIKit can
            // queue callbacks while rendering, so isPressed may already differ.
            NSUInteger bit=[name isEqualToString:@"left"]?1:[name isEqualToString:@"right"]?2:4;
            NSUInteger previous=receivedButtons(input);
            NSUInteger next=pressed?(previous|bit):(previous&~bit);
            @synchronized(buttonStates){buttonStates[[NSValue valueWithNonretainedObject:input]]=@(next);}
            record(@{@"source":@"GCMouse",@"type":@"button",@"mouseId":@(mouseId),@"name":name,@"pressed":@(pressed),@"value":@(value),@"buttons":@(next),@"polledButtons":@(buttons(input)),@"handlerQueue":@"dedicated-serial"});
            // Snapshot each actual edge off the UI queue. Only UIKit/WebKit
            // access is dispatched to main; never re-poll to reconstruct edges.
            dispatch_async(dispatch_get_main_queue(),^{
                bridgeButtons=next;
                bridge(@{@"type":@"native-button",@"api":@"GCMouse",@"mouseId":@(mouseId),@"name":name,@"pressed":@(pressed)});
            });
        };
    }
    input.scroll.valueChangedHandler=^(GCControllerDirectionPad *pad,float x,float y){ record(@{@"source":@"GCMouse",@"type":@"scroll",@"x":@(x),@"y":@(y),@"buttons":@(receivedButtons(input))}); dispatch_async(dispatch_get_main_queue(),^{bridge(@{@"type":@"native-scroll",@"api":@"GCMouse",@"deltaX":@(x),@"deltaY":@(y)});}); };
}
@interface ProbeApplication : UIApplication @end
@implementation ProbeApplication
- (void)sendEvent:(UIEvent *)event {
    NSMutableArray *touches=[NSMutableArray array];
    for(UITouch *touch in event.allTouches) {
        CGPoint p=[touch locationInView:touch.window];
        [touches addObject:@{@"phase":@(touch.phase),@"touchType":@(touch.type),@"x":@(p.x),@"y":@(p.y),@"timestamp":@(touch.timestamp)}];
    }
    if(touches.count || event.buttonMask)record(@{@"source":@"UIKit",@"type":@"event",@"eventType":@(event.type),@"buttons":@(event.buttonMask),@"timestamp":@(event.timestamp),@"touches":touches});
    for(UITouch *touch in event.allTouches)if(!rawMouseMode && touch.type==UITouchTypeIndirectPointer && bridgeView){
        CGPoint p=[touch locationInView:bridgeView];
        if(!hasBridgePoint || !CGPointEqualToPoint(p,bridgePoint)){
            bridgePoint=p; hasBridgePoint=YES;
            bridge(@{@"type":@"native-move",@"api":@"UIKit",@"nativeTimestamp":@(event.timestamp)});
        }
    }
    [super sendEvent:event];
}
@end
@interface ProbeController : UIViewController @end
@implementation ProbeController
- (BOOL)prefersPointerLocked{return [NSProcessInfo.processInfo.arguments containsObject:@"--pointer-lock"];}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self setNeedsUpdateOfPrefersPointerLocked];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UIPointerLockState *state=self.view.window.windowScene.pointerLockState;
        record(@{@"source":@"app",@"type":@"pointer-lock",@"requested":@(self.prefersPointerLocked),@"stateAvailable":@(state!=nil),@"locked":@(state.isLocked)});
    });
}
- (void)viewDidLoad {
    [super viewDidLoad];
    WKWebView *web=[[WKWebView alloc] initWithFrame:CGRectZero];
    bridgeView=web;
    // Match UIKit-local and CSS viewport coordinates. Automatic scroll insets
    // previously added the status-bar height (32/62 points in captured runs).
    web.translatesAutoresizingMaskIntoConstraints=NO;
    web.scrollView.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:web];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[web.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [web.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [web.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [web.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]]];
    NSString *kind=UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad?@"ipad":@"iphone";
    NSString *phase=self.prefersPointerLocked?@"locked":@"native";
    NSArray *args=NSProcessInfo.processInfo.arguments;NSUInteger arg=[args indexOfObject:@"--probe-phase"];
    if(arg!=NSNotFound && arg+1<args.count)phase=args[arg+1];
    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:8765/?device=%@-%@",kind,phase]]]];
    record(@{@"source":@"app",@"type":@"ready",@"device":kind,@"systemVersion":UIDevice.currentDevice.systemVersion,@"mouseCount":@(GCMouse.mice.count),@"assistiveTouch":@(UIAccessibilityIsAssistiveTouchRunning())});
    // Read-only lifecycle diagnostics. These records never generate input.
    [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityAssistiveTouchStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        record(@{@"source":@"app",@"type":@"assistive-touch-change",@"running":@(UIAccessibilityIsAssistiveTouchRunning())});
    }];
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){
        record(@{@"source":@"app",@"type":@"lifecycle-sample",@"assistiveTouch":@(UIAccessibilityIsAssistiveTouchRunning()),@"mouseCount":@(GCMouse.mice.count),@"applicationState":@(UIApplication.sharedApplication.applicationState)});
    }];
    for(GCMouse *mouse in GCMouse.mice)observeMouse(mouse);
    // 50 Hz samples are diagnostic observations, never missing-edge repairs.
    [NSTimer scheduledTimerWithTimeInterval:.02 repeats:YES block:^(NSTimer *timer){
        for(GCMouse *mouse in GCMouse.mice){
            NSNumber *identity=identityForMouse(mouse);GCMouseInput *input=mouse.mouseInput;
            dispatch_async(mouseQueue,^{
                NSNumber *mask=@(buttons(input));
                if(![sampledMasks[identity] isEqual:mask]){
                    sampledMasks[identity]=mask;
                    record(@{@"source":@"diagnostic",@"type":@"sample-change",@"mouseId":identity,@"polledButtons":mask,@"profileTimestampRaw":@(input.lastEventTimestamp),@"notAnInputEvent":@YES});
                }
            });
        }
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ observeMouse(n.object); }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        record(@{@"source":@"GCMouse",@"type":@"disconnected",@"identity":[NSString stringWithFormat:@"%p",n.object],@"mouseCount":@(GCMouse.mice.count)});
        GCMouse *mouse=n.object;
        // A disconnected object may be reported again on reconnect. Retaining
        // it in observedMice previously prevented reinstallation of handlers.
        // Dispose subscriptions, never fabricate missing button-up events.
        GCMouseInput *input=mouse.mouseInput;
        input.mouseMovedHandler=nil;
        input.leftButton.pressedChangedHandler=nil;
        input.rightButton.pressedChangedHandler=nil;
        input.middleButton.pressedChangedHandler=nil;
        input.leftButton.valueChangedHandler=nil;
        input.rightButton.valueChangedHandler=nil;
        input.middleButton.valueChangedHandler=nil;
        input.valueDidChangeHandler=nil;
        input.scroll.valueChangedHandler=nil;
        [observedMice removeObject:mouse];
        @synchronized(buttonStates){[buttonStates removeObjectForKey:[NSValue valueWithNonretainedObject:input]];}
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidBecomeCurrentNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ observeMouse(n.object); }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidStopBeingCurrentNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){record(@{@"source":@"diagnostic",@"type":@"not-current",@"mouseId":identityForMouse(n.object)});}];
}
@end
@interface ProbeScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[ProbeController new];
    [self.window makeKeyAndVisible];
}
@end
@interface ProbeDelegate : UIResponder <UIApplicationDelegate> @end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    rawMouseMode=[NSProcessInfo.processInfo.arguments containsObject:@"--raw-mouse"];
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"native-events.jsonl"];
    [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    logFile=[NSFileHandle fileHandleForWritingAtPath:path]; observedMice=[NSMutableSet set]; buttonStates=[NSMutableDictionary dictionary];
    mouseIdentities=[NSMapTable strongToStrongObjectsMapTable];sampledMasks=[NSMutableDictionary dictionary];
    logQueue=dispatch_queue_create("org.jwprobe.mouse-log",DISPATCH_QUEUE_SERIAL);
    mouseQueue=dispatch_queue_create("org.jwprobe.mouse-input",DISPATCH_QUEUE_SERIAL);
    // SDL's UIKit backend uses the same dedicated serial HIGH-priority target.
    // https://github.com/libsdl-org/SDL/blob/main/src/video/uikit/SDL_uikitevents.m
    dispatch_set_target_queue(mouseQueue,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0));
    record(@{@"source":@"app",@"type":@"logging-policy",@"mouseQueue":@"serial-high",@"logQueue":@"separate-serial",@"timestamp":@"callback-entry"});
    return YES;
}
- (void)applicationWillTerminate:(UIApplication *)application {
    dispatch_sync(logQueue,^{[logFile synchronizeFile];});
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,NSStringFromClass(ProbeApplication.class),NSStringFromClass(ProbeDelegate.class)); } }

