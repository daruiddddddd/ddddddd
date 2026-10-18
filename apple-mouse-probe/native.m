// Independent diagnostic: public UIKit / GameController API and WKWebView.
// No synthetic DOM events, no inferred releases, no product drawings.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <WebKit/WebKit.h>

static NSFileHandle *logFile;
static NSMutableSet<GCMouse *> *observedMice;
static NSMutableDictionary<NSValue *,NSNumber *> *buttonStates;
static dispatch_queue_t mouseQueue;
static WKWebView *bridgeView;
static CGPoint bridgePoint;
static BOOL hasBridgePoint=NO;
static NSUInteger bridgeButtons=0;
static void record(NSDictionary *data) {
    NSMutableDictionary *row=[data mutableCopy];
    row[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
    row[@"wall"]=@(NSDate.date.timeIntervalSince1970);
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    @synchronized(logFile) { [logFile writeData:bytes]; [logFile writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]]; }
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
static void observeMouse(GCMouse *mouse) {
    if(!mouse || [observedMice containsObject:mouse])return;
    [observedMice addObject:mouse]; mouse.handlerQueue=mouseQueue;
    NSUInteger mouseId=observedMice.count;
    record(@{@"source":@"GCMouse",@"type":@"connected",@"mouseId":@(mouseId),@"category":mouse.productCategory?:@"",@"vendor":mouse.vendorName?:@""});
    GCMouseInput *input=mouse.mouseInput;
    @synchronized(buttonStates){buttonStates[[NSValue valueWithNonretainedObject:input]]=@(buttons(input));}
    input.mouseMovedHandler=^(GCMouseInput *m,float dx,float dy){ record(@{@"source":@"GCMouse",@"type":@"move",@"mouseId":@(mouseId),@"dx":@(dx),@"dy":@(dy),@"buttons":@(receivedButtons(m))}); };
    for(NSDictionary *entry in @[@{@"name":@"left",@"button":input.leftButton?:NSNull.null},@{@"name":@"right",@"button":input.rightButton?:NSNull.null},@{@"name":@"middle",@"button":input.middleButton?:NSNull.null}]) {
        if(entry[@"button"]==NSNull.null)continue;
        GCControllerButtonInput *button=entry[@"button"];
        NSString *name=entry[@"name"];
        if([NSProcessInfo.processInfo.arguments containsObject:@"--direct-buttons"])
            button.preferredSystemGestureState=GCSystemGestureStateDisabled;
        record(@{@"source":@"GCMouse",@"type":@"button-policy",@"mouseId":@(mouseId),@"name":name,@"boundToSystemGesture":@(button.isBoundToSystemGesture),@"preferredSystemGestureState":@(button.preferredSystemGestureState)});
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
    for(UITouch *touch in event.allTouches)if(touch.type==UITouchTypeIndirectPointer && bridgeView){
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
    for(GCMouse *mouse in GCMouse.mice)observeMouse(mouse);
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ observeMouse(n.object); }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidBecomeCurrentNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ observeMouse(n.object); }];
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
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"native-events.jsonl"];
    [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    logFile=[NSFileHandle fileHandleForWritingAtPath:path]; observedMice=[NSMutableSet set]; buttonStates=[NSMutableDictionary dictionary];
    mouseQueue=dispatch_queue_create("org.jwprobe.mouse-input",DISPATCH_QUEUE_SERIAL);
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,NSStringFromClass(ProbeApplication.class),NSStringFromClass(ProbeDelegate.class)); } }
