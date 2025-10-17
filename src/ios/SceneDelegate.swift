import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        if session.role == .windowApplication {
            // In scene-based apps, the SceneDelegate is responsible for creating the main window.
            if self.window == nil {
                let window = UIWindow(windowScene: windowScene)

                // Check if AppDelegate already has a window (Cordova's default behavior)
                if let appDelegate = UIApplication.shared.delegate,
                let existingWindow = appDelegate.window as? UIWindow,
                existingWindow.rootViewController != nil {
                    print("[SceneDelegate] Using existing window from AppDelegate")
                    self.window = existingWindow
                    existingWindow.windowScene = windowScene
                    return
                }

                // Prefer Cordova's CDVViewController if available
                if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                    window.rootViewController = cdvVCType.init()
                } else if let storyboardName = Bundle.main.object(forInfoDictionaryKey: "UIMainStoryboardFile") as? String,
                          let initialVC = UIStoryboard(name: storyboardName, bundle: nil).instantiateInitialViewController() {
                    // Fallback to app's main storyboard initial view controller
                    window.rootViewController = initialVC
                } else {
                    // Last-resort placeholder to avoid blank screen
                    let vc = UIViewController()
                    vc.view.backgroundColor = .systemBackground
                    let label = UILabel()
                    label.text = "App"
                    label.textAlignment = .center
                    label.translatesAutoresizingMaskIntoConstraints = false
                    vc.view.addSubview(label)
                    NSLayoutConstraint.activate([
                        label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                        label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
                    ])
                    window.rootViewController = vc
                }

                window.makeKeyAndVisible()
                self.window = window
            }
        } else {
            // For secondary scenes (e.g., CarPlay), show a simple placeholder unless handled elsewhere
            let window = UIWindow(windowScene: windowScene)
            let vc = UIViewController()
            vc.view.backgroundColor = .black
            window.rootViewController = vc
            window.makeKeyAndVisible()
            self.window = window
        }

        // Optionally handle URL contexts
        if let urlContext = connectionOptions.urlContexts.first {
            print("SceneDelegate URL: \(urlContext.url)")
        }
    }
}
