#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Change these to your preferred URLs
#define WEBSOCKET_URL @"wss://echo.websocket.org"
#define SAFARI_URL @"https://www.apple.com"

// Helper function to find the topmost view controller to present the alert
// FIXED: Completely removed the deprecated 'keyWindow' fallback. iOS 13+ uses scenes natively.
UIViewController *getTopViewController() {
    UIWindow *keyWindow = nil;
    
    // Iterate through connected scenes to find the active UIWindow
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
    
    // Fallback if the app is in the background but we still need a window
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

// WebSocket Manager Interface
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
    NSURL *url = [NSURL URLWithString:WEBSOCKET_URL];
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:nil];
    self.webSocketTask = [self.session webSocketTaskWithURL:url];
    [self.webSocketTask resume];
    [self listenForMessages];
}

// Recursively listen for incoming WebSocket data
- (void)listenForMessages {
    __weak typeof(self) weakSelf = self;
    
    // FIXED ERROR: Corrected Objective-C method name to 'receiveMessageWithCompletionHandler:'
    [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        if (error) {
            // Handle disconnection or socket errors here if needed
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
        [weakSelf listenForMessages]; // Re-register the handler for the next message
    }];
}

// Presents the UIAlertController on the main UI thread
- (void)showAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = getTopViewController();
        if (topVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"WebSocket Message"
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

// Triggers when the connection successfully establishes
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *safariURL = [NSURL URLWithString:SAFARI_URL];
        if ([[UIApplication sharedApplication] canOpenURL:safariURL]) {
            [[UIApplication sharedApplication] openURL:safariURL options:@{} completionHandler:nil];
        }
    });
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    // Optional: handle close events here
}

@end

#pragma mark - Constructor Entry Point

__attribute__((constructor)) static void init() {
    // Safety check to ensure we only load inside application environments
    if (NSClassFromString(@"UIApplication") != nil) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification * _Nonnull note) {
            [[WebSocketManager sharedInstance] connect];
        }];
    }
}
