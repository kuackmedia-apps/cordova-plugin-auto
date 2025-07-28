#import "CDVCarPlaySceneDelegate.h"
#import <CarPlay/CarPlay.h> // Ensure CarPlay framework is explicitly imported
#import <Cordova/CDVViewController.h>
#import "CDVAutoMusicPlugin.h" // For the notification constant

@implementation CDVCarPlaySceneDelegate {
    CPInterfaceController *storedInterfaceController;
    __weak CDVViewController *mainAppViewController; // Use weak to avoid retain cycles if VCs hold delegates
    __weak CDVAutoMusicPlugin *autoMusicPlugin;
    BOOL carPlayConnectionAttempted;
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didConnectInterfaceController:(CPInterfaceController *)interfaceController {
    NSLog(@"CDVCarPlaySceneDelegate: ---> templateApplicationScene:didConnectInterfaceController: called");
    
    // Store these for later use if needed (e.g. if we need to set up templates after finding the plugin)
    self.carPlayScene = templateApplicationScene;
    storedInterfaceController = interfaceController;
    
    NSLog(@"CDVCarPlaySceneDelegate: carPlayScene property set: %@, storedInterfaceController: %@", self.carPlayScene, storedInterfaceController);
    
    // Attempt to set up the CarPlay connection
    NSLog(@"CDVCarPlaySceneDelegate: Attempting CarPlay connection setup...");
    [self attemptCarPlayConnectionSetup];
    
    // Safety measure: Always display a fallback template after a short delay if the normal flow hasn't succeeded
    // This ensures we never show a grey screen
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!storedInterfaceController.rootTemplate) {
            NSLog(@"CDVCarPlaySceneDelegate WARNING: No root template set after 1 second. Applying fallback template.");
            CPListTemplate *fallbackTemplate = [self createFallbackTemplate];
            [storedInterfaceController setRootTemplate:fallbackTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
                if (error) {
                    NSLog(@"CDVCarPlaySceneDelegate ERROR: Failed to set safety fallback template: %@", error);
                } else {
                    NSLog(@"CDVCarPlaySceneDelegate: Safety fallback template set: %@", success ? @"SUCCESS" : @"FAILURE");
                }
            }];
        }
    });
    
    NSLog(@"CDVCarPlaySceneDelegate: <--- templateApplicationScene:didConnectInterfaceController: finished (setup might be deferred)");
}

