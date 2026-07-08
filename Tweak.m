#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 1. UPDATE THIS: The URL of your control web page once you enable GitHub Pages!
#define CONTROL_PAGE_URL @"https://demiandegoat.github.io/Executor4bovlox/index.html"

// Helper to retrieve or generate a unique persistent UUID for this device
NSString *getDeviceUUID() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [defaults stringForKey:@"TweakDeviceUUID"];
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
        [defaults setObject:uuid forKey:@"TweakDeviceUUID"];
        [defaults synchronize];
    }
    return uuid;
}

// Helper function to find the topmost view controller to present the alert
UIViewController *getTopViewController() {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        }
        if (keyWindow) break;
    }
    if (!keyWindow) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                keyWindow = ((UIWindowScene *)scene).windows.firstObject;
                if (keyWindow) break;
            }
        }
    }
    if (!keyWindow) return nil;
    
    UIViewController *topController = keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

// WebSocket Manager
@interface WebSocketManager : NSObject <NSURLSessionWebSocketDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocketTask;
+ (instancetype)sharedInstance;
- (void)connect;
@end

@implementation WebSocketManager

+ (instancetype)sharedInstance {
    static WebSocketManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)connect {
    // Generate a unique WebSocket link isolated by this device's UUID
    NSString *uuid = getDeviceUUID();
    NSString *wsUrlStr = [NSString stringWithFormat:@"wss://demo.piesocket.com/v3/%@?api_key=VCbEZAFZmbes97v2A51T9scMy9KiwT5v2eIYFrba", uuid];
    
    NSURL *url = [NSURL URLWithString:wsUrlStr];
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:nil];
    self.webSocketTask = [self.session webSocketTaskWithURL:url];
    [self.webSocketTask resume];
    [self listenForMessages];
}

- (void)listenForMessages {
    __weak typeof(self) weakSelf = self;
    [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
            // Auto-reconnect after 5 seconds if connection drops
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf connect];
            });
            return;
        }
        if (message) {
            NSString *text = nil;
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                text = message.string;
            } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
                text = [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
            }
            
            if (text) {
                [weakSelf showAlertWithMessage:text];
            }
        }
        [weakSelf listenForMessages];
    }];
}

- (void)showAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (topVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Control Panel Event"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                               style:UIAlertActionStyleDefault
                                                             handler:nil];
            [alert addAction:okAction];
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    // Isolated connection established successfully
}

@end

#pragma mark - Constructor Entry Point

__attribute__((constructor)) static void init() {
    if (NSClassFromString(@"UIApplication") != nil) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification * _Nonnull note) {
            // 1. Establish background listen socket on the device's unique room ID
            [[WebSocketManager sharedInstance] connect];
            
            // 2. Open Safari automatically, passing the device UUID as a query parameter
            NSString *uuid = getDeviceUUID();
            NSString *safariUrlStr = [NSString stringWithFormat:@"%@?id=%@", CONTROL_PAGE_URL, uuid];
            
            NSURL *controlURL = [NSURL URLWithString:safariUrlStr];
            if ([[UIApplication sharedApplication] canOpenURL:controlURL]) {
                [[UIApplication sharedApplication] openURL:controlURL options:@{} completionHandler:nil];
            }
        }];
    }
}
