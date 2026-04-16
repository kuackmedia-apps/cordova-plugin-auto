import UIKit
import Intents

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Handle any Siri intents that launched this scene
        if let userActivity = connectionOptions.userActivities.first {
            handleSiriUserActivity(userActivity)
        }
        // Handle URL schemes on cold start
        if !connectionOptions.urlContexts.isEmpty {
            handleURLContexts(connectionOptions.urlContexts)
        }
        guard let windowScene = scene as? UIWindowScene else { return }

        if session.role == .windowApplication {
            // PRIORITY 1: Always try to reuse AppDelegate's window first
            // This ensures Cordova plugins (like StatusBar) work correctly
            // because they reference the same viewController
            if let appDelegate = UIApplication.shared.delegate,
               let existingWindow = appDelegate.window as? UIWindow {

                // Case A: Window exists with a valid rootViewController
                if existingWindow.rootViewController != nil {
                    existingWindow.windowScene = windowScene
                    self.window = existingWindow
                    existingWindow.makeKeyAndVisible()
                    return
                }

                // Case B: Window exists but no rootViewController yet
                // This can happen during cold launch from CarPlay
                existingWindow.windowScene = windowScene
                self.window = existingWindow

                // Create MainViewController (same as AppDelegate uses)
                if let mainVCType = NSClassFromString("MainViewController") as? UIViewController.Type {
                    existingWindow.rootViewController = mainVCType.init()
                } else if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                    existingWindow.rootViewController = cdvVCType.init()
                }

                existingWindow.makeKeyAndVisible()
                return
            }

            // PRIORITY 2: No AppDelegate window exists - create new one
            // This should rarely happen, but handle it safely
            guard self.window == nil else {
                return
            }

            let window = UIWindow(windowScene: windowScene)

            // Use MainViewController (same as AppDelegate) to ensure plugin compatibility
            if let mainVCType = NSClassFromString("MainViewController") as? UIViewController.Type {
                window.rootViewController = mainVCType.init()
            } else if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                window.rootViewController = cdvVCType.init()
            } else if let storyboardName = Bundle.main.object(forInfoDictionaryKey: "UIMainStoryboardFile") as? String,
                      let initialVC = UIStoryboard(name: storyboardName, bundle: nil).instantiateInitialViewController() {
                window.rootViewController = initialVC
            } else {
                // Last-resort placeholder to avoid blank screen
                print("[SceneDelegate] WARNING: Using placeholder view controller")
                let vc = UIViewController()
                vc.view.backgroundColor = .systemBackground
                window.rootViewController = vc
            }

            window.makeKeyAndVisible()
            self.window = window

        }
    }

    // MARK: - URL Scheme Handling

    /// Called when a URL scheme opens the app while the scene is already connected (warm start)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleURLContexts(URLContexts)
    }

    /// Forward URL contexts to Cordova's notification system so CDVHandleOpenURL calls JavaScript's handleOpenURL()
    private func handleURLContexts(_ urlContexts: Set<UIOpenURLContext>) {
        guard let urlContext = urlContexts.first else { return }
        let url = urlContext.url

        NotificationCenter.default.post(
            name: NSNotification.Name("CDVPluginHandleOpenURLNotification"),
            object: url
        )

        let openURLData = NSMutableDictionary()
        openURLData["url"] = url
        if let sourceApplication = urlContext.options.sourceApplication {
            openURLData["sourceApplication"] = sourceApplication
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification"),
            object: openURLData
        )
    }

    // MARK: - Siri Intent Handling

    /// Called when Siri triggers a user activity while the scene is active
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleSiriUserActivity(userActivity)
    }

    /// Handle Siri user activity and forward to the plugin
    private func handleSiriUserActivity(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "INPlayMediaIntent" {
            // Forward to plugin - may need to wait for plugin to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                    plugin.handleSiriIntent(userActivity: userActivity)
                } else {
                    // Store the activity to process when plugin is ready
                    NotificationCenter.default.post(
                        name: Notification.Name("CDVPendingSiriIntent"),
                        object: userActivity
                    )
                }
            }
        }
    }
}
