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
        // NOTE: Do NOT send disconnect notification here.
        // Real disconnection is reliably handled by:
        // 1. templateApplicationScene(_:didDisconnect:) - CPTemplateApplicationSceneDelegate protocol
        // 2. UIScene.didDisconnectNotification - observed by CDVCarPlayManager
        // Sending notification here would cause false disconnects if iOS recreates the SceneDelegate.
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
        print("[CarPlay][SceneDelegate] sceneDidEnterBackground - CarPlay scene in background (another app in foreground)")
        // NOTE: Do NOT send disconnect notification here!
        // sceneDidEnterBackground is called when user switches to another app in CarPlay (Maps, Messages, etc.)
        // but CarPlay is still connected and music continues playing.
        // Real disconnection is handled by didDisconnect() and UIScene.didDisconnectNotification
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneWillEnterForeground - CarPlay entering foreground")
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        print("[CarPlay][SceneDelegate] sceneDidBecomeActive - CarPlay became active")
    }
}

