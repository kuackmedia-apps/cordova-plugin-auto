import UIKit
import CarPlay

@objc(CDVCarPlaySceneDelegate)
class CDVCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    @objc var carPlayScene: CPTemplateApplicationScene?
    
    override init() {
        super.init()
        print("[CarPlay][SceneDelegate] init")
    }

    deinit {
        print("[CarPlay][SceneDelegate] deinit - scene being deallocated")
        // Post disconnect notification when scene is deallocated
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            print("[CarPlay][SceneDelegate] deinit - notifying manager of disconnect")
            NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": false])
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        print("[CarPlay][SceneDelegate] didConnect invoked")
        self.carPlayScene = templateApplicationScene
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            print("[CarPlay][SceneDelegate] forwarding didConnect to manager")
            manager.templateApplicationScene(templateApplicationScene, didConnect: interfaceController)
        } else {
            print("[CarPlay][SceneDelegate] plugin/manager unavailable, presenting fallback list template")
            // Fallback: show a simple template so CarPlay UI isn't blank
            let item = CPListItem(text: "Sample Song", detailText: "Sample Artist")
            let section = CPListSection(items: [item])
            let list = CPListTemplate(title: "Music", sections: [section])
            DispatchQueue.main.async {
                interfaceController.setRootTemplate(list, animated: true) { success, error in
                    if let error = error { print("[CarPlay][SceneDelegate] setRootTemplate fallback error: \(error)") }
                    else { print("[CarPlay][SceneDelegate] setRootTemplate fallback success: \(success)") }
                }
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        print("[CarPlay][SceneDelegate] didDisconnect invoked")
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            print("[CarPlay][SceneDelegate] forwarding didDisconnect to manager")
            manager.templateApplicationScene(templateApplicationScene, didDisconnect: interfaceController)
        }
        self.carPlayScene = nil
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneWillResignActive - CarPlay going inactive")
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneDidEnterBackground - CarPlay entered background")
        // Post disconnect notification when scene enters background
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            print("[CarPlay][SceneDelegate] sceneDidEnterBackground - notifying manager of disconnect")
            NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": false])
        }
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneWillEnterForeground - CarPlay entering foreground")
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneDidBecomeActive - CarPlay became active")
    }
}