- (void)attemptCarPlayConnectionSetup {
    if (carPlayConnectionAttempted && autoMusicPlugin && autoMusicPlugin.carPlayManager && [autoMusicPlugin.carPlayManager isConnected]) {
        NSLog(@"CDVCarPlaySceneDelegate: CarPlay connection already established and attempted. Skipping.");
        return;
    }
    
    // Prevent re-entry for the same connection attempt, but allow re-attempts if called externally later
    // carPlayConnectionAttempted = YES; // This will be set once a definitive action (connect or wait) is taken

    NSLog(@"CDVCarPlaySceneDelegate: Attempting CarPlay connection setup...");

    // Try to get the plugin via the new shared instance method first
    CDVAutoMusicPlugin *sharedPlugin = [CDVAutoMusicPlugin sharedInstance];
    if (sharedPlugin && sharedPlugin.viewController) {
        NSString *viewControllerClassName = NSStringFromClass([sharedPlugin.viewController class]);
        NSLog(@"CDVCarPlaySceneDelegate: Found viewController class: %@", viewControllerClassName);
        
        if ([sharedPlugin.viewController isKindOfClass:[CDVViewController class]]) {
            NSLog(@"CDVCarPlaySceneDelegate: Found CDVViewController from shared instance.");
            mainAppViewController = (CDVViewController *)sharedPlugin.viewController;
            autoMusicPlugin = sharedPlugin;
            NSLog(@"CDVCarPlaySceneDelegate: Successfully obtained mainAppViewController and autoMusicPlugin from shared instance.");
            carPlayConnectionAttempted = YES;
            [self proceedWithCarPlayConnection];
            return;
        } else if ([viewControllerClassName containsString:@"CAPBridge"] || 
                  [viewControllerClassName containsString:@"Capacitor"]) {
            // Capacitor view controller detected
            NSLog(@"CDVCarPlaySceneDelegate: Found Capacitor controller: %@. Using it directly.", sharedPlugin.viewController);
            mainAppViewController = sharedPlugin.viewController;
            autoMusicPlugin = sharedPlugin;
            NSLog(@"CDVCarPlaySceneDelegate: Set mainAppViewController to Capacitor controller and autoMusicPlugin.");
            carPlayConnectionAttempted = YES;
            [self proceedWithCarPlayConnection];
            return;
        } else {
            NSLog(@"CDVCarPlaySceneDelegate: Shared plugin's viewController is neither CDVViewController nor Capacitor: %@", sharedPlugin.viewController);
        }
    } else {
        NSLog(@"CDVCarPlaySceneDelegate: Shared plugin not available or its viewController is nil. Falling back.");
    }
    mainAppViewController = nil; // Reset to ensure fallback logic engages fully
    autoMusicPlugin = nil;
    // Fallback: Try finding VC and then wait for notification if needed.
    NSLog(@"CDVCarPlaySceneDelegate: Trying to find CDVViewController via scene iteration...");
    mainAppViewController = [self findMainAppCDVViewController];

    if (mainAppViewController) {
        NSLog(@"CDVCarPlaySceneDelegate: Found mainAppViewController via scene iteration: %@", mainAppViewController);
        autoMusicPlugin = (CDVAutoMusicPlugin *)[mainAppViewController getCommandInstance:@"AutoMusicPlugin"];

        if (autoMusicPlugin && autoMusicPlugin.viewController) { // autoMusicPlugin.viewController confirms plugin is fully initialized by Cordova
            NSLog(@"CDVCarPlaySceneDelegate: CDVAutoMusicPlugin instance found via scene iteration and its viewController is set: %@. Proceeding with connection.", autoMusicPlugin);
            carPlayConnectionAttempted = YES;
            [self proceedWithCarPlayConnection];
        } else {
            NSLog(@"CDVCarPlaySceneDelegate: CDVAutoMusicPlugin not ready via scene iteration (plugin: %@). Waiting for CDVViewControllerIsReadyNotification.", autoMusicPlugin);
            carPlayConnectionAttempted = YES;
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(handleViewControllerReady:)
                                                         name:CDVViewControllerIsReadyNotification
                                                       object:nil];
        }
    } else {
        NSLog(@"CDVCarPlaySceneDelegate: mainAppViewController not found via shared instance or scene iteration. Waiting for CDVViewControllerIsReadyNotification.");
        carPlayConnectionAttempted = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                selector:@selector(handleViewControllerReady:)
                                                    name:CDVViewControllerIsReadyNotification
                                                  object:nil];
    }
}

