import UIKit
import CarPlay
import Intents

@objc(CDVCarPlaySceneDelegate)
class CDVCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    @objc var carPlayScene: CPTemplateApplicationScene?
    
    override init() {
        super.init()
    }

    deinit {
        // NOTE: Do NOT send disconnect notification here.
        // Real disconnection is reliably handled by:
        // 1. templateApplicationScene(_:didDisconnect:) - CPTemplateApplicationSceneDelegate protocol
        // 2. UIScene.didDisconnectNotification - observed by CDVCarPlayManager
        // Sending notification here would cause false disconnects if iOS recreates the SceneDelegate.
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.carPlayScene = templateApplicationScene
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            manager.templateApplicationScene(templateApplicationScene, didConnect: interfaceController)
        } else {
            // Fallback: show a simple template so CarPlay UI isn't blank
            let item = CPListItem(text: "Sample Song", detailText: "Sample Artist")
            let section = CPListSection(items: [item])
            let list = CPListTemplate(title: "Music", sections: [section])
            DispatchQueue.main.async {
                interfaceController.setRootTemplate(list, animated: true) { success, error in
                    if let error = error { print("[CarPlay][SceneDelegate] setRootTemplate fallback error: \(error)") }
                }
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            manager.templateApplicationScene(templateApplicationScene, didDisconnect: interfaceController)
        }
        self.carPlayScene = nil
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // NOTE: Do NOT send disconnect notification here!
        // sceneDidEnterBackground is called when user switches to another app in CarPlay (Maps, Messages, etc.)
        // but CarPlay is still connected and music continues playing.
        // Real disconnection is handled by didDisconnect() and UIScene.didDisconnectNotification
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
    }

    // MARK: - Siri Intent Handling for CarPlay

    /// Called when Siri triggers a user activity while CarPlay scene is active
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleCarPlaySiriIntent(userActivity)
    }

    /// Handle Siri user activity in CarPlay context
    private func handleCarPlaySiriIntent(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "INPlayMediaIntent" {
            if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                plugin.handleSiriIntent(userActivity: userActivity)
            } else {
                print("⚠️ [CarPlay][SceneDelegate] Plugin not available for Siri intent")
            }
        }
    }
}

