import Foundation
import CarPlay
import MediaPlayer
import UIKit

@objc(CDVCarPlayManager)
class CDVCarPlayManager: NSObject, CPTemplateApplicationSceneDelegate {
    private weak var plugin: CDVAutoMusicPlugin?

    @objc var musicPlayer: CDVMusicPlayer!
    @objc var interfaceController: CPInterfaceController?
    @objc private(set) var connected: Bool = false
    private var isNowPlayingShown: Bool = false
    private let listImageCache = NSCache<NSURL, UIImage>()

    @objc init(plugin: CDVAutoMusicPlugin) {
        self.plugin = plugin
        super.init()
        self.musicPlayer = CDVMusicPlayer(manager: self)
    }

    // MARK: - Helpers
    private func setListItemImage(_ li: CPListItem, from urlString: String?) {
        guard let s = urlString, !s.isEmpty, let url = URL(string: s) else {
            if let s = urlString, s.isEmpty { print("[CarPlay][IMG] empty image URL string") }
            else { print("[CarPlay][IMG] no image URL present for list item") }
            return
        }
        let nsurl = url as NSURL
        if let cached = listImageCache.object(forKey: nsurl) {
            print("[CarPlay][IMG] cache hit for list image: \(s) size=\(Int(cached.size.width))x\(Int(cached.size.height)))")
            li.setImage(cached)
            return
        }
        print("[CarPlay][IMG] cache miss, downloading list item image: \(s)")
        URLSession.shared.dataTask(with: url) { [weak self] data, resp, err in
            if let err = err { print("[CarPlay][IMG][ERROR] download failed for: \(s) error=\(err.localizedDescription)"); return }
            guard let self = self, let data = data, let img = UIImage(data: data) else {
                print("[CarPlay][IMG][ERROR] invalid image data for: \(s)")
                return
            }
            print("[CarPlay][IMG] download success bytes=\(data.count) size=\(Int(img.size.width))x\(Int(img.size.height))) url=\(s)")
            self.listImageCache.setObject(img, forKey: nsurl)
            DispatchQueue.main.async { li.setImage(img) }
        }.resume()
    }
    private func makeListItems(from dicts: [[String: Any]], parentTitle: String) -> [CPListItem] {
        var cpItems: [CPListItem] = []
        for d in dicts {
            let name = (d["name"] as? String) ?? (d["title"] as? String) ?? (d["text"] as? String) ?? "Item"
            let subtitle = d["description"] as? String
            let id = String(describing: d["id"] ?? "")
            let mediaType = (d["itemType"] as? String) ?? (d["type"] as? String) // PLAYLIST, ALBUM, ARTIST, TAG
            let childFileName = d["fileName"] as? String
            let inlineItems = d["items"] as? [[String: Any]]
            let li = CPListItem(text: name, detailText: subtitle)
            // Try to attach image if available on item
            let imageUrl = (d["artwork"] as? String) ?? (d["image"] as? String) ?? (d["icon"] as? String)
            if let imageUrl, !imageUrl.isEmpty { print("[CarPlay][IMG] list item has image URL: \(imageUrl)") }
            else { print("[CarPlay][IMG] list item without image URL. keys=\(Array(d.keys)) name=\(name)") }
            setListItemImage(li, from: imageUrl)
            li.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                print("[CarPlay] select item name=\(name) id=\(id) mediaType=\(mediaType ?? "-") fileName=\(childFileName ?? "<nil>") in parent=\(parentTitle)")

                // Drill-down navigation takes precedence if a child file or inline items exist
                if let file = childFileName, !file.isEmpty, let controller = self.interfaceController {
                    let children = CDVPlaylistProvider.loadNavigationChildren(fileName: file)
                    print("[CarPlay][NAV] drill-down file=\(file) children=\(children.count)")
                    let nextItems = self.makeListItems(from: children, parentTitle: name)
                    let section = CPListSection(items: nextItems)
                    let next = CPListTemplate(title: name, sections: [section])
                    DispatchQueue.main.async {
                        self.isNowPlayingShown = false
                        controller.pushTemplate(next, animated: true)
                        completion()
                    }
                    return
                }
                if let items = inlineItems, !items.isEmpty, let controller = self.interfaceController {
                    print("[CarPlay][NAV] drill-down inline items=\(items.count)")
                    let nextItems = self.makeListItems(from: items, parentTitle: name)
                    let section = CPListSection(items: nextItems)
                    let next = CPListTemplate(title: name, sections: [section])
                    DispatchQueue.main.async {
                        self.isNowPlayingShown = false
                        controller.pushTemplate(next, animated: true)
                        completion()
                    }
                    return
                }

                // 1) Try local queue file first
                var tracks = id.isEmpty ? [] : CDVPlaylistProvider.loadTracks(forPlaylist: id)
                // 2) If empty, attempt remote by mediaType
                if tracks.isEmpty, let mediaType = mediaType?.lowercased(), !id.isEmpty {
                    self.fetchTracksRemote(mediaType: mediaType, itemId: id, parentTitle: name) { remote in
                        if !remote.isEmpty { self.musicPlayer.updateQueue(remote); self.musicPlayer.play() }
                    }
                } else if !tracks.isEmpty {
                    self.musicPlayer.updateQueue(tracks); self.musicPlayer.play()
                }
                completion()
            }
            cpItems.append(li)
        }
        return cpItems
    }

    private func fetchTracksRemote(mediaType: String, itemId: String, parentTitle: String, completion: @escaping ([[String: Any]]) -> Void) {
        let api: MusicApi = MusicApiImpl()

        // Helper to resolve signed URLs for a list of Track models
        func resolveSignedUrls(from tracks: [Track], completion: @escaping ([[String: Any]]) -> Void) {
            let group = DispatchGroup()
            var results: [[String: Any]] = []
            for t in tracks {
                group.enter()
                let req = TrackRequest(
                    idAlbumTrack: String(t.idAlbumTrack ?? 0),
                    idTrack: t.id,
                    forceDevice: false,
                    useCloudFront: true,
                    forcePreview: false,
                    extraLife: false
                )
                api.getTrackUrl(trackRequest: req) { res in
                    defer { group.leave() }
                    guard let signed = try? res.get() else { return }
                    // Prefer largest album image URL when possible
                    let artUrl: String? = {
                        guard let images = t.album?.images, !images.isEmpty else { return nil }
                        // If size is provided, choose the max; else fallback to the first URL
                        if let best = images.max(by: { (a, b) in (a.size ?? 0) < (b.size ?? 0) }) { return best.url }
                        return images.first?.url
                    }()
                    let dict: [String: Any] = [
                        "title": t.name,
                        "artist": t.artists.first?.name ?? "",
                        "album": t.album?.title ?? parentTitle,
                        "source": signed.signedUrl,
                        "artwork": artUrl as Any
                    ]
                    results.append(dict)
                }
            }
            group.notify(queue: .main) { completion(results) }
        }

        switch mediaType {
        case "playlist":
            api.getPlayListTracks(playListId: itemId) { result in
                guard let container = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                let tracks = container.tracks.items.map { $0.track }
                print("[CarPlay][remote] playlist id=\(itemId) rawTracks=\(tracks.count)")
                resolveSignedUrls(from: tracks, completion: completion)
            }
        case "album":
            api.getAlbumTracks(albumId: itemId) { result in
                guard let album = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                print("[CarPlay][remote] album id=\(itemId) rawTracks=\(album.tracks.items.count)")
                resolveSignedUrls(from: album.tracks.items, completion: completion)
            }
        case "artist":
            api.getArtistTracks(artistId: itemId) { result in
                guard let artistTracks = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                print("[CarPlay][remote] artist id=\(itemId) rawTracks=\(artistTracks.list.count)")
                resolveSignedUrls(from: artistTracks.list, completion: completion)
            }
        case "tag":
            print("[CarPlay][remote] tag not implemented for track listing")
            DispatchQueue.main.async { completion([]) }
        default:
            print("[CarPlay][remote] unknown mediaType=\(mediaType)")
            DispatchQueue.main.async { completion([]) }
        }
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

        // Build list templates from AUTO_NAVIGATION sections (max 4 to satisfy CarPlay UI guidance)
        var tabTemplates: [CPTemplate] = []
        for (idx, sectionDict) in autoNavigation.enumerated() {
            let sectionTitle = (sectionDict["text"] as? String) ?? "Section \(idx+1)"
            let fileName = (sectionDict["fileName"] as? String) ?? ""
            let explicitItems = sectionDict["items"] as? [[String: Any]]

            var cpSections: [CPListSection] = []

            if !fileName.isEmpty {
                // Load children from referenced file (e.g., RECENT_LISTENED, AUTO_NAVIGATION_LIBRARY, AUTO_NAVIGATION_EXPLORER)
                let children = CDVPlaylistProvider.loadNavigationChildren(fileName: fileName)
                print("[CarPlay] [NAV] fileName=\(fileName) childrenCount=\(children.count)")
                if children.isEmpty { print("[CarPlay][TAB][EMPTY] fileName=\(fileName) produced 0 children") }

                // If this is AUTO_NAVIGATION_LIBRARY, children are sections: [{ text, items: [...] }]
                if fileName == "AUTO_NAVIGATION_LIBRARY", let first = children.first, first["items"] != nil {
                    var topItems: [CPListItem] = []
                    for (sidx, subSection) in children.enumerated() {
                        let subTitle = (subSection["text"] as? String) ?? "Section \(sidx+1)"
                        let subItems = subSection["items"] as? [[String: Any]] ?? []
                        let li = CPListItem(text: subTitle, detailText: "\(subItems.count) items")
                        // Subsections may include a representative image key
                        let subImage = (subSection["artwork"] as? String) ?? (subSection["image"] as? String) ?? (subSection["icon"] as? String)
                        if let subImage, !subImage.isEmpty { print("[CarPlay][IMG] subsection image URL: \(subImage)") }
                        setListItemImage(li, from: subImage)
                        li.handler = { [weak self] _, completion in
                            guard let self, let controller = self.interfaceController else { completion(); return }
                            print("[CarPlay] [NAV][LIB] open subsection title=\(subTitle) items=\(subItems.count)")
                            let leafItems = self.makeListItems(from: subItems, parentTitle: subTitle)
                            let section = CPListSection(items: leafItems)
                            let next = CPListTemplate(title: subTitle, sections: [section])
                            DispatchQueue.main.async {
                                self.isNowPlayingShown = false
                                controller.pushTemplate(next, animated: true)
                                completion()
                            }
                        }
                        topItems.append(li)
                    }
                    cpSections.append(CPListSection(items: topItems))
                } else {
                    // Generic flat list
                    let items = makeListItems(from: children, parentTitle: sectionTitle)
                    if items.isEmpty { print("[CarPlay][TAB][EMPTY] section=\(sectionTitle) (file=\(fileName)) returned 0 list items") }
                    cpSections.append(CPListSection(items: items))
                }
            } else if let sectionItems = explicitItems {
                let items = makeListItems(from: sectionItems, parentTitle: sectionTitle)
                if items.isEmpty { print("[CarPlay][TAB][EMPTY] explicit items section=\(sectionTitle) returned 0 list items") }
                cpSections.append(CPListSection(items: items))
            }

            // Build template if we have any sections
            let safeTitle = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Section \(idx+1)" : sectionTitle
            let cpList = CPListTemplate(title: safeTitle, sections: cpSections)
            cpList.tabTitle = safeTitle
            if #available(iOS 13.0, *) { cpList.tabImage = UIImage(systemName: "music.note.list") }
            let totalItems = cpSections.reduce(0) { $0 + $1.items.count }
            print("[CarPlay] [NAV] building tab title=\(safeTitle) sections=\(cpSections.count) totalItems=\(totalItems)")
            if totalItems == 0 { print("[CarPlay][TAB][EMPTY] tab title=\(safeTitle) has no items") }
            // Ensure sections are applied on main thread for reliability
            DispatchQueue.main.async {
                cpList.updateSections(cpSections)
            }
            // Re-apply after a short delay to avoid race with presentation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                cpList.updateSections(cpSections)
            }
            tabTemplates.append(cpList)
            if tabTemplates.count >= 4 { break }
        }

        // Fallback: if no AUTO_NAVIGATION sections, mirror Android by using AUTO_NAVIGATION_LIBRARY sections
        if tabTemplates.isEmpty {
            let librarySections = CDVPlaylistProvider.loadLibrarySectionsFromJSON()
            print("[CarPlay] setupTemplates: library sections loaded count=\(librarySections.count)")
            if librarySections.isEmpty {
                // As a last resort, build a single Playlists tab from extracted items
                let playlists = CDVPlaylistProvider.loadPlaylistsFromJSON()
                print("[CarPlay] setupTemplates: playlists loaded count=\(playlists.count)")
                var items: [CPListItem] = []
                for dict in playlists {
                    let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? "Playlist"
                    let subtitle = dict["description"] as? String
                    let pid = String(describing: dict["id"] ?? "")
                    let item = CPListItem(text: title, detailText: subtitle)
                    item.handler = { [weak self] _, completion in
                        guard let self else { completion(); return }
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
                list.tabTitle = "Playlists"
                if #available(iOS 13.0, *) {
                    list.tabImage = UIImage(systemName: "music.note.list")
                }
                DispatchQueue.main.async {
                    list.updateSections([section])
                }
                tabTemplates.append(list)
            } else {
                for (idx, sectionDict) in librarySections.enumerated() {
                    let title = (sectionDict["text"] as? String) ?? "Section \(idx+1)"
                    let sectionItems = sectionDict["items"] as? [[String: Any]] ?? []
                    print("[CarPlay] [LIB] section idx=\(idx) title=\(title) rawKeys=\(Array(sectionDict.keys)) items=\(sectionItems.count)")
                    var cpItems: [CPListItem] = []
                    for itemDict in sectionItems {
                        let name = (itemDict["name"] as? String) ?? (itemDict["title"] as? String) ?? "Item"
                        let subtitle = itemDict["description"] as? String
                        let pid = String(describing: itemDict["id"] ?? "")
                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            print("[CarPlay] [LIB][WARN] item with empty name. keys=\(Array(itemDict.keys))")
                        }
                        let listItem = CPListItem(text: name, detailText: subtitle)
                        let itemImage = (itemDict["artwork"] as? String) ?? (itemDict["image"] as? String) ?? (itemDict["icon"] as? String)
                        if let itemImage, !itemImage.isEmpty { print("[CarPlay][IMG] library item image URL: \(itemImage)") }
                        setListItemImage(listItem, from: itemImage)
                        listItem.handler = { [weak self] _, completion in
                            guard let self else { completion(); return }
                            print("[CarPlay] [LIB] list item selected in section=\(title) id=\(pid) name=\(name)")
                            if !pid.isEmpty {
                                let tracks = CDVPlaylistProvider.loadTracks(forPlaylist: pid)
                                print("[CarPlay] [LIB] tracks loaded for id=\(pid) count=\(tracks.count)")
                                if !tracks.isEmpty {
                                    self.musicPlayer.updateQueue(tracks)
                                    self.musicPlayer.play()
                                }
                            }
                            completion()
                        }
                        cpItems.append(listItem)
                    }
                    let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Section \(idx+1)" : title
                    print("[CarPlay] [LIB] building section title=\(safeTitle) items=\(cpItems.count)")
                    if cpItems.isEmpty { print("[CarPlay][TAB][EMPTY] library section title=\(safeTitle) has 0 items") }
                    let cpSection = CPListSection(items: cpItems)
                    let cpList = CPListTemplate(title: safeTitle, sections: [cpSection])
                    cpList.tabTitle = safeTitle
                    if #available(iOS 13.0, *) {
                        cpList.tabImage = UIImage(systemName: "music.note.list")
                    }
                    DispatchQueue.main.async {
                        cpList.updateSections([cpSection])
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        cpList.updateSections([cpSection])
                    }
                    tabTemplates.append(cpList)
                    if tabTemplates.count >= 4 { break }
                }
            }
        }

        // If after all attempts titles are empty or templates invalid, add a static Browse tab as a fail-safe
        if tabTemplates.isEmpty {
            print("[CarPlay][FALLBACK] No valid templates found. Adding static Browse tab.")
            let placeholders = [
                CPListItem(text: "Playlists", detailText: nil),
                CPListItem(text: "Favorites", detailText: nil),
                CPListItem(text: "Recently Played", detailText: nil)
            ]
            let section = CPListSection(items: placeholders)
            let list = CPListTemplate(title: "Browse", sections: [section])
            list.tabTitle = "Browse"
            if #available(iOS 13.0, *) {
                list.tabImage = UIImage(systemName: "music.note.list")
            }
            tabTemplates.append(list)
        }

        // Log final tabs
        let titles = tabTemplates.compactMap { ($0 as? CPListTemplate)?.tabTitle ?? "(unknown)" }
        print("[CarPlay] Final tabs count=\(tabTemplates.count) titles=\(titles)")
        for t in tabTemplates {
            if let l = t as? CPListTemplate {
                let title = l.tabTitle ?? l.title ?? "(untitled)"
                let count = l.sections.reduce(0) { $0 + $1.items.count }
                if count == 0 { print("[CarPlay][TAB][EMPTY] presenting empty tab: \(title)") }
            }
        }

        // Configure Now Playing template (cannot be part of TabBar templates)
        let now = CPNowPlayingTemplate.shared
        musicPlayer.setNowPlayingTemplate(now)

        // Optional: add a "Now Playing" list tab that opens the Now Playing screen when tapped
        if tabTemplates.count < 4 {
            let openNowItem = CPListItem(text: "Open Now Playing", detailText: nil)
            openNowItem.handler = { [weak self] _, completion in
                guard let self, let controller = self.interfaceController else { completion(); return }
                // Avoid pushing the shared instance more than once
                if self.isNowPlayingShown || controller.topTemplate === now {
                    print("[CarPlay] Now Playing already shown, skipping push")
                    completion(); return
                }
                print("[CarPlay] Now Playing list tab selected -> push CPNowPlayingTemplate")
                self.isNowPlayingShown = true
                controller.pushTemplate(now, animated: true)
                completion()
            }
            let nowSection = CPListSection(items: [openNowItem])
            let nowList = CPListTemplate(title: "Now Playing", sections: [nowSection])
            nowList.tabTitle = "Now Playing"
            tabTemplates.append(nowList)
        }

        // Set Tab Bar as root
        let tabBar = CPTabBarTemplate(templates: tabTemplates)
        print("[CarPlay] setupTemplates: presenting TabBar with \(tabTemplates.count) tabs")
        DispatchQueue.main.async {
            controller.setRootTemplate(tabBar, animated: true, completion: { success, error in
                if let error = error { print("[CarPlay] setRootTemplate(TabBar) error: \(error)") }
                else { print("[CarPlay] setRootTemplate(TabBar) success: \(success)") }
            })
            self.isNowPlayingShown = false
        }

        NotificationCenter.default.addObserver(self, selector: #selector(showNowPlayingTemplate), name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        print("[CarPlay] setupTemplates: end")
    }

    @objc private func showNowPlayingTemplate() {
      guard let controller = interfaceController else {
        print("[CarPlay] showNowPlayingTemplate: interfaceController nil")
        return
      }
      let now = CPNowPlayingTemplate.shared
      print("[CarPlay] showNowPlayingTemplate: presenting")
      DispatchQueue.main.async {
        if self.isNowPlayingShown || controller.topTemplate === now {
            print("[CarPlay] showNowPlayingTemplate: already shown, skipping push")
            return
        }
        // Ensure Now Playing metadata is populated before presenting
        // Request a one-shot clear to avoid stale UI without causing repeated blinking
        self.musicPlayer.requestNowPlayingClearRefresh()
        self.musicPlayer.updateNowPlayingInfo()
        self.isNowPlayingShown = true
        controller.pushTemplate(now, animated: true)
        // Single re-apply shortly after presentation to avoid races (no clearing this time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            print("[CarPlay] showNowPlayingTemplate: reapply NowPlayingInfo (+0.25s)")
            self.musicPlayer.updateNowPlayingInfo()
        }
      }
    }
}

