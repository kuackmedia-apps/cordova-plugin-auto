import Foundation
import CarPlay
import MediaPlayer

@objc(CDVCarPlayManager)
class CDVCarPlayManager: NSObject, CPTemplateApplicationSceneDelegate {
    private weak var plugin: CDVAutoMusicPlugin?

    @objc var musicPlayer: CDVMusicPlayer!
    @objc var interfaceController: CPInterfaceController?
    @objc private(set) var connected: Bool = false

    @objc init(plugin: CDVAutoMusicPlugin) {
        self.plugin = plugin
        super.init()
        self.musicPlayer = CDVMusicPlayer(manager: self)
    }

    @objc func isConnected() -> Bool { connected }

    // MARK: - CPTemplateApplicationSceneDelegate
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        connected = true
        self.interfaceController = interfaceController
        setupTemplates(interfaceController)
        NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": true])
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        connected = false
        NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": false])
        self.interfaceController = nil
    }

    // MARK: - Templates
    private func setupTemplates(_ controller: CPInterfaceController) {
      let autoNavigation = CDVPlaylistProvider.loadNavigationFromJSON()

        // Basic playlists template
        let playlists = CDVPlaylistProvider.loadPlaylistsFromJSON()
        var items: [CPListItem] = []
        for obj in playlists {
            guard let dict = obj as? [String: Any] else { continue }
            let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Playlist"
            let subtitle = dict["description"] as? String
            let item = CPListItem(text: title, detailText: subtitle)
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                let pid = (dict["id"] as? String) ?? ""
                let tracks = CDVPlaylistProvider.loadTracks(forPlaylist: pid)
                self.musicPlayer.updateQueue(tracks)
                self.musicPlayer.play()
                completion()
            }
            items.append(item)
        }
        let section = CPListSection(items: items)
        let list = CPListTemplate(title: "Playlists", sections: [section])

        // Now Playing template
        let now = CPNowPlayingTemplate.shared
        musicPlayer.setNowPlayingTemplate(now)

        // Tab bar with Library + Now Playing fallback
        controller.setRootTemplate(list, animated: true, completion: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(showNowPlayingTemplate), name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
    }

    @objc private func showNowPlayingTemplate() {
      guard let controller = interfaceController else { return }
      controller.presentTemplate(CPNowPlayingTemplate.shared, animated: true)
    }
}