// Method to find the main application's CDVViewController
- (CDVViewController *)findMainAppCDVViewController {
    NSLog(@"CDVCarPlaySceneDelegate: Attempting to find CDVViewController by iterating through connected scenes...");
    CDVViewController *foundVC = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication] && scene.activationState == UISceneActivationStateForegroundActive) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            NSLog(@"CDVCarPlaySceneDelegate: Found active application UIWindowScene: %@", windowScene);
            for (UIWindow *window in windowScene.windows) {
                NSLog(@"CDVCarPlaySceneDelegate: Checking window: %@ in scene: %@", window, windowScene);
                if (window.isKeyWindow || windowScene.windows.count == 1) {
                    UIViewController *potentialRootVC = window.rootViewController;
                    NSLog(@"CDVCarPlaySceneDelegate: Window's rootViewController: %@, Type: %@", potentialRootVC, NSStringFromClass([potentialRootVC class]));

                    if ([potentialRootVC isKindOfClass:[CDVViewController class]]) {
                        // Standard Cordova app structure
                        foundVC = (CDVViewController *)potentialRootVC;
                        NSLog(@"CDVCarPlaySceneDelegate: Found CDVViewController directly as root: %@", foundVC);
                        break; // Found it
                    } else if ([potentialRootVC isKindOfClass:NSClassFromString(@"CAPBridgeViewController")]) {
                        // Capacitor structure: CAPBridgeViewController is the root
                        // Try KVC for 'cordovaViewController' first (Capacitor < 6 or specific setups)
                        @try {
                            id internalCordovaVC = [potentialRootVC valueForKey:@"cordovaViewController"];
                            if (internalCordovaVC && [internalCordovaVC isKindOfClass:[CDVViewController class]]) {
                                foundVC = (CDVViewController *)internalCordovaVC;
                                NSLog(@"CDVCarPlaySceneDelegate: Found CDVViewController via KVC on CAPBridgeViewController: %@", foundVC);
                                break; // Found it
                            }
                        } @catch (NSException *exception) {
                            NSLog(@"CDVCarPlaySceneDelegate: KVC failed for 'cordovaViewController': %@", exception.reason);
                        }
                        // Fallback: Check children of CAPBridgeViewController (Capacitor 6+ often embeds CDVVC as a child)
                        if (!foundVC && potentialRootVC.childViewControllers.count > 0) {
                            NSLog(@"CDVCarPlaySceneDelegate: CAPBridgeViewController (%@) has %lu childViewControllers. Iterating...", potentialRootVC, (unsigned long)potentialRootVC.childViewControllers.count);
                            for (UIViewController *childVC in potentialRootVC.childViewControllers) {
                                if ([childVC isKindOfClass:[CDVViewController class]]) {
                                    foundVC = (CDVViewController *)childVC;
                                    NSLog(@"CDVCarPlaySceneDelegate: Found CDVViewController as child of CAPBridgeViewController: %@", foundVC);
                                    break; // Found it
                                }
                            }
                        }
                        if (foundVC) break; // Break outer loop if found as child
                        // If no CDVViewController found inside, but we have the CAPBridgeVC, that's our target for getCommandInstance
                        // This case is tricky because CAPBridgeVC itself is not a CDVViewController.
                        // For now, if we only find CAPBridgeVC, we let the caller handle it (it might try getCommandInstance on it).
                        // Or, we could consider not returning it if strict CDVViewController is needed.
                        // For this revert, let's stick to finding an actual CDVViewController.
                    }
                } else {
                    NSLog(@"CDVCarPlaySceneDelegate: Skipping window %@ as it's not the key window and there are multiple windows in scene %@", window, windowScene);
                }
            }
            if (foundVC) break; // Break outer loop if found in this scene
        }
    }

    if (!foundVC) {
        NSLog(@"CDVCarPlaySceneDelegate ERROR: CDVViewController not found after checking all active application scenes and their windows.");
    }
    return foundVC;
}

- (void)handleViewControllerReady:(NSNotification *)notification {
    NSLog(@"CDVCarPlaySceneDelegate: Received CDVViewControllerIsReadyNotification.");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:CDVViewControllerIsReadyNotification object:nil];

    // Ensure mainAppViewController and autoMusicPlugin are set from the notification or re-fetched
    // The notification object should be the CDVViewController instance itself
    // The notification object should be the CDVViewController instance itself (or CAPBridgeViewController in practice)
    // And userInfo should contain the plugin instance.
    id vcFromNotification = notification.object;
    if ([vcFromNotification isKindOfClass:[CDVViewController class]]) {
        mainAppViewController = (CDVViewController *)vcFromNotification;
        NSLog(@"CDVCarPlaySceneDelegate: mainAppViewController (CDVViewController) set from notification: %@", mainAppViewController);
    } else if ([vcFromNotification isKindOfClass:NSClassFromString(@"CAPBridgeViewController")]) {
        // If it's a CAPBridgeViewController, we might need to get the plugin differently or use this as the main VC
        // For now, let's assume the plugin post will provide the correct CDVViewController or the plugin itself
        NSLog(@"CDVCarPlaySceneDelegate: Notification object is CAPBridgeViewController: %@. Will rely on plugin from userInfo.", vcFromNotification);
        // We might not set mainAppViewController directly from CAPBridgeVC here if we expect plugin's VC to be the CDVVC.
    }

    // The userInfo should contain the plugin instance
    if (notification.userInfo[@"plugin"] && [notification.userInfo[@"plugin"] isKindOfClass:[CDVAutoMusicPlugin class]]) {
        autoMusicPlugin = notification.userInfo[@"plugin"];
        NSLog(@"CDVCarPlaySceneDelegate: autoMusicPlugin set from notification: %@", autoMusicPlugin);
    }
    
    // If still not set, try to re-fetch (defensive)
    // If mainAppViewController is not set from notification (or was CAPBridgeVC), try to find it or use plugin's VC
    if (!mainAppViewController && autoMusicPlugin && [autoMusicPlugin.viewController isKindOfClass:[CDVViewController class]]) {
        mainAppViewController = (CDVViewController *)autoMusicPlugin.viewController;
        NSLog(@"CDVCarPlaySceneDelegate: Set mainAppViewController from plugin's viewController: %@", mainAppViewController);
    } else if (!mainAppViewController) {
        NSLog(@"CDVCarPlaySceneDelegate: mainAppViewController still nil, trying findMainAppCDVViewController again.");
        mainAppViewController = [self findMainAppCDVViewController];
    }

    // Ensure autoMusicPlugin is set, potentially from mainAppViewController if it was just found
    if (mainAppViewController && !autoMusicPlugin) {
        NSLog(@"CDVCarPlaySceneDelegate: autoMusicPlugin is nil, trying getCommandInstance from mainAppViewController: %@", mainAppViewController);
        autoMusicPlugin = (CDVAutoMusicPlugin *)[mainAppViewController getCommandInstance:@"AutoMusicPlugin"];
    }

    if (mainAppViewController && autoMusicPlugin && autoMusicPlugin.viewController) {
        NSLog(@"CDVCarPlaySceneDelegate: All components ready after notification. Proceeding with CarPlay connection.");
        [self proceedWithCarPlayConnection];
    } else {
        NSLog(@"CDVCarPlaySceneDelegate ERROR: Components not fully ready after notification. mainAppVC: %@, plugin: %@, plugin.VC: %@", mainAppViewController, autoMusicPlugin, autoMusicPlugin.viewController);
    }
}

