// Independent diagnostic: public UIKit / GameController API and WKWebView.
// No synthetic DOM events, no inferred releases, no product drawings.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <WebKit/WebKit.h>

static NSFileHandle *logFile;
static NSMutableSet<GCMouse *> *observedMice;
static void record(NSDictionary *data) {
    NSMutableDictionary *row=[data mutableCopy];
    row[@"uptime"]=@(NSProcessInfo.processInfo.systemUptime);
    row[@"wall"]=@(NSDate.date.timeIntervalSince1970);
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    @synchronized(logFile) { [logFile writeData:bytes]; [logFile writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]]; }
}
static NSUInteger buttons(GCMouseInput *input) {
    return (input.leftButton.isPressed?1:0)|(input.rightButton.isPressed?2:0)|(input.middleButton.isPressed?4:0);
}
static void observeMouse(GCMouse *mouse) {
    if(!mouse || [observedMice containsObject:mouse])return;
    [observedMice addObject:mouse]; mouse.handlerQueue=dispatch_get_main_queue();
    record(@{@"source":@"GCMouse",@"type":@"connected",@"category":mouse.productCategory?:@"",@"vendor":mouse.vendorName?:@""});
    GCMouseInput *input=mouse.mouseInput;
    input.mouseMovedHandler=^(GCMouseInput *m,float dx,float dy){ record(@{@"source":@"GCMouse",@"type":@"move",@"dx":@(dx),@"dy":@(dy),@"buttons":@(buttons(m))}); };
    for(NSDictionary *entry in @[@{@"name":@"left",@"button":input.leftButton?:NSNull.null},@{@"name":@"right",@"button":input.rightButton?:NSNull.null},@{@"name":@"middle",@"button":input.middleButton?:NSNull.null}]) {
        if(entry[@"button"]==NSNull.null)continue;
        GCControllerButtonInput *button=entry[@"button"];
        NSString *name=entry[@"name"];
        button.pressedChangedHandler=^(GCControllerButtonInput *b,float value,BOOL pressed){ record(@{@"source":@"GCMouse",@"type":@"button",@"name":name,@"pressed":@(pressed),@"value":@(value),@"buttons":@(buttons(input))}); };
    }
    input.scroll.valueChangedHandler=^(GCControllerDirectionPad *pad,float x,float y){ record(@{@"source":@"GCMouse",@"type":@"scroll",@"x":@(x),@"y":@(y),@"buttons":@(buttons(input))}); };
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
    [super sendEvent:event];
}
@end
@interface ProbeController : UIViewController @end
@implementation ProbeController
- (void)viewDidLoad {
    [super viewDidLoad];
    WKWebView *web=[[WKWebView alloc] initWithFrame:self.view.bounds];
    web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:web];
    NSString *kind=UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad?@"ipad":@"iphone";
    [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:8765/?device=%@-native",kind]]]];
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
    logFile=[NSFileHandle fileHandleForWritingAtPath:path]; observedMice=[NSMutableSet set];
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,NSStringFromClass(ProbeApplication.class),NSStringFromClass(ProbeDelegate.class)); } }
