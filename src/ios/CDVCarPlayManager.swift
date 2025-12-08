import Foundation
import CarPlay
import MediaPlayer
import UIKit

@objc(CDVCarPlayManager)
class CDVCarPlayManager: NSObject, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate {
    private weak var plugin: CDVAutoMusicPlugin?

    private(set) var musicPlayer: CDVMusicPlayer!
    @objc var interfaceController: CPInterfaceController?
    @objc private(set) var connected: Bool = false
    private var isNowPlayingShown: Bool = false
    private let listImageCache = NSCache<NSURL, UIImage>()
    private var nowPlayingRetryCount: Int = 0
    private var didReopenNowPlayingOnce: Bool = false
    private var isPresentingNowPlaying: Bool = false
    private weak var nowPlayingListTab: CPListTemplate?

    @objc init(plugin: CDVAutoMusicPlugin) {
        self.plugin = plugin
        super.init()
        self.musicPlayer = CDVMusicPlayer(manager: self)
    }

    private struct QueueParentContext {
        let id: String
        let type: String
        let name: String
    }

    // Ensure queue items maintain the mobile app structure: { "data": { ...track... } }
    // and update the indice field within the data object
    private func normalizeQueueItems(_ rawItems: [[String: Any]]) -> [[String: Any]] {
        return rawItems.enumerated().map { index, item in
            // If item already has the correct structure, just update indice
            if var data = item["data"] as? [String: Any] {
                data["indice"] = index
                return ["data": data]
            }
            // Otherwise, wrap the item in the correct structure
            var data = item
            data["indice"] = index
            return ["data": data]
        }
    }

    private func buildParentContext(mediaType: String, itemId: String, parentTitle: String) -> QueueParentContext {
        let type: String
        switch mediaType {
        case "playlist": type = "PLAYLIST"
        case "album": type = "ALBUM"
        case "artist": type = "ARTIST"
        case "tag": type = "PLAYLIST"
        default: type = mediaType.uppercased()
        }
        return QueueParentContext(id: itemId, type: type, name: parentTitle)
    }

    private func bestArtworkURL(for track: Track, fallbackAlbumTitle: String?) -> String? {
        if let images = track.album?.images, !images.isEmpty {
            if let best = images.max(by: { ($0.size ?? 0) < ($1.size ?? 0) }) { return best.url }
            return images.first?.url
        }
        if let album = track.album, let coverList = album.images, !coverList.isEmpty {
            return coverList.first?.url
        }
        return nil
    }

    // Build a queue entry in the mobile app's structure: { "data": { ...track... } }
    private func queueEntry(from track: Track, signedUrl: String, parent: QueueParentContext, index: Int) -> [String: Any] {
        let albumTitle = track.album?.title ?? parent.name
        
        // Build the track data object
        // Convert id from String to Int if possible (mobile app expects number)
        let trackId: Any = Int(track.id) ?? track.id
        
        var trackData: [String: Any] = [
            "id": trackId,
            "name": track.name,
            "length": track.length,
            "explicit": track.explicit,
            "active": track.active,
            "itemType": track.itemType,
            "hasRelatedTracks": track.hasRelatedTracks,
            "source": signedUrl,
            "indice": index,
            "context": [
                "id": Int(parent.id) ?? 0,
                "type": parent.type,
                "name": parent.name
            ]
        ]
        
        if let idAlbumTrack = track.idAlbumTrack {
            trackData["idAlbumTrack"] = idAlbumTrack
        }
        if let isrc = track.isrc {
            trackData["isrc"] = isrc
        }
        if let version = track.version {
            trackData["version"] = version
        }
        if let score = track.score {
            trackData["score"] = score
        }
        
        if let number = track.number { trackData["number"] = number }
        if let volume = track.volume { trackData["volume"] = volume }
        
        // Build album object
        if let album = track.album {
            var albumData: [String: Any] = [:]
            albumData["id"] = album.id
            albumData["title"] = album.title
            if let images = album.images, !images.isEmpty {
                albumData["images"] = images.map { img -> [String: Any] in
                    var imgData: [String: Any] = [:]
                    imgData["type"] = "url"
                    if let url = img.url { imgData["url"] = url }
                    if let size = img.size { imgData["size"] = size }
                    if let type = img.imageType { imgData["imageType"] = type }
                    return imgData
                }
            }
            trackData["album"] = albumData
        }
        
        // Build artists array
        if !track.artists.isEmpty {
            trackData["artists"] = track.artists.map { artist -> [String: Any] in
                var artistData: [String: Any] = [
                    "id": artist.id,
                    "name": artist.name
                ]
                if let images = artist.images, !images.isEmpty {
                    artistData["images"] = images.map { img -> [String: Any] in
                        var imgData: [String: Any] = [:]
                        imgData["type"] = "url"
                        if let url = img.url { imgData["url"] = url }
                        if let size = img.size { imgData["size"] = size }
                        if let type = img.imageType { imgData["imageType"] = type }
                        return imgData
                    }
                }
                return artistData
            }
        }
        
        // Wrap in the mobile app's structure
        return ["data": trackData]
    }

