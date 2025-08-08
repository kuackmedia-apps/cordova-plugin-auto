#import "SceneDelegate.h"
#import <Cordova/CDVViewController.h>
#import <CarPlay/CarPlay.h>

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    NSString *role = session.role;

    if ([role isEqualToString:UIWindowSceneSessionRoleApplication]) {
        NSLog(@"SceneDelegate: Main application scene connected. Creating window and attaching AppDelegate's root view controller.");
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

        // Use the Cordova AppDelegate's viewController as root
        id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;
        UIViewController *rootVC = nil;
        if ([appDelegate respondsToSelector:@selector(viewController)]) {
            rootVC = [appDelegate performSelector:@selector(viewController)];
        }
        if (!rootVC) {
            // Fallback: try to create a default CDVViewController
            rootVC = [CDVViewController new];
        }
        self.window.rootViewController = rootVC;
        [self.window makeKeyAndVisible];
        return;
    }

    if ([role isEqualToString:CPTemplateApplicationSceneSessionRoleApplication]) {
        // 🚗 CarPlay UI
        NSLog(@"SceneDelegate: CarPlay scene connected");
        // CarPlay UI is handled by CPTemplateApplicationSceneDelegate methods (CDVCarPlaySceneDelegate)
        return;
    }

    // Any other roles are ignored for safety
    NSLog(@"SceneDelegate: Ignoring scene with role: %@", role);
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    NSLog(@"Scene disconnected: %@", scene.session.role);
}

@end
