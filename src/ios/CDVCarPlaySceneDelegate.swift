import UIKit
import CarPlay

@objc(CDVCarPlaySceneDelegate)
class CDVCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    @objc var carPlayScene: CPTemplateApplicationScene?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.carPlayScene = templateApplicationScene
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            manager.templateApplicationScene(templateApplicationScene, didConnect: interfaceController)
        } else {
            // Fallback: show a simple template so CarPlay UI isn't blank
            let item = CPListItem(text: "Sample Song", detailText: "Sample Artist")
            let section = CPListSection(items: [item])
            let list = CPListTemplate(title: "Music", sections: [section])
            interfaceController.setRootTemplate(list, animated: true, completion: nil)
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        if let plugin = CDVAutoMusicPlugin.sharedInstance(), let manager = plugin.carPlayManager {
            manager.templateApplicationScene(templateApplicationScene, didDisconnect: interfaceController)
        }
        self.carPlayScene = nil
    }
}