- (void)proceedWithCarPlayConnection {
    NSLog(@"CDVCarPlaySceneDelegate: proceedWithCarPlayConnection called");
    
    if (!storedInterfaceController) {
        NSLog(@"CDVCarPlaySceneDelegate ERROR: storedInterfaceController is nil in proceedWithCarPlayConnection.");
        return;
    }
    
    if (!autoMusicPlugin) {
        NSLog(@"CDVCarPlaySceneDelegate ERROR: autoMusicPlugin is nil in proceedWithCarPlayConnection. Attempting to re-fetch.");
        
        NSString *viewControllerClassName = NSStringFromClass([mainAppViewController class]);
        if (mainAppViewController) {
            if ([mainAppViewController isKindOfClass:[CDVViewController class]]) {
                // Handle Cordova view controller
                autoMusicPlugin = (CDVAutoMusicPlugin *)[(CDVViewController *)mainAppViewController getCommandInstance:@"AutoMusicPlugin"];
                NSLog(@"CDVCarPlaySceneDelegate: Re-fetched plugin from Cordova view controller");
            } else if ([viewControllerClassName containsString:@"CAPBridge"] || 
                      [viewControllerClassName containsString:@"Capacitor"]) {
                // Handle Capacitor view controller
                NSLog(@"CDVCarPlaySceneDelegate: Found Capacitor view controller, attempting to get plugin");
                autoMusicPlugin = [CDVAutoMusicPlugin sharedInstance];
                
                if (!autoMusicPlugin) {
                    NSLog(@"CDVCarPlaySceneDelegate ERROR: Could not retrieve AutoMusicPlugin from shared instance for Capacitor");
                    // Create a fallback template to show something rather than a grey screen
                    dispatch_async(dispatch_get_main_queue(), ^{
                        CPListTemplate *fallbackTemplate = [self createFallbackTemplate];
                        [storedInterfaceController setRootTemplate:fallbackTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
                            NSLog(@"CDVCarPlaySceneDelegate: Fallback template set due to missing plugin - Success: %@", success ? @"YES" : @"NO");
                        }];
                    });
                    return;
                }
            }
        }
        
        if (!autoMusicPlugin) {
             NSLog(@"CDVCarPlaySceneDelegate ERROR: Failed to re-fetch autoMusicPlugin.");
            return;
        }
    }
    
    // Ensure carPlayManager is created if it doesn't exist
    if (!autoMusicPlugin.carPlayManager) {
        NSLog(@"CDVCarPlaySceneDelegate: carPlayManager is nil, attempting to create it");
        // This should trigger the lazy initialization of carPlayManager in the plugin
        SEL selector = NSSelectorFromString(@"initializeCarPlayManager");
        if ([autoMusicPlugin respondsToSelector:selector]) {
            NSLog(@"CDVCarPlaySceneDelegate: Calling initializeCarPlayManager on plugin");
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [autoMusicPlugin performSelector:selector];
            #pragma clang diagnostic pop
        }
        
        // Check if we now have a carPlayManager
        if (!autoMusicPlugin.carPlayManager) {
            NSLog(@"CDVCarPlaySceneDelegate ERROR: Failed to create carPlayManager");
            return;
        }
    }
    
    NSLog(@"CDVCarPlaySceneDelegate: CarPlayManager instance found: %@. Forwarding connection to manager.", autoMusicPlugin.carPlayManager);
    
    // Ensure we have a valid CarPlay scene
    if (!self.carPlayScene) {
        NSLog(@"CDVCarPlaySceneDelegate ERROR: self.carPlayScene is nil in proceedWithCarPlayConnection.");
        return;
    }
    
    // Forward the connection to the manager
    NSLog(@"CDVCarPlaySceneDelegate: Calling templateApplicationScene:didConnectInterfaceController: on carPlayManager");
    [autoMusicPlugin.carPlayManager templateApplicationScene:self.carPlayScene didConnectInterfaceController:storedInterfaceController];
    
    // Verify the connection was successful
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL isConnected = [autoMusicPlugin.carPlayManager isConnected];
        NSLog(@"CDVCarPlaySceneDelegate: After connection attempt, carPlayManager.isConnected = %@", isConnected ? @"YES" : @"NO");
        
        if (!isConnected) {
            NSLog(@"CDVCarPlaySceneDelegate WARNING: CarPlay connection may have failed. Attempting to set root template directly.");
            // As a fallback, try to set a simple template if the connection failed
            CPListTemplate *fallbackTemplate = [self createFallbackTemplate];
            [storedInterfaceController setRootTemplate:fallbackTemplate animated:YES completion:^(BOOL success, NSError * _Nullable error) {
                if (error) {
                    NSLog(@"CDVCarPlaySceneDelegate ERROR: Failed to set fallback template: %@", error);
                } else {
                    NSLog(@"CDVCarPlaySceneDelegate: Fallback template set successfully: %@", success ? @"YES" : @"NO");
                }
            }];
        }
    });
}

