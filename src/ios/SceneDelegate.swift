import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if session.role == .windowApplication {
            print("[SceneDelegate] Main app scene connecting...")

            // PRIORITY 1: Always try to reuse AppDelegate's window first
            // This ensures Cordova plugins (like StatusBar) work correctly
            // because they reference the same viewController
            if let appDelegate = UIApplication.shared.delegate,
               let existingWindow = appDelegate.window as? UIWindow {

                // Case A: Window exists with a valid rootViewController
                if existingWindow.rootViewController != nil {
                    print("[SceneDelegate] Reusing existing AppDelegate window with rootViewController")
                    existingWindow.windowScene = windowScene
                    self.window = existingWindow
                    existingWindow.makeKeyAndVisible()
                    return
                }

                // Case B: Window exists but no rootViewController yet
                // This can happen during cold launch from CarPlay
                print("[SceneDelegate] AppDelegate window exists but no rootViewController, will configure it")
                existingWindow.windowScene = windowScene
                self.window = existingWindow

                // Create MainViewController (same as AppDelegate uses)
                if let mainVCType = NSClassFromString("MainViewController") as? UIViewController.Type {
                    print("[SceneDelegate] Creating MainViewController for existing window")
                    existingWindow.rootViewController = mainVCType.init()
                } else if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                    print("[SceneDelegate] Fallback: Creating CDVViewController for existing window")
                    existingWindow.rootViewController = cdvVCType.init()
                }

                existingWindow.makeKeyAndVisible()
                return
            }

            // PRIORITY 2: No AppDelegate window exists - create new one
            // This should rarely happen, but handle it safely
            guard self.window == nil else {
                print("[SceneDelegate] Window already exists, skipping creation")
                return
            }

            print("[SceneDelegate] No AppDelegate window, creating new window")
            let window = UIWindow(windowScene: windowScene)

            // Use MainViewController (same as AppDelegate) to ensure plugin compatibility
            if let mainVCType = NSClassFromString("MainViewController") as? UIViewController.Type {
                print("[SceneDelegate] Creating MainViewController for new window")
                window.rootViewController = mainVCType.init()
            } else if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                print("[SceneDelegate] Fallback: Creating CDVViewController for new window")
                window.rootViewController = cdvVCType.init()
            } else if let storyboardName = Bundle.main.object(forInfoDictionaryKey: "UIMainStoryboardFile") as? String,
                      let initialVC = UIStoryboard(name: storyboardName, bundle: nil).instantiateInitialViewController() {
                print("[SceneDelegate] Using storyboard initial view controller")
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

        } else {
            // For secondary scenes (e.g., CarPlay), this is handled by CDVCarPlaySceneDelegate
            // Only create a placeholder if absolutely needed
            print("[SceneDelegate] Secondary scene role: \(session.role.rawValue)")
        }

        // Handle URL contexts if present
        if let urlContext = connectionOptions.urlContexts.first {
            print("[SceneDelegate] URL context: \(urlContext.url)")
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print("[SceneDelegate] sceneDidBecomeActive")
        // Ensure status bar appearance is updated when scene becomes active
        // This fixes the status bar not showing when app is opened from CarPlay command center
        guard let vc = window?.rootViewController else { return }

        // Read StatusBar configuration from Cordova settings
        let settings = readCordovaSettings(from: vc)
        let statusBarStyle = (settings["statusbarstyle"] as? String)?.lowercased() ?? "default"
        let statusBarOverlaysWebView = (settings["statusbaroverlayswebview"] as? String)?.lowercased() != "false"
        let statusBarBackgroundColor = settings["statusbarbackgroundcolor"] as? String

        print("[SceneDelegate] StatusBar config: style=\(statusBarStyle), overlays=\(statusBarOverlaysWebView), bgColor=\(statusBarBackgroundColor ?? "nil")")

        // Force sb_hideStatusBar to NO to ensure status bar is visible
        vc.setValue(NSNumber(value: false), forKey: "sb_hideStatusBar")

        // Set status bar style based on config
        // UIStatusBarStyle: 0 = default, 1 = lightContent, 3 = darkContent (iOS 13+)
        let styleValue: Int
        if statusBarStyle == "lightcontent" {
            styleValue = 1 // UIStatusBarStyle.lightContent
        } else if statusBarStyle == "darkcontent" {
            styleValue = 3 // UIStatusBarStyle.darkContent (iOS 13+)
        } else {
            styleValue = 0 // UIStatusBarStyle.default
        }
        vc.setValue(NSNumber(value: styleValue), forKey: "sb_statusBarStyle")

        vc.setNeedsStatusBarAppearanceUpdate()
        print("[SceneDelegate] Applied sb_hideStatusBar=false, sb_statusBarStyle=\(styleValue)")

        // Ensure status bar background view exists with correct color (when overlays=false)
        if !statusBarOverlaysWebView, let bgColorHex = statusBarBackgroundColor {
            ensureStatusBarBackground(for: vc, colorHex: bgColorHex)
        }

        // Notify StatusBar plugin to resize the webview
        NotificationCenter.default.post(name: Notification.Name("CDVViewWillAppearNotification"), object: nil)
        print("[SceneDelegate] Posted CDVViewWillAppearNotification")
    }

    /// Reads Cordova settings from the CDVViewController
    private func readCordovaSettings(from viewController: UIViewController) -> [String: Any] {
        // CDVViewController has a 'settings' property with config.xml preferences
        if let settings = (viewController as? NSObject)?.value(forKey: "settings") as? [String: Any] {
            return settings
        }
        return [:]
    }

    /// Ensures a status bar background view exists with the configured color
    /// This is needed when the app is opened from CarPlay command center and
    /// the StatusBar plugin hasn't had a chance to create its background view
    private func ensureStatusBarBackground(for viewController: UIViewController, colorHex: String) {
        let statusBarTag = 38482 // Unique tag to identify our status bar background

        // Check if we already added the background
        if viewController.view.viewWithTag(statusBarTag) != nil {
            print("[SceneDelegate] Status bar background already exists")
            return
        }

        // Get status bar frame
        let statusBarFrame: CGRect
        if #available(iOS 13.0, *) {
            statusBarFrame = window?.windowScene?.statusBarManager?.statusBarFrame ?? CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
        } else {
            statusBarFrame = UIApplication.shared.statusBarFrame
        }

        // Parse hex color
        let bgColor = colorFromHex(colorHex) ?? .black

        // Create background view
        let backgroundView = UIView(frame: statusBarFrame)
        backgroundView.backgroundColor = bgColor
        backgroundView.tag = statusBarTag
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

        viewController.view.addSubview(backgroundView)
        print("[SceneDelegate] Created status bar background with color \(colorHex)")
    }

    /// Converts a hex color string to UIColor
    private func colorFromHex(_ hex: String) -> UIColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        print("[SceneDelegate] sceneWillEnterForeground")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print("[SceneDelegate] sceneDidEnterBackground")
    }
}