    // MARK: - Icons
    @available(iOS 13.0, *)
    private func carPlayTabImage(from apiValue: Any?) -> UIImage? {
        let fallback = UIImage(systemName: "music.note.list")
        guard let raw = (apiValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return fallback
        }
        // Try SF Symbol name first
        if let symbol = UIImage(systemName: raw) {
            let config = UIImage.SymbolConfiguration(weight: .regular)
            return symbol.applyingSymbolConfiguration(config) ?? symbol
        }
        // Not a valid SF Symbol -> fallback. For URLs/paths, we keep the standard tab glyph.
        return fallback
    }

    // MARK: - Image URL extraction for list items
    private func extractImageURL(from dict: [String: Any]) -> String? {
        // 1) Direct keys commonly used by API payloads
        if let s = dict["artwork"] as? String, !s.isEmpty { return s }
        if let s = dict["image"] as? String, !s.isEmpty { return s }
        if let s = dict["icon"] as? String, !s.isEmpty { return s }
        // 2) images: [ { url, size, type } ] — choose the largest by size, else first with url
        if let images = dict["images"] as? [[String: Any]], !images.isEmpty {
            let sorted = images.sorted { (a, b) -> Bool in
                let sa = (a["size"] as? Int) ?? 0
                let sb = (b["size"] as? Int) ?? 0
                return sa > sb
            }
            for im in sorted {
                if let url = im["url"] as? String, !url.isEmpty { return url }
                // Some payloads use type=create_svg with list: ["https://…svg"]
                if let type = im["type"] as? String, type == "create_svg", let arr = im["list"] as? [String], let first = arr.first, !first.isEmpty { return first }
            }
        }
        // 3) Nested album.images (e.g., for tracks)
        if let album = dict["album"] as? [String: Any], let url = extractImageURL(from: album) { return url }
        return nil
    }