- (CPListTemplate *)createFallbackTemplate {
    NSLog(@"CDVCarPlaySceneDelegate: Creating fallback template");
    
    // Create a simple list item
    CPListItem *item = [[CPListItem alloc] initWithText:@"Sample Song" detailText:@"Sample Artist"];
    
    // Create a section with the item
    CPListSection *section = [[CPListSection alloc] initWithItems:@[item]];
    
    // Create the list template
    CPListTemplate *template = [[CPListTemplate alloc] initWithTitle:@"Music" sections:@[section]];
    
    return template;
}

- (void)dealloc {
    NSLog(@"CDVCarPlaySceneDelegate: dealloc called. Removing notification observers.");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene didDisconnectInterfaceController:(CPInterfaceController *)interfaceController {
    // Get the Cordova view controller
    UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    CDVViewController *viewController = nil;
    
    if ([rootViewController isKindOfClass:[CDVViewController class]]) {
        viewController = (CDVViewController *)rootViewController;
    } else if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navController = (UINavigationController *)rootViewController;
        if ([[navController viewControllers] count] > 0 && 
            [[[navController viewControllers] objectAtIndex:0] isKindOfClass:[CDVViewController class]]) {
            viewController = (CDVViewController *)[[navController viewControllers] objectAtIndex:0];
        }
    }
    
    if (viewController) {
        // Get the plugin instance
        CDVAutoMusicPlugin *plugin = (CDVAutoMusicPlugin *)[viewController getCommandInstance:@"AutoMusicPlugin"];
        
        // Forward the disconnection to the plugin's CarPlay manager
        if (plugin && plugin.carPlayManager) {
            [plugin.carPlayManager templateApplicationScene:templateApplicationScene 
                               didDisconnectInterfaceController:interfaceController];
        }
    }
    
    self.carPlayScene = nil;
}

@end
