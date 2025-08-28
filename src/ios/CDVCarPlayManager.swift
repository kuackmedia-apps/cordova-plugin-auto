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
        print("[CarPlay] didConnect: interfaceController received")
        connected = true
        self.interfaceController = interfaceController
        setupTemplates(interfaceController)
        NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": true])
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        print("[CarPlay] didDisconnect")
        connected = false
        NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": false])
        self.interfaceController = nil
    }

    // MARK: - Templates
    private func setupTemplates(_ controller: CPInterfaceController) {
      print("[CarPlay] setupTemplates: begin")
      let autoNavigation = CDVPlaylistProvider.loadNavigationFromJSON()
      print("[CarPlay] setupTemplates: AUTO_NAVIGATION sections count=\(autoNavigation.count)")
      if let first = autoNavigation.first {
          print("[CarPlay] setupTemplates: first section keys=\(Array(first.keys))")
          if let text = first["text"] as? String { print("[CarPlay] setupTemplates: first section text=\(text)") }
          if let items = first["items"] as? [[String: Any]] { print("[CarPlay] setupTemplates: first section items count=\(items.count)") }
      } else {
          print("[CarPlay] setupTemplates: AUTO_NAVIGATION is empty")
      }

        // Basic playlists template
        let playlists = CDVPlaylistProvider.loadPlaylistsFromJSON()
        print("[CarPlay] setupTemplates: playlists loaded count=\(playlists.count)")
        var items: [CPListItem] = []
        for obj in playlists {
            guard let dict = obj as? [String: Any] else { continue }
            let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Playlist"
            let subtitle = dict["description"] as? String
            let item = CPListItem(text: title, detailText: subtitle)
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                let pid = (dict["id"] as? String) ?? ""
                print("[CarPlay] list item selected: pid=\(pid) title=\(title)")
                let tracks = CDVPlaylistProvider.loadTracks(forPlaylist: pid)
                print("[CarPlay] tracks loaded for pid=\(pid) count=\(tracks.count)")
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
        if items.isEmpty {
            print("[CarPlay] setupTemplates: no playlist items, presenting empty Playlists list")
        } else {
            print("[CarPlay] setupTemplates: presenting Playlists with items count=\(items.count)")
        }
        DispatchQueue.main.async {
            print("[CarPlay] setupTemplates: setRootTemplate Playlists")
            controller.setRootTemplate(list, animated: true, completion: { success, error in
                if let error = error { print("[CarPlay] setRootTemplate error: \(error)") }
                else { print("[CarPlay] setRootTemplate success: \(success)") }
            })
        }

        NotificationCenter.default.addObserver(self, selector: #selector(showNowPlayingTemplate), name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        print("[CarPlay] setupTemplates: end")
    }

    @objc private func showNowPlayingTemplate() {
      guard let controller = interfaceController else {
        print("[CarPlay] showNowPlayingTemplate: interfaceController nil")
        return
      }
      print("[CarPlay] showNowPlayingTemplate: presenting")
      DispatchQueue.main.async {
        controller.presentTemplate(CPNowPlayingTemplate.shared, animated: true)
      }
    }
}