    // MARK: - CPTabBarTemplateDelegate
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect template: CPTemplate) {
        // If user taps the "Now Playing" tab, open the CarPlay Now Playing template immediately
        if let nowList = nowPlayingListTab, template === nowList {
            print("[CarPlay][TAB] Now Playing tab selected -> showNowPlayingTemplate()")
            // Reset flag to allow presentation if previously shown from another selection
            self.isNowPlayingShown = false
            showNowPlayingTemplate()
        }
    }

    // MARK: - Helpers
    private func setListItemImage(_ li: CPListItem, from urlString: String?) {
        guard let s = urlString, !s.isEmpty else {
            print("[CarPlay][IMG] no image URL present for list item")
            return
        }
        // First, try remote URL
        if let url = URL(string: s), url.scheme != nil {
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
                DispatchQueue.main.async {
                    li.setImage(img)
                    // Nudge UI to refresh if needed
                    if let list = self.interfaceController?.topTemplate as? CPListTemplate {
                        list.updateSections(list.sections)
                    }
                }
            }.resume()
            return
        }
        // Fallback: attempt to resolve a bundled/app-container image by name or relative path
        let candidates: [String] = [
            s,
            "www/\(s)",
            "img/\(s)",
            (s as NSString).lastPathComponent
        ]
        for candidate in candidates {
            if let img = UIImage(named: candidate) {
                print("[CarPlay][IMG] loaded bundled image: \(candidate) size=\(Int(img.size.width))x\(Int(img.size.height)))")
                li.setImage(img)
                return
            }
            // App container Library/NoCloud
            let noCloud = (NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? "") + "/NoCloud/" + candidate
            if FileManager.default.fileExists(atPath: noCloud), let img = UIImage(contentsOfFile: noCloud) {
                print("[CarPlay][IMG] loaded app-container image: \(candidate) size=\(Int(img.size.width))x\(Int(img.size.height)))")
                li.setImage(img)
                return
            }
        }
        print("[CarPlay][IMG][WARN] unable to resolve image reference: \(s)")
    }
    private func makeListItems(from dicts: [[String: Any]], parentTitle: String) -> [CPListItem] {
        var cpItems: [CPListItem] = []
        let allowedMediaTypes = ["PLAYLIST", "ALBUM", "ARTIST", "TAG"]

        for d in dicts {
            let name = (d["name"] as? String) ?? (d["title"] as? String) ?? (d["text"] as? String) ?? "Item"
            let subtitle = d["description"] as? String
            let id = String(describing: d["id"] ?? "")
            let mediaType = (d["itemType"] as? String) ?? (d["type"] as? String) // PLAYLIST, ALBUM, ARTIST, TAG
            let childFileName = d["fileName"] as? String
            let inlineItems = d["items"] as? [[String: Any]]

            // Validar que el mediaType exista y sea permitido
            guard let mediaType = mediaType, allowedMediaTypes.contains(mediaType.uppercased()) else {
                print("[CarPlay] Skipping item with missing or unsupported mediaType: \(mediaType ?? "nil")")
                continue
            }

            let li = CPListItem(text: name, detailText: subtitle)
            // Try to attach image if available on item (supports artwork/image/icon or images array)
            let imageUrl = extractImageURL(from: d)
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

                // Special handling for tags - show playlists as browsable items
                if mediaType.lowercased() == "tag", !id.isEmpty, let controller = self.interfaceController {
                    print("[CarPlay] Tag selected, fetching playlists for tag id=\(id)")
                    let api: MusicApi = MusicApiImpl()
                    api.getTagPlaylists(tagId: id) { result in
                        switch result {
                        case .success(let playlists):
                            print("[CarPlay] Tag playlists fetched: \(playlists.count)")
                            let playlistItems = self.makeListItems(from: playlists, parentTitle: name)
                            let section = CPListSection(items: playlistItems)
                            let next = CPListTemplate(title: name, sections: [section])
                            DispatchQueue.main.async {
                                self.isNowPlayingShown = false
                                controller.pushTemplate(next, animated: true)
                                completion()
                            }
                        case .failure(let e):
                            print("[CarPlay] Failed to fetch tag playlists: \(e)")
                            completion()
                        }
                    }
                    return
                }

                print("[CarPlay] makeListItems Try local queue file first")
                // 1) Try local queue file first
                var tracks = id.isEmpty ? [] : CDVPlaylistProvider.loadTracks(forPlaylist: id)

                print("[CarPlay] makeListItems local tracks loaded for id=\(id) count=\(tracks.count)")
                let normalizedLocal = normalizeQueueItems(tracks)

                // 2) If empty, attempt remote by mediaType
                if normalizedLocal.isEmpty, !mediaType.lowercased().isEmpty, !id.isEmpty {
                    let mediaLower = mediaType.lowercased()
                    let parentContext = self.buildParentContext(mediaType: mediaLower, itemId: id, parentTitle: name)
                    self.fetchTracksRemote(mediaType: mediaLower, itemId: id, parentContext: parentContext) { remote in
                        if !remote.isEmpty {
                            // Reset shown flag before kicking off playback so Now Playing can be presented again
                            self.isNowPlayingShown = false
                            // Extract ID from nested data structure
                            let firstData = remote.first?["data"] as? [String: Any]
                            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
                            // persist: true to sync queue with mobile app
                            self.musicPlayer.updateQueue(remote, selectedTrackId: selectedId, persist: true)
                            self.musicPlayer.play()
                        }
                    }
                } else if !tracks.isEmpty {
                    // Reset shown flag before kicking off playback so Now Playing can be presented again
                    self.isNowPlayingShown = false
                    // Extract ID from nested data structure
                    let firstData = normalizedLocal.first?["data"] as? [String: Any]
                    let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
                    // persist: true to sync queue with mobile app
                    self.musicPlayer.updateQueue(normalizedLocal, selectedTrackId: selectedId, persist: true)
                    self.musicPlayer.play()
                }
                completion()
            }
            cpItems.append(li)
        }
        return cpItems
    }

    private func fetchTracksRemote(mediaType: String, itemId: String, parentContext: QueueParentContext, completion: @escaping ([[String: Any]]) -> Void) {
        let api: MusicApi = MusicApiImpl()

        // Helper to resolve signed URLs for a list of Track models
        func resolveSignedUrls(from tracks: [Track], parent: QueueParentContext, completion: @escaping ([[String: Any]]) -> Void) {
            let group = DispatchGroup()
            var results: [[String: Any]?] = Array(repeating: nil, count: tracks.count)
            for (index, t) in tracks.enumerated() {
                group.enter()
                let req = TrackRequest(
                    idAlbumTrack: String(t.idAlbumTrack ?? 0),
                    idTrack: t.id,
                    forceDevice: false,
                    useCloudFront: true,
                    forcePreview: false,
                    extraLife: true
                )
                api.getTrackUrl(trackRequest: req) { res in
                    defer { group.leave() }
                    guard let signed = try? res.get() else { return }
                    let entry = self.queueEntry(from: t, signedUrl: signed.signedUrl, parent: parent, index: index)
                    results[index] = entry
                }
            }
            group.notify(queue: .main) { completion(results.compactMap { $0 }) }
        }

        switch mediaType {
        case "playlist":
            api.getPlayListTracks(playListId: itemId) { result in
                guard let container = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                let tracks = container.tracks.items.map { $0.track }
                print("[CarPlay][remote] playlist id=\(itemId) rawTracks=\(tracks.count)")
                resolveSignedUrls(from: tracks, parent: parentContext, completion: completion)
            }
        case "album":
            api.getAlbumTracks(albumId: itemId) { result in
                guard let album = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                print("[CarPlay][remote] album id=\(itemId) rawTracks=\(album.tracks.items.count)")
                resolveSignedUrls(from: album.tracks.items, parent: parentContext, completion: completion)
            }
        case "artist":
            api.getArtistTracks(artistId: itemId) { result in
                guard let artistTracks = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                print("[CarPlay][remote] artist id=\(itemId) rawTracks=\(artistTracks.list.count)")
                resolveSignedUrls(from: artistTracks.list, parent: parentContext, completion: completion)
            }
        case "tag":
            // Match Android: fetch playlists with this tag and show them as browsable items
            api.getTagPlaylists(tagId: itemId) { result in
                switch result {
                case .success(let playlists):
                    print("[CarPlay][remote] tag id=\(itemId) playlists=\(playlists.count)")
                    // Return empty array - tags should show playlists as browsable items, not play tracks
                    DispatchQueue.main.async { completion([]) }
                case .failure(let e):
                    print("[CarPlay][remote][tag] getTagPlaylists failed: \(e)")
                    DispatchQueue.main.async { completion([]) }
                }
            }
        default:
            print("[CarPlay][remote] unknown mediaType=\(mediaType)")
            DispatchQueue.main.async { completion([]) }
        }
    }

    @objc func isConnected() -> Bool { connected }
    
    // Called when the queue has been reloaded and CarPlay UI needs to refresh
    @objc func refreshQueueUI() {
        guard let controller = interfaceController else {
            print("[CarPlay] refreshQueueUI: No interface controller available")
            return
        }
        print("[CarPlay] refreshQueueUI: Rebuilding templates with new queue")
        setupTemplates(controller)
    }

    // MARK: - CPTemplateApplicationSceneDelegate
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        print("[CarPlay] didConnect: interfaceController received")
        connected = true
        self.interfaceController = interfaceController
        // Present a lightweight placeholder to avoid gray screen while we build templates
        presentLoadingPlaceholder(interfaceController)
        // Reload any queue stored by the host app before building templates so Now Playing can bind
        self.musicPlayer.reloadQueueForced()
        // Build and replace with real templates
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
    private func presentLoadingPlaceholder(_ controller: CPInterfaceController) {
        let loadingItem = CPListItem(text: "Initializing…", detailText: nil)
        if #available(iOS 15.0, *) {
            loadingItem.isEnabled = false
        }
        let section = CPListSection(items: [loadingItem])
        let loadingList = CPListTemplate(title: "Loading", sections: [section])
        loadingList.tabTitle = "Loading"
        let placeholder = CPTabBarTemplate(templates: [loadingList])
        DispatchQueue.main.async {
            controller.setRootTemplate(placeholder, animated: false, completion: { success, error in
                if let error = error { print("[CarPlay] setRootTemplate(Loading) error: \(error)") }
                else { print("[CarPlay] setRootTemplate(Loading) success: \(success)") }
            })
        }
    }
    private func setupTemplates(_ controller: CPInterfaceController) {
      print("[CarPlay] setupTemplates: begin")
      let autoNavigation = CDVPlaylistProvider.loadNavigationFromJSON()
      // Pretty-print full AUTO_NAVIGATION for diagnostics
      if let data = try? JSONSerialization.data(withJSONObject: autoNavigation, options: [.prettyPrinted]),
         let pretty = String(data: data, encoding: .utf8) {
          print("[CarPlay][NAV][FULL] AUTO_NAVIGATION=\n\(pretty)")
      } else {
          print("[CarPlay][NAV][FULL][WARN] could not serialize AUTO_NAVIGATION to JSON")
      }
      print("[CarPlay] setupTemplates: AUTO_NAVIGATION sections count=\(autoNavigation.count)")
      if let first = autoNavigation.first {
          print("[CarPlay] setupTemplates: first section keys=\(Array(first.keys))")
          if let text = first["text"] as? String { print("[CarPlay] setupTemplates: first section text=\(text)") }
          if let items = first["items"] as? [[String: Any]] { print("[CarPlay] setupTemplates: first section items count=\(items.count)") }
      } else {
          print("[CarPlay] setupTemplates: AUTO_NAVIGATION is empty")
      }

        // Build list templates from AUTO_NAVIGATION sections (collect all; we'll trim/compose later)
        var navTemplates: [CPTemplate] = []
        for (idx, sectionDict) in autoNavigation.enumerated() {
            let sectionTitle = (sectionDict["text"] as? String) ?? "Section \(idx+1)"
            let fileName = (sectionDict["fileName"] as? String) ?? ""
            let explicitItems = sectionDict["items"] as? [[String: Any]]
            let sectionIcon = sectionDict["icon"]
            if let iconStr = sectionIcon as? String, !iconStr.isEmpty {
                print("[CarPlay][TAB] section icon value=\(iconStr) for title=\(sectionTitle)")
            } else {
                print("[CarPlay][TAB] no icon for title=\(sectionTitle); will use fallback")
            }

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
                        let subImage = extractImageURL(from: subSection)
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
            if #available(iOS 13.0, *) { cpList.tabImage = carPlayTabImage(from: sectionIcon) }
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
            navTemplates.append(cpList)
        }

        // Fallback: if no AUTO_NAVIGATION sections, mirror Android by using AUTO_NAVIGATION_LIBRARY sections
        if navTemplates.isEmpty {
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
                        let normalized = self.normalizeQueueItems(tracks)
                        // Reset shown flag before starting playback
                        self.isNowPlayingShown = false
                        let selectedId = normalized.first?["idAlbumTrack"] as? String ?? normalized.first?["id"] as? String
                        self.musicPlayer.updateQueue(normalized, selectedTrackId: selectedId)
                        self.musicPlayer.play()
                        completion()
                    }
                    items.append(item)
                }
                let section = CPListSection(items: items)
                let list = CPListTemplate(title: "Playlists", sections: [section])
                list.tabTitle = "Playlists"
                if #available(iOS 13.0, *) { list.tabImage = carPlayTabImage(from: nil) }
                DispatchQueue.main.async {
                    list.updateSections([section])
                }
                navTemplates.append(list)
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
                                let normalized = self.normalizeQueueItems(tracks)
                                if !normalized.isEmpty {
                                    // Reset shown flag before starting playback
                                    self.isNowPlayingShown = false
                                    let selectedId = normalized.first?["idAlbumTrack"] as? String ?? normalized.first?["id"] as? String
                                    self.musicPlayer.updateQueue(normalized, selectedTrackId: selectedId)
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
                    if #available(iOS 13.0, *) { cpList.tabImage = carPlayTabImage(from: nil) }
                    DispatchQueue.main.async {
                        cpList.updateSections([cpSection])
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        cpList.updateSections([cpSection])
                    }
                    navTemplates.append(cpList)
                }
            }
        }

        // If after all attempts titles are empty or templates invalid, add a static Browse tab as a fail-safe
        if navTemplates.isEmpty {
            print("[CarPlay][FALLBACK] No valid templates found. Adding static Browse tab.")
            let placeholders = [
                CPListItem(text: "Playlists", detailText: nil),
                CPListItem(text: "Favorites", detailText: nil),
                CPListItem(text: "Recently Played", detailText: nil)
            ]
            let section = CPListSection(items: placeholders)
            let list = CPListTemplate(title: "Browse", sections: [section])
            list.tabTitle = "Browse"
            if #available(iOS 13.0, *) { list.tabImage = carPlayTabImage(from: nil) }
            navTemplates.append(list)
        }

        // Log navigation tabs before composing final tab bar
        let titles = navTemplates.compactMap { ($0 as? CPListTemplate)?.tabTitle ?? "(unknown)" }
        print("[CarPlay] Nav tabs (pre-compose) count=\(navTemplates.count) titles=\(titles)")
        for t in navTemplates {
            if let l = t as? CPListTemplate {
                let title = l.tabTitle ?? l.title ?? "(untitled)"
                let count = l.sections.reduce(0) { $0 + $1.items.count }
                if count == 0 { print("[CarPlay][TAB][EMPTY] presenting empty tab: \(title)") }
            }
        }

        // Configure Now Playing template (cannot be part of TabBar templates)
        let now = CPNowPlayingTemplate.shared
        musicPlayer.setNowPlayingTemplate(now)

        // Compose final tab templates with ONLY navigation templates.
        // Do not add a dedicated "Now Playing" tab; rely on CarPlay's default Now Playing button.
        let tabTemplates: [CPTemplate] = navTemplates

        // Set Tab Bar as root
        let tabBar = CPTabBarTemplate(templates: tabTemplates)
        tabBar.delegate = self
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
        if self.isPresentingNowPlaying || self.isNowPlayingShown || controller.topTemplate === now {
            print("[CarPlay] showNowPlayingTemplate: already shown, skipping push")
            return
        }
        // Ensure we have a current track; otherwise, retry briefly to avoid presenting a blank Now Playing
        if self.musicPlayer.currentTrack == nil {
            if self.nowPlayingRetryCount < 3 {
                self.nowPlayingRetryCount += 1
                print("[CarPlay] showNowPlayingTemplate: no track yet, retry #\(self.nowPlayingRetryCount) in 0.5s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showNowPlayingTemplate() }
            } else {
                print("[CarPlay] showNowPlayingTemplate: giving up after retries due to no track")
                self.nowPlayingRetryCount = 0
            }
            return
        }
        // Extra guard: require NowPlayingInfo to contain at least a title or artist before presenting
        let np = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let hasTitle = (np?[MPMediaItemPropertyTitle] as? String)?.isEmpty == false
        let hasArtist = (np?[MPMediaItemPropertyArtist] as? String)?.isEmpty == false
        if !(hasTitle || hasArtist) {
            if self.nowPlayingRetryCount < 5 {
                self.nowPlayingRetryCount += 1
                print("[CarPlay] showNowPlayingTemplate: missing title/artist in NowPlayingInfo, retry #\(self.nowPlayingRetryCount) in 0.3s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showNowPlayingTemplate() }
            } else {
                print("[CarPlay] showNowPlayingTemplate: proceeding without visible metadata after retries")
                self.nowPlayingRetryCount = 0
            }
            return
        }
        // Also require the AVPlayerItem to be ready, to avoid CarPlay binding to an unknown/idle item state
        if !self.musicPlayer.isCurrentItemReady() {
            if self.nowPlayingRetryCount < 7 {
                self.nowPlayingRetryCount += 1
                print("[CarPlay] showNowPlayingTemplate: player item not ready, retry #\(self.nowPlayingRetryCount) in 0.2s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showNowPlayingTemplate() }
            } else {
                print("[CarPlay] showNowPlayingTemplate: proceeding even though item not ready (after retries)")
                self.nowPlayingRetryCount = 0
            }
            return
        }
        self.nowPlayingRetryCount = 0
        // Ensure Now Playing metadata is populated before presenting
        // Avoid clearing here to reduce visible flicker; rely on track-change clears instead
        // Apply a minimal set first to help CarPlay bind quickly
        self.musicPlayer.applyMinimalNowPlayingInfo()
        // Then apply the full metadata shortly after
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.musicPlayer.updateNowPlayingInfo()
        }
        // Slightly increase delay to give the system time to register NowPlayingInfo before template push
        let pushDelay: TimeInterval = 0.3
        self.isPresentingNowPlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + pushDelay) {
            controller.pushTemplate(now, animated: true)
            // Mark as shown and clear presenting flag shortly after push
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.isNowPlayingShown = true
                self.isPresentingNowPlaying = false
            }
        }
        // Single re-apply after presentation to avoid races (no clearing this time)
        DispatchQueue.main.asyncAfter(deadline: .now() + pushDelay + 0.15) {
            print("[CarPlay] showNowPlayingTemplate: reapply NowPlayingInfo (post-push)")
            self.musicPlayer.updateNowPlayingInfo()
        }
        // Removed extra minimal nudge and pop/push repaint to avoid visible flicker
      }
    }
}

