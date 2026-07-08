#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Your specific GitHub Pages website
#define CONTROL_PAGE_URL @"https://demiandegoat.github.io/Executor4bovlox/index.html"
// Zero API Key required!
#define WEBSOCKET_URL_FORMAT @"wss://ntfy.sh/%@/ws"

// Generate a unique persistent UUID for your specific phone
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

// Helper to find the topmost view controller
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
    NSString *uuid = getDeviceUUID();
    NSString *wsUrlStr = [NSString stringWithFormat:WEBSOCKET_URL_FORMAT, uuid];
    
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
            // Reconnect instantly if Roblox forces the connection closed
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf connect];
            });
            return;
        }
        
        if (message) {
            NSData *jsonData = nil;
            if (message.type == NSURLSessionWebSocketMessageTypeString) {
                jsonData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
            } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
                jsonData = message.data;
            }
            
            // The free server sends JSON. We only want to trigger the UI if it's an actual message event.
            if (jsonData) {
                NSError *jsonError;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
                
                if (!jsonError && [dict isKindOfClass:[NSDictionary class]]) {
                    // Filter out background pings/open events, ONLY show user text
                    if ([dict[@"event"] isEqualToString:@"message"]) {
                        NSString *text = dict[@"message"];
                        if (text && text.length > 0) {
                            [weakSelf showAlertWithMessage:text];
                        }
                    }
                }
            }
        }
        [weakSelf listenForMessages];
    }];
}

- (void)showAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (topVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Executor Panel"
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
    // Socket connected safely
}
@end

#pragma mark - Constructor Entry Point

__attribute__((constructor)) static void init() {
    if (NSClassFromString(@"UIApplication") != nil) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification * _Nonnull note) {
            // 1. Establish the API-less background socket
            [[WebSocketManager sharedInstance] connect];
            
            // 2. Automatically launch your specific Executor4bovlox page
            NSString *uuid = getDeviceUUID();
            NSString *safariUrlStr = [NSString stringWithFormat:@"%@?id=%@", CONTROL_PAGE_URL, uuid];
            
            NSURL *controlURL = [NSURL URLWithString:safariUrlStr];
            if ([[UIApplication sharedApplication] canOpenURL:controlURL]) {
                [[UIApplication sharedApplication] openURL:controlURL options:@{} completionHandler:nil];
            }
        }];
    }
}
