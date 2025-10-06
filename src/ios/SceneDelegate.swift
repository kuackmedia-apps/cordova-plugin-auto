import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    static var cordovaInitialized = false // Track Cordova initialization

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print("[SceneDelegate] willConnectTo called. session.role: \(session.role.rawValue), window exists: \(self.window != nil), cordovaInitialized: \(SceneDelegate.cordovaInitialized)")
        guard let windowScene = scene as? UIWindowScene else { return }

        // Only initialize Cordova for the main app scene
        if session.role == .windowApplication {
            if self.window == nil && !SceneDelegate.cordovaInitialized {
                print("[SceneDelegate] Creating UIWindow and initializing Cordova for main app scene.")
                let window = UIWindow(windowScene: windowScene)

                // Prefer Cordova's CDVViewController if available
                if let cdvVCType = NSClassFromString("CDVViewController") as? UIViewController.Type {
                    print("[SceneDelegate] Initializing CDVViewController.")
                    window.rootViewController = cdvVCType.init()
                } else if let storyboardName = Bundle.main.object(forInfoDictionaryKey: "UIMainStoryboardFile") as? String,
                          let initialVC = UIStoryboard(name: storyboardName, bundle: nil).instantiateInitialViewController() {
                    print("[SceneDelegate] Initializing storyboard initial view controller.")
                    window.rootViewController = initialVC
                } else {
                    print("[SceneDelegate] Initializing fallback view controller.")
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
                SceneDelegate.cordovaInitialized = true
            } else if self.window != nil {
                print("[SceneDelegate] UIWindow already exists, reusing.")
            } else if SceneDelegate.cordovaInitialized {
                print("[SceneDelegate] Cordova already initialized, skipping.")
            }
        } else {
            // For CarPlay or other secondary scenes, do NOT initialize Cordova
            print("[SceneDelegate] Creating UIWindow for CarPlay/secondary scene (no Cordova).")
            let window = UIWindow(windowScene: windowScene)
            let vc = UIViewController()
            vc.view.backgroundColor = .black
            // Optionally, customize this view for CarPlay
            let label = UILabel()
            label.text = "CarPlay Scene"
            label.textColor = .white
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
            ])
            window.rootViewController = vc
            window.makeKeyAndVisible()
            self.window = window
        }

        // Optionally handle URL contexts
        if let urlContext = connectionOptions.urlContexts.first {
            print("[SceneDelegate] URL: \(urlContext.url)")
        }
    }
}
