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

    // Flag to track if root template has been set - prevents crash when pushing templates
    private var isRootTemplateSet: Bool = false

    @objc init(plugin: CDVAutoMusicPlugin) {
        self.plugin = plugin
        super.init()
        self.musicPlayer = CDVMusicPlayer(manager: self)

        // Observe scene connection notifications to detect CarPlay availability
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneActivation(_:)),
            name: UIScene.didActivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDisconnection(_:)),
            name: UIScene.didDisconnectNotification,
            object: nil
        )

        // Start network monitoring and refresh templates when connectivity changes
        CDVNetworkUtils.shared.startMonitoring()
        CDVNetworkUtils.shared.onNetworkStatusChanged = { [weak self] isAvailable in
            print("[CarPlay] Network status changed: \(isAvailable ? "ONLINE" : "OFFLINE")")
            guard let self = self, self.connected, let controller = self.interfaceController else { return }
            // Refresh templates when network state changes
            DispatchQueue.main.async {
                self.setupTemplates(controller)
            }
        }

        // Check if CarPlay is already connected when plugin initializes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkCarPlayConnection()
        }
    }

    @objc private func handleSceneActivation(_ notification: Notification) {
        if notification.object is CPTemplateApplicationScene {
            print("[CarPlay] Scene activated: CarPlay scene detected")
            if !connected {
                connected = true
                NotificationCenter.default.post(
                    name: Notification.Name("CDVCarPlayConnectionChanged"),
                    object: nil,
                    userInfo: ["connected": true]
                )
            }
        }
    }

    @objc private func handleSceneDisconnection(_ notification: Notification) {
        if notification.object is CPTemplateApplicationScene {
            print("[CarPlay] Scene disconnected: CarPlay scene removed")
            if connected {
                connected = false
                isRootTemplateSet = false
                // CRITICAL: Stop the CarPlay player to prevent double playback
                musicPlayer.deactivateForCarPlay()
                NotificationCenter.default.post(
                    name: Notification.Name("CDVCarPlayConnectionChanged"),
                    object: nil,
                    userInfo: ["connected": false]
                )
                interfaceController = nil
            }
        }
    }

    private func checkCarPlayConnection() {
        let carPlayConnected = UIApplication.shared.connectedScenes.contains { scene in
            scene is CPTemplateApplicationScene
        }
        print("[CarPlay] checkCarPlayConnection: carPlayConnected=\(carPlayConnected), current connected=\(connected)")
        if carPlayConnected && !connected {
            connected = true
            NotificationCenter.default.post(
                name: Notification.Name("CDVCarPlayConnectionChanged"),
                object: nil,
                userInfo: ["connected": true]
            )
        }
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
        case "playlist", "mix": type = mediaType.uppercased()
        case "album": type = "ALBUM"
        case "artist": type = "ARTIST"
        case "tag": type = "RADIO"
        case "artist_radio": type = "ARTIST_STATION"
        case "radio_track": type = "TRACK_RADIO"
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

    /// SF Symbol mapping for navigation tabs based on section title or fileName
    /// This ensures consistent, visible icons across all iOS versions and themes
    private static let sfSymbolMapping: [String: String] = [
        // Main navigation tabs (by text/title)
        "home": "house.fill",
        "inicio": "house.fill",
        "library": "books.vertical.fill",
        "biblioteca": "books.vertical.fill",
        "mi música": "books.vertical.fill",
        "mi musica": "books.vertical.fill",
        "explorer": "safari.fill",
        "explorar": "safari.fill",
        "explore": "safari.fill",
        "buscar": "magnifyingglass",
        "search": "magnifyingglass",
        "recents": "clock.fill",
        "recientes": "clock.fill",
        "recent": "clock.fill",
        "history": "clock.fill",
        "historial": "clock.fill",
        "offline": "arrow.down.circle.fill",
        "downloads": "arrow.down.circle.fill",
        "descargas": "arrow.down.circle.fill",
        "favorites": "heart.fill",
        "favoritos": "heart.fill",
        "browse": "square.grid.2x2.fill",
        "navegar": "square.grid.2x2.fill",

        // Library subsections (by text/title)
        "playlists": "music.note.list",
        "playlist": "music.note.list",
        "albums": "square.stack.fill",
        "álbumes": "square.stack.fill",
        "album": "square.stack.fill",
        "artists": "music.mic",
        "artistas": "music.mic",
        "artist": "music.mic",
        "tracks": "music.note",
        "canciones": "music.note",
        "songs": "music.note",
        "podcasts": "mic.fill",
        "podcast": "mic.fill",
        "radio": "dot.radiowaves.left.and.right",
        "genres": "guitars.fill",
        "géneros": "guitars.fill",

        // By fileName
        "auto_navigation_home": "house.fill",
        "auto_navigation_library": "books.vertical.fill",
        "auto_navigation_library_offline": "arrow.down.circle.fill",
        "auto_navigation_explorer": "safari.fill",
        "recent_listened": "clock.fill",
        "queue_items_key": "list.bullet"
    ]

    @available(iOS 13.0, *)
    private func carPlayTabImage(from apiValue: Any?, sectionTitle: String? = nil, fileName: String? = nil) -> UIImage? {
        let config = UIImage.SymbolConfiguration(weight: .medium)
        let fallback = UIImage(systemName: "music.note.list")?.applyingSymbolConfiguration(config)

        // 1. Try to find SF Symbol from section title (case-insensitive)
        if let title = sectionTitle?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           let symbolName = Self.sfSymbolMapping[title],
           let symbol = UIImage(systemName: symbolName) {
            print("[CarPlay][ICON] Using SF Symbol '\(symbolName)' for title '\(sectionTitle ?? "")'")
            return symbol.applyingSymbolConfiguration(config) ?? symbol
        }

        // 2. Try to find SF Symbol from fileName (case-insensitive)
        if let file = fileName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           let symbolName = Self.sfSymbolMapping[file],
           let symbol = UIImage(systemName: symbolName) {
            print("[CarPlay][ICON] Using SF Symbol '\(symbolName)' for fileName '\(fileName ?? "")'")
            return symbol.applyingSymbolConfiguration(config) ?? symbol
        }

        // 3. Try to use apiValue directly as SF Symbol name (if it's already a valid SF Symbol)
        if let raw = (apiValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if let symbol = UIImage(systemName: raw) {
                print("[CarPlay][ICON] Using SF Symbol '\(raw)' from API value")
                return symbol.applyingSymbolConfiguration(config) ?? symbol
            }
        }

        // 4. Fallback to default icon
        print("[CarPlay][ICON] Using fallback icon for title='\(sectionTitle ?? "")' fileName='\(fileName ?? "")'")
        return fallback
    }

    /// Get SF Symbol for library subsections
    @available(iOS 13.0, *)
    private func librarySubsectionImage(for title: String) -> UIImage? {
        let config = UIImage.SymbolConfiguration(weight: .medium)
        let lowercased = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let symbolName = Self.sfSymbolMapping[lowercased],
           let symbol = UIImage(systemName: symbolName) {
            print("[CarPlay][ICON] Library subsection '\(title)' -> SF Symbol '\(symbolName)'")
            return symbol.applyingSymbolConfiguration(config) ?? symbol
        }

        // Default for unknown subsections
        let fallback = UIImage(systemName: "folder.fill")?.applyingSymbolConfiguration(config)
        print("[CarPlay][ICON] Library subsection '\(title)' -> fallback folder icon")
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
    private func setListItemImage(_ li: CPListItem, from urlString: String?, itemType: String? = nil, itemId: String? = nil, itemDict: [String: Any]? = nil) {
        // PRIORITY 1: Check for local image first (offline support)
        // For tracks, we need to use the album ID, not the track ID
        if let type = itemType, !type.isEmpty {
            var lookupType = type.lowercased()
            var lookupId = itemId ?? ""

            // For tracks, extract albumId from the item dictionary
            if lookupType == "track", let dict = itemDict {
                if let albumDict = dict["album"] as? [String: Any],
                   let albumId = albumDict["id"] {
                    lookupId = String(describing: albumId)
                    lookupType = "album" // Use album type for cover lookup
                    print("[CarPlay][IMG] Track -> using album cover: albumId=\(lookupId)")
                }
            }

            if !lookupId.isEmpty {
                if let localImage = CDVLocalStorageUtils.getLocalImage(itemType: lookupType, itemId: lookupId) {
                    print("[CarPlay][IMG] Using LOCAL image for \(lookupType)/\(lookupId) size=\(Int(localImage.size.width))x\(Int(localImage.size.height))")
                    li.setImage(localImage)
                    return
                }
            }
        }

        guard let s = urlString, !s.isEmpty else {
            print("[CarPlay][IMG] no image URL present for list item")
            return
        }

        // PRIORITY 2: Handle file:// URLs (e.g., mix covers stored in Documents/)
        if let url = URL(string: s), url.isFileURL {
            if let img = UIImage(contentsOfFile: url.path) {
                print("[CarPlay][IMG] loaded file URL image: \(url.path) size=\(Int(img.size.width))x\(Int(img.size.height)))")
                li.setImage(img)
            } else {
                print("[CarPlay][IMG][WARN] file URL image not found: \(url.path)")
            }
            return
        }

        // PRIORITY 3: Try memory cache
        if let url = URL(string: s), url.scheme != nil {
            let nsurl = url as NSURL
            if let cached = listImageCache.object(forKey: nsurl) {
                print("[CarPlay][IMG] cache hit for list image: \(s) size=\(Int(cached.size.width))x\(Int(cached.size.height)))")
                li.setImage(cached)
                return
            }

            // PRIORITY 4: Download from remote URL
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
        let allowedMediaTypes = ["PLAYLIST", "ALBUM", "ARTIST", "TAG", "TRACK", "PODCAST", "RADIO_TRACK", "RADIO", "ARTIST_RADIO", "ARTIST_STATION", "MIX"]

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
            setListItemImage(li, from: imageUrl, itemType: mediaType, itemId: id, itemDict: d)
            li.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                print("[CarPlay] select item name=\(name) id=\(id) mediaType=\(mediaType ?? "-") fileName=\(childFileName ?? "<nil>") in parent=\(parentTitle)")

                // Drill-down navigation takes precedence if a child file or inline items exist
                if let file = childFileName, !file.isEmpty, let controller = self.interfaceController {
                    let children = CDVPlaylistProvider.loadNavigationChildren(fileName: file)
                    print("[CarPlay][NAV] drill-down file=\(file) children=\(children.count)")
                    let nextItems = self.makeListItems(from: children, parentTitle: name)
                    // Add Play All / Shuffle action items for playable parent types (Phase 7)
                    let playableTypes = ["PLAYLIST", "ALBUM", "ARTIST", "MIX"]
                    var sections: [CPListSection] = []
                    if playableTypes.contains(mediaType.uppercased()), !id.isEmpty {
                        let actionItems = self.buildActionItems(mediaType: mediaType.lowercased(), itemId: id, parentTitle: name)
                        sections.append(CPListSection(items: actionItems))
                    }
                    sections.append(CPListSection(items: nextItems))
                    let next = CPListTemplate(title: name, sections: sections)
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
                    // Add Play All / Shuffle action items for playable parent types (Phase 7)
                    let playableTypes = ["PLAYLIST", "ALBUM", "ARTIST", "MIX"]
                    var sections: [CPListSection] = []
                    if playableTypes.contains(mediaType.uppercased()), !id.isEmpty {
                        let actionItems = self.buildActionItems(mediaType: mediaType.lowercased(), itemId: id, parentTitle: name)
                        sections.append(CPListSection(items: actionItems))
                    }
                    sections.append(CPListSection(items: nextItems))
                    let next = CPListTemplate(title: name, sections: sections)
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

                // Handle single track playback as track radio (TRACK type)
                if mediaType.uppercased() == "TRACK", !id.isEmpty {
                    print("[CarPlay] Single track selected as track radio, id=\(id)")
                    self.handleTrackRadio(trackId: id, trackName: name, trackDict: d)
                    completion()
                    return
                }

                // Handle podcast (browsable - shows episodes)
                if mediaType.uppercased() == "PODCAST", !id.isEmpty, let controller = self.interfaceController {
                    print("[CarPlay] Podcast selected, fetching episodes for show id=\(id)")
                    self.handlePodcastTap(showId: id, showName: name, controller: controller, completion: completion)
                    return
                }

                // Handle radio types (RADIO_TRACK, RADIO, ARTIST_RADIO, ARTIST_STATION)
                let radioTypes = ["RADIO_TRACK", "RADIO", "ARTIST_RADIO", "ARTIST_STATION"]
                if radioTypes.contains(mediaType.uppercased()), !id.isEmpty {
                    print("[CarPlay] Radio type \(mediaType) selected, id=\(id)")
                    self.handleRadioTap(radioType: mediaType.uppercased(), itemId: id, itemName: name, itemDict: d)
                    completion()
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
                            // Persist playback context (Phase 1: PLAYLIST_DATA)
                            self.musicPlayer.setCurrentParentContext([
                                "id": parentContext.id,
                                "type": parentContext.type,
                                "name": parentContext.name
                            ])
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
                    // Persist playback context for local tracks (Phase 1: PLAYLIST_DATA)
                    let mediaLower = mediaType.lowercased()
                    let parentContext = self.buildParentContext(mediaType: mediaLower, itemId: id, parentTitle: name)
                    self.musicPlayer.setCurrentParentContext([
                        "id": parentContext.id,
                        "type": parentContext.type,
                        "name": parentContext.name
                    ])
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

    // MARK: - Type-specific handlers (Phase 4+5+6)

    /// Handle tap on an image in the Home image row (Quick Access)
    private func handleHomeItemTap(id: String, mediaType: String, name: String, itemDict: [String: Any]) {
        let upperType = mediaType.uppercased()

        if upperType == "TRACK", !id.isEmpty {
            handleTrackRadio(trackId: id, trackName: name, trackDict: itemDict)
            return
        }
        if upperType == "PODCAST", !id.isEmpty, let controller = interfaceController {
            handlePodcastTap(showId: id, showName: name, controller: controller, completion: {})
            return
        }
        let radioTypes = ["RADIO_TRACK", "RADIO", "ARTIST_RADIO", "ARTIST_STATION"]
        if radioTypes.contains(upperType), !id.isEmpty {
            handleRadioTap(radioType: upperType, itemId: id, itemName: name, itemDict: itemDict)
            return
        }

        // Default: playlist/mix/album/artist — try local queue then remote
        guard !id.isEmpty else { return }
        let mediaLower = mediaType.lowercased()
        let parentContext = buildParentContext(mediaType: mediaLower, itemId: id, parentTitle: name)
        let tracks = CDVPlaylistProvider.loadTracks(forPlaylist: id)
        let normalizedLocal = normalizeQueueItems(tracks)

        if normalizedLocal.isEmpty {
            fetchTracksRemote(mediaType: mediaLower, itemId: id, parentContext: parentContext) { [weak self] remote in
                guard let self = self, !remote.isEmpty else { return }
                self.musicPlayer.setCurrentParentContext(["id": parentContext.id, "type": parentContext.type, "name": parentContext.name])
                self.isNowPlayingShown = false
                let firstData = remote.first?["data"] as? [String: Any]
                let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
                self.musicPlayer.updateQueue(remote, selectedTrackId: selectedId, persist: true)
                self.musicPlayer.play()
            }
        } else {
            musicPlayer.setCurrentParentContext(["id": parentContext.id, "type": parentContext.type, "name": parentContext.name])
            isNowPlayingShown = false
            let firstData = normalizedLocal.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            musicPlayer.updateQueue(normalizedLocal, selectedTrackId: selectedId, persist: true)
            musicPlayer.play()
        }
    }

    /// Load an image from URL (file://, cache, or remote download)
    private func loadImageAsync(from urlString: String, itemType: String? = nil, itemId: String? = nil, completion: @escaping (UIImage?) -> Void) {
        // Try local offline image first
        if let type = itemType, !type.isEmpty, let id = itemId, !id.isEmpty {
            if let localImage = CDVLocalStorageUtils.getLocalImage(itemType: type.lowercased(), itemId: id) {
                completion(localImage)
                return
            }
        }

        guard let url = URL(string: urlString) else { completion(nil); return }

        // File URL — load directly from filesystem
        if url.isFileURL {
            completion(UIImage(contentsOfFile: url.path))
            return
        }

        // Memory cache
        let nsurl = url as NSURL
        if let cached = listImageCache.object(forKey: nsurl) {
            completion(cached)
            return
        }

        // Download from remote
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { completion(nil); return }
            self?.listImageCache.setObject(img, forKey: nsurl)
            completion(img)
        }.resume()
    }

    /// Handle tap on a single TRACK item - fetch signed URL and play
    private func handleTrackTap(trackId: String, trackName: String) {
        let api: MusicApi = MusicApiImpl()
        let req = TrackRequest(
            idAlbumTrack: trackId,
            idTrack: trackId,
            forceDevice: false,
            useCloudFront: true,
            forcePreview: false,
            extraLife: true
        )
        api.getTrackUrl(trackRequest: req) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let signed):
                let parentContext = QueueParentContext(id: "0", type: "TRACK", name: trackName)
                let entry: [String: Any] = [
                    "data": [
                        "id": trackId,
                        "idAlbumTrack": trackId,
                        "name": trackName,
                        "source": signed.signedUrl,
                        "indice": 0,
                        "context": [
                            "id": parentContext.id,
                            "type": parentContext.type,
                            "name": parentContext.name
                        ]
                    ] as [String: Any]
                ]
                DispatchQueue.main.async {
                    self.musicPlayer.setCurrentParentContext([
                        "id": parentContext.id, "type": parentContext.type, "name": parentContext.name
                    ])
                    self.isNowPlayingShown = false
                    self.musicPlayer.updateQueue([entry], selectedTrackId: trackId, persist: true)
                    self.musicPlayer.play()
                }
            case .failure(let error):
                print("[CarPlay] handleTrackTap: failed to get track URL: \(error.localizedDescription)")
            }
        }
    }

    /// Handle tap on a PODCAST item - show episodes list (browsable)
    private func handlePodcastTap(showId: String, showName: String, controller: CPInterfaceController, completion: @escaping () -> Void) {
        let api: MusicApi = MusicApiImpl()
        api.getPodcastEpisodes(showId: showId, limit: 20, offset: 0) { [weak self] result in
            guard let self = self else { completion(); return }
            switch result {
            case .success(let showResponse):
                let episodes = showResponse.episodes
                print("[CarPlay] Podcast episodes fetched: \(episodes.count)")
                var episodeItems: [CPListItem] = []
                for episode in episodes {
                    let epTitle = episode.title
                    let epSubtitle = episode.showTitle ?? showName
                    let li = CPListItem(text: epTitle, detailText: epSubtitle)
                    // Set episode image if available
                    if let imageUrl = episode.image ?? episode.ourImage {
                        self.setListItemImage(li, from: imageUrl, itemType: "podcast", itemId: episode.id)
                    }
                    li.handler = { [weak self] _, epCompletion in
                        guard let self = self else { epCompletion(); return }
                        print("[CarPlay] Podcast episode selected: \(epTitle) id=\(episode.id)")
                        self.handlePodcastEpisodePlay(episode: episode, showName: showName)
                        epCompletion()
                    }
                    episodeItems.append(li)
                }
                let section = CPListSection(items: episodeItems)
                let next = CPListTemplate(title: showName, sections: [section])
                DispatchQueue.main.async {
                    self.isNowPlayingShown = false
                    controller.pushTemplate(next, animated: true)
                    completion()
                }
            case .failure(let error):
                print("[CarPlay] Failed to fetch podcast episodes: \(error.localizedDescription)")
                completion()
            }
        }
    }

    /// Play a podcast episode
    private func handlePodcastEpisodePlay(episode: PodcastEpisode, showName: String) {
        let audioUrl = episode.enclosureUrl ?? ""
        guard !audioUrl.isEmpty else {
            print("[CarPlay] handlePodcastEpisodePlay: no audio URL for episode \(episode.id)")
            return
        }
        let parentContext: [String: Any] = [
            "id": episode.showId ?? "0",
            "type": "PODCAST",
            "name": showName
        ]
        let entry: [String: Any] = [
            "data": [
                "id": episode.id,
                "name": episode.title,
                "title": episode.title,
                "source": audioUrl,
                "indice": 0,
                "isPodcast": true,
                "showTitle": showName,
                "showId": episode.showId ?? "",
                "duration": episode.duration ?? "",
                "image": episode.image ?? episode.ourImage ?? "",
                "context": parentContext
            ] as [String: Any]
        ]
        // Persist podcast context
        musicPlayer.setCurrentParentContext(parentContext)
        CDVQueueStorage.setCurrentEpisode([
            "id": episode.id,
            "title": episode.title,
            "showId": episode.showId ?? "",
            "showTitle": showName,
            "duration": episode.duration ?? "",
            "image": episode.image ?? episode.ourImage ?? "",
            "enclosure": ["url": audioUrl, "type": "audio/mpeg"]
        ])
        isNowPlayingShown = false
        musicPlayer.updateQueue([entry], selectedTrackId: episode.id, persist: true)
        musicPlayer.play()
    }

    /// Handle tap on radio types (RADIO_TRACK, RADIO, ARTIST_RADIO, ARTIST_STATION)
    private func handleRadioTap(radioType: String, itemId: String, itemName: String, itemDict: [String: Any]) {
        switch radioType {
        case "RADIO_TRACK":
            // Track radio: selected track + related tracks
            handleTrackRadio(trackId: itemId, trackName: itemName, trackDict: itemDict)
        case "RADIO":
            // Station radio: fetch station tracks
            handleStationRadio(stationId: itemId, stationName: itemName, stationDict: itemDict)
        case "ARTIST_RADIO", "ARTIST_STATION":
            // Artist radio: top tracks shuffled
            handleArtistRadio(artistId: itemId, artistName: itemName)
        default:
            print("[CarPlay] handleRadioTap: unknown radio type \(radioType)")
        }
    }

    /// Track radio: play the selected track + related tracks
    private func handleTrackRadio(trackId: String, trackName: String, trackDict: [String: Any]) {
        let api: MusicApi = MusicApiImpl()
        // Use idAlbumTrack for the parent context id (JS expects idAlbumTrack, not id)
        let idAlbumTrack = String(describing: trackDict["idAlbumTrack"] ?? trackId)
        let parentContext = QueueParentContext(id: idAlbumTrack, type: "TRACK_RADIO", name: trackName)

        // First get the signed URL for the selected track
        let req = TrackRequest(
            idAlbumTrack: idAlbumTrack,
            idTrack: trackId,
            forceDevice: false,
            useCloudFront: true,
            forcePreview: false,
            extraLife: true
        )
        api.getTrackUrl(trackRequest: req) { [weak self] trackResult in
            guard let self = self else { return }
            let selectedEntry: [String: Any]? = {
                guard let signed = try? trackResult.get() else { return nil }
                // Use trackDict as base (has album, artists, etc.) and enrich with source/context
                var data = trackDict
                data["source"] = signed.signedUrl
                data["indice"] = 0
                data["context"] = ["id": idAlbumTrack, "type": "TRACK_RADIO", "name": trackName]
                return ["data": data]
            }()

            // Then fetch related tracks
            api.getRelatedTracks(trackId: trackId, limit: 14) { [weak self] relatedResult in
                guard let self = self else { return }
                switch relatedResult {
                case .success(let relatedTracks):
                    let tracks = relatedTracks.list
                    print("[CarPlay] Track radio: \(tracks.count) related tracks found")
                    // Resolve signed URLs for related tracks
                    let group = DispatchGroup()
                    var results: [[String: Any]?] = Array(repeating: nil, count: tracks.count)
                    for (index, t) in tracks.enumerated() {
                        group.enter()
                        let relReq = TrackRequest(
                            idAlbumTrack: String(t.idAlbumTrack ?? 0),
                            idTrack: t.id,
                            forceDevice: false, useCloudFront: true, forcePreview: false, extraLife: true
                        )
                        api.getTrackUrl(trackRequest: relReq) { res in
                            defer { group.leave() }
                            guard let signed = try? res.get() else { return }
                            results[index] = self.queueEntry(from: t, signedUrl: signed.signedUrl, parent: parentContext, index: index + 1)
                        }
                    }
                    group.notify(queue: .main) {
                        var queue: [[String: Any]] = []
                        if let selected = selectedEntry { queue.append(selected) }
                        queue.append(contentsOf: results.compactMap { $0 })
                        guard !queue.isEmpty else {
                            print("[CarPlay] Track radio: no tracks to play")
                            return
                        }
                        self.musicPlayer.setCurrentParentContext([
                            "id": parentContext.id, "type": parentContext.type, "name": parentContext.name,
                            "trackData": trackDict
                        ])
                        self.isNowPlayingShown = false
                        self.musicPlayer.updateQueue(queue, selectedTrackId: trackId, persist: true)
                        self.musicPlayer.play()
                    }
                case .failure(let error):
                    print("[CarPlay] Track radio: related tracks failed: \(error.localizedDescription)")
                    // Fallback: play just the selected track
                    if let selected = selectedEntry {
                        DispatchQueue.main.async {
                            self.musicPlayer.setCurrentParentContext([
                                "id": parentContext.id, "type": parentContext.type, "name": parentContext.name,
                                "trackData": trackDict
                            ])
                            self.isNowPlayingShown = false
                            self.musicPlayer.updateQueue([selected], selectedTrackId: trackId, persist: true)
                            self.musicPlayer.play()
                        }
                    }
                }
            }
        }
    }

    /// Station radio: fetch tracks from station endpoint
    private func handleStationRadio(stationId: String, stationName: String, stationDict: [String: Any]) {
        let api: MusicApi = MusicApiImpl()
        let parentContext = QueueParentContext(id: stationId, type: "RADIO", name: stationName)

        api.getRadioTracks(stationId: stationId, count: 15, lastIdAlbumTrack: nil) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let tracks):
                print("[CarPlay] Station radio: \(tracks.count) tracks fetched")
                let shuffled = tracks.shuffled()
                // Resolve signed URLs
                let group = DispatchGroup()
                var results: [[String: Any]?] = Array(repeating: nil, count: shuffled.count)
                for (index, t) in shuffled.enumerated() {
                    group.enter()
                    let req = TrackRequest(
                        idAlbumTrack: String(t.idAlbumTrack ?? 0),
                        idTrack: t.id,
                        forceDevice: false, useCloudFront: true, forcePreview: false, extraLife: true
                    )
                    api.getTrackUrl(trackRequest: req) { res in
                        defer { group.leave() }
                        guard let signed = try? res.get() else { return }
                        results[index] = self.queueEntry(from: t, signedUrl: signed.signedUrl, parent: parentContext, index: index)
                    }
                }
                group.notify(queue: .main) {
                    let queue = results.compactMap { $0 }
                    guard !queue.isEmpty else {
                        print("[CarPlay] Station radio: no tracks to play")
                        return
                    }
                    self.musicPlayer.setCurrentParentContext([
                        "id": parentContext.id, "type": parentContext.type, "name": parentContext.name,
                        "tagData": stationDict
                    ])
                    self.isNowPlayingShown = false
                    let firstData = queue.first?["data"] as? [String: Any]
                    let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
                    self.musicPlayer.updateQueue(queue, selectedTrackId: selectedId, persist: true)
                    self.musicPlayer.play()
                }
            case .failure(let error):
                print("[CarPlay] Station radio: failed: \(error.localizedDescription)")
            }
        }
    }

    /// Artist radio: top tracks of artist, shuffled
    private func handleArtistRadio(artistId: String, artistName: String) {
        let parentContext = QueueParentContext(id: artistId, type: "ARTIST_STATION", name: artistName)
        fetchTracksRemote(mediaType: "artist", itemId: artistId, parentContext: parentContext) { [weak self] queueItems in
            guard let self = self, !queueItems.isEmpty else {
                print("[CarPlay] Artist radio: no tracks found for artist \(artistName)")
                return
            }
            let shuffled = queueItems.shuffled()
            self.musicPlayer.setCurrentParentContext([
                "id": parentContext.id, "type": parentContext.type, "name": parentContext.name
            ])
            self.isNowPlayingShown = false
            let firstData = shuffled.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(shuffled, selectedTrackId: selectedId, persist: true)
            self.musicPlayer.play()
        }
    }

    // MARK: - Action Items (Phase 7: Play All / Shuffle)

    /// Build "Play All" and "Shuffle" action items for drill-down lists (mirrors Android buildActionItems)
    private func buildActionItems(mediaType: String, itemId: String, parentTitle: String) -> [CPListItem] {
        let playItem = CPListItem(text: "\u{25B6} Play", detailText: parentTitle)
        if #available(iOS 14.0, *) {
            playItem.setImage(UIImage(systemName: "play.fill"))
        }
        playItem.handler = { [weak self] _, completion in
            guard let self = self else { completion(); return }
            print("[CarPlay] Action: Play All mediaType=\(mediaType) id=\(itemId)")
            self.fetchAndPlayAll(mediaType: mediaType, itemId: itemId, parentTitle: parentTitle, shuffle: false)
            completion()
        }

        let shuffleItem = CPListItem(text: "\u{21C6} Shuffle", detailText: parentTitle)
        if #available(iOS 14.0, *) {
            shuffleItem.setImage(UIImage(systemName: "shuffle"))
        }
        shuffleItem.handler = { [weak self] _, completion in
            guard let self = self else { completion(); return }
            print("[CarPlay] Action: Shuffle mediaType=\(mediaType) id=\(itemId)")
            self.fetchAndPlayAll(mediaType: mediaType, itemId: itemId, parentTitle: parentTitle, shuffle: true)
            completion()
        }

        return [playItem, shuffleItem]
    }

    /// Fetch all tracks and start playback (with optional shuffle)
    private func fetchAndPlayAll(mediaType: String, itemId: String, parentTitle: String, shuffle: Bool) {
        let parentContext = buildParentContext(mediaType: mediaType, itemId: itemId, parentTitle: parentTitle)
        fetchTracksRemote(mediaType: mediaType, itemId: itemId, parentContext: parentContext) { [weak self] remote in
            guard let self = self, !remote.isEmpty else {
                print("[CarPlay] fetchAndPlayAll: no tracks found")
                return
            }
            let queue = shuffle ? remote.shuffled() : remote
            self.musicPlayer.setCurrentParentContext([
                "id": parentContext.id, "type": parentContext.type, "name": parentContext.name
            ])
            self.isNowPlayingShown = false
            let firstData = queue.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(queue, selectedTrackId: selectedId, persist: true)
            self.musicPlayer.play()
        }
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
        case "playlist", "mix":
            api.getPlayListTracks(playListId: itemId, limit: 50, offset: 0) { result in
                guard let container = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                let tracks = container.tracks.items.map { $0.track }
                print("[CarPlay][remote] playlist id=\(itemId) rawTracks=\(tracks.count)")
                resolveSignedUrls(from: tracks, parent: parentContext, completion: completion)
            }
        case "album":
            api.getAlbumTracks(albumId: itemId, limit: 50, offset: 0) { result in
                guard let album = try? result.get() else { DispatchQueue.main.async { completion([]) }; return }
                print("[CarPlay][remote] album id=\(itemId) rawTracks=\(album.tracks.items.count)")
                resolveSignedUrls(from: album.tracks.items, parent: parentContext, completion: completion)
            }
        case "artist":
            api.getArtistTracks(artistId: itemId, order: "popularity", limit: 50, offset: 0) { result in
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

    @objc func isConnected() -> Bool {
        // Check both our internal state and the actual scene connection
        let sceneConnected = UIApplication.shared.connectedScenes.contains { scene in
            scene is CPTemplateApplicationScene
        }
        // Update internal state if out of sync
        if sceneConnected != connected {
            connected = sceneConnected
        }
        return connected
    }
    
    // Called when the queue has been reloaded and CarPlay UI needs to refresh
    @objc func refreshQueueUI() {
        guard let controller = interfaceController else {
            print("[CarPlay] refreshQueueUI: No interface controller available")
            return
        }
        print("[CarPlay] refreshQueueUI: Rebuilding templates with new queue")
        setupTemplates(controller)
    }

    /// Refresh the CarPlay navigation tree.
    /// This reloads navigation data from JSON files and rebuilds the CarPlay templates.
    /// Equivalent to Android's MusicLibraryService.refreshNavigation()
    @objc func refreshNavigation() {
        print("[CarPlay] refreshNavigation: Starting navigation refresh")
        guard let controller = interfaceController else {
            print("[CarPlay] refreshNavigation: No interface controller available")
            return
        }
        guard connected else {
            print("[CarPlay] refreshNavigation: CarPlay not connected, skipping refresh")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("[CarPlay] refreshNavigation: Rebuilding templates with updated data")
            self.setupTemplates(controller)
            print("[CarPlay] refreshNavigation: Navigation refresh completed")
        }
    }

    // MARK: - Login Detection

    /// Check if user is logged in by looking for REFRESH_TOKEN_KEY in UserDefaults
    /// Mirrors Android's MediaItemTree.isUserLoggedIn() which checks NativeStorage SharedPreferences
    private func isUserLoggedIn() -> Bool {
        // NativeStorage stores values as quoted strings in UserDefaults
        if let refreshToken = UserDefaults.standard.string(forKey: "REFRESH_TOKEN_KEY") {
            let cleaned = refreshToken.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isLoggedIn = !cleaned.isEmpty && cleaned != "null"
            print("[CarPlay] isUserLoggedIn: refreshToken=\(isLoggedIn ? "present" : "null/empty"), isLoggedIn=\(isLoggedIn)")
            return isLoggedIn
        }
        print("[CarPlay] isUserLoggedIn: no REFRESH_TOKEN_KEY found, isLoggedIn=false")
        return false
    }

    /// Show a "login required" template when user is not authenticated
    private func setupLoginRequiredTemplate(_ controller: CPInterfaceController) {
        print("[CarPlay] setupLoginRequiredTemplate: showing login required message")
        let loginItem = CPListItem(
            text: "Inicia sesión en la app",
            detailText: "Para usar CarPlay, abre la app e inicia sesión"
        )
        if #available(iOS 15.0, *) {
            loginItem.isEnabled = false
        }
        let section = CPListSection(items: [loginItem])
        let loginList = CPListTemplate(title: "Sesión requerida", sections: [section])
        loginList.tabTitle = "Inicio"
        if #available(iOS 13.0, *) {
            loginList.tabImage = UIImage(systemName: "person.crop.circle.badge.exclamationmark")
        }

        let tabBar = CPTabBarTemplate(templates: [loginList])
        tabBar.delegate = self
        DispatchQueue.main.async {
            controller.setRootTemplate(tabBar, animated: true, completion: { success, error in
                if let error = error { print("[CarPlay] setRootTemplate(Login) error: \(error)") }
                else { print("[CarPlay] setRootTemplate(Login) success: \(success)") }
            })
        }
    }

    // MARK: - CPTemplateApplicationSceneDelegate
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        print("[CarPlay] didConnect: interfaceController received - starting sequential setup")
        connected = true
        isRootTemplateSet = false  // Reset flag
        self.interfaceController = interfaceController

        // STEP 1: Present loading placeholder and WAIT for completion
        // This ensures root template is set before any push operations
        presentLoadingPlaceholder(interfaceController) { [weak self] in
            guard let self = self else { return }
            print("[CarPlay] didConnect: STEP 1 complete - root template set")

            // STEP 2: Activate the music player for CarPlay (registers remote command handlers)
            // This captures the existing playback state but does NOT auto-play
            self.musicPlayer.activateForCarPlay()
            print("[CarPlay] didConnect: STEP 2 complete - CarPlay activated")

            // STEP 3: Notify JS BEFORE loading queue
            // This gives the JS side a chance to pause the app's player
            print("[CarPlay] didConnect: STEP 3 - notifying JS of connection")
            NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": true])

            // STEP 4: Wait 0.2s for JS to process and pause app's player
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                print("[CarPlay] didConnect: STEP 4 - delay complete, proceeding with queue load")

                // STEP 5: Reload queue from storage (without auto-play due to isInitialCarPlaySetup flag)
                self.musicPlayer.reloadQueueForced()
                print("[CarPlay] didConnect: STEP 5 complete - queue reloaded")

                // STEP 6: Build and set the real templates
                self.setupTemplates(interfaceController)
                print("[CarPlay] didConnect: STEP 6 complete - templates set up")

                // STEP 7: Complete initial setup - this enables normal playback behavior
                // and applies the captured playback state (seek + resume if was playing)
                self.musicPlayer.completeInitialSetup()
                print("[CarPlay] didConnect: STEP 7 complete - initial setup finished")
            }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
        print("[CarPlay] didDisconnect")
        connected = false
        isRootTemplateSet = false  // Reset flag on disconnect
        // Deactivate the music player for CarPlay (removes remote command handlers)
        self.musicPlayer.deactivateForCarPlay()
        NotificationCenter.default.post(name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil, userInfo: ["connected": false])
        self.interfaceController = nil
    }

    // MARK: - Templates
    private func presentLoadingPlaceholder(_ controller: CPInterfaceController, completion: @escaping () -> Void) {
        let loadingItem = CPListItem(text: "Initializing…", detailText: nil)
        if #available(iOS 15.0, *) {
            loadingItem.isEnabled = false
        }
        let section = CPListSection(items: [loadingItem])
        let loadingList = CPListTemplate(title: "Loading", sections: [section])
        loadingList.tabTitle = "Loading"
        let placeholder = CPTabBarTemplate(templates: [loadingList])
        DispatchQueue.main.async { [weak self] in
            controller.setRootTemplate(placeholder, animated: false, completion: { [weak self] success, error in
                if let error = error {
                    print("[CarPlay] setRootTemplate(Loading) error: \(error)")
                } else {
                    print("[CarPlay] setRootTemplate(Loading) success: \(success)")
                    self?.isRootTemplateSet = true
                }
                completion()
            })
        }
    }
    private func setupTemplates(_ controller: CPInterfaceController) {
      print("[CarPlay] setupTemplates: begin")

      // Check network availability - if offline, show offline library
      let isOnline = CDVNetworkUtils.shared.isNetworkAvailable
      print("[CarPlay] setupTemplates: network available = \(isOnline)")

      if !isOnline {
          print("[CarPlay] setupTemplates: OFFLINE MODE - showing offline library")
          setupOfflineTemplates(controller)
          return
      }

      // Check login state - show login required template if not authenticated
      if !isUserLoggedIn() {
          let autoNavigation = CDVPlaylistProvider.loadNavigationFromJSON()
          if autoNavigation.isEmpty {
              print("[CarPlay] setupTemplates: NOT LOGGED IN and no navigation data - showing login template")
              setupLoginRequiredTemplate(controller)
              return
          }
          // If navigation data exists (e.g. from a previous session), proceed normally
          print("[CarPlay] setupTemplates: NOT LOGGED IN but navigation data exists, proceeding")
      }

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

                // If children are sections (have "items" key), build browsable subsections (applies to LIBRARY, HOME, etc.)
                let isSectionBased = children.first?["items"] != nil
                if isSectionBased {
                    if fileName == "AUTO_NAVIGATION_LIBRARY" {
                        // Library: show subsection titles that drill down into items
                        var topItems: [CPListItem] = []
                        for (sidx, subSection) in children.enumerated() {
                            let subTitle = (subSection["text"] as? String) ?? "Section \(sidx+1)"
                            let subItems = subSection["items"] as? [[String: Any]] ?? []
                            let li = CPListItem(text: subTitle, detailText: "\(subItems.count) items")
                            if #available(iOS 13.0, *) {
                                if let sfImage = librarySubsectionImage(for: subTitle) {
                                    li.setImage(sfImage)
                                }
                            }
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
                    } else if #available(iOS 14.0, *) {
                        // Home and other section-based files
                        // First section: CPListImageRowItem with thumbnails
                        // Other sections: CPListItem with disclosure indicator
                        var sectionListItems: [CPListTemplateItem] = []
                        for (sidx, subSection) in children.enumerated() {
                            let subTitle = (subSection["text"] as? String) ?? "Section \(sidx+1)"
                            let subItems = subSection["items"] as? [[String: Any]] ?? []
                            if subItems.isEmpty { continue }

                            if sidx == 0 {
                                // First section (Quick Access): image row with thumbnails
                                let maxGrid = Int(CPMaximumNumberOfGridImages)
                                let previewItems = Array(subItems.prefix(min(4, maxGrid)))
                                let placeholder = UIImage(systemName: "music.note") ?? UIImage()

                                // Load images synchronously (file://, local offline, cache)
                                var images: [UIImage] = []
                                for itemDict in previewItems {
                                    let urlStr = self.extractImageURL(from: itemDict)
                                    let itemType = (itemDict["itemType"] as? String) ?? (itemDict["type"] as? String)
                                    let itemId = String(describing: itemDict["id"] ?? "")
                                    var loaded: UIImage? = nil

                                    // Try local offline image
                                    if let t = itemType, !t.isEmpty, !itemId.isEmpty {
                                        loaded = CDVLocalStorageUtils.getLocalImage(itemType: t.lowercased(), itemId: itemId)
                                    }
                                    // Try file:// URL
                                    if loaded == nil, let s = urlStr, let url = URL(string: s), url.isFileURL {
                                        loaded = UIImage(contentsOfFile: url.path)
                                    }
                                    // Try memory cache
                                    if loaded == nil, let s = urlStr, let url = URL(string: s), !url.isFileURL {
                                        loaded = self.listImageCache.object(forKey: url as NSURL)
                                    }
                                    images.append(loaded ?? placeholder)
                                }

                                let imageRow = CPListImageRowItem(text: subTitle, images: images)

                                // Title tap -> navigate to full section list
                                imageRow.handler = { [weak self] _, completion in
                                    guard let self, let controller = self.interfaceController else { completion(); return }
                                    print("[CarPlay] [NAV][HOME] open section title=\(subTitle) items=\(subItems.count)")
                                    let leafItems = self.makeListItems(from: subItems, parentTitle: subTitle)
                                    let section = CPListSection(items: leafItems)
                                    let next = CPListTemplate(title: subTitle, sections: [section])
                                    DispatchQueue.main.async {
                                        self.isNowPlayingShown = false
                                        controller.pushTemplate(next, animated: true)
                                        completion()
                                    }
                                }

                                // Image tap -> play that specific item
                                imageRow.listImageRowHandler = { [weak self] _, index, completion in
                                    guard let self, index < previewItems.count else { completion(); return }
                                    let itemDict = previewItems[index]
                                    let id = String(describing: itemDict["id"] ?? "")
                                    let mediaType = (itemDict["itemType"] as? String) ?? (itemDict["type"] as? String) ?? ""
                                    let name = (itemDict["name"] as? String) ?? (itemDict["title"] as? String) ?? "Item"
                                    print("[CarPlay] [NAV][HOME] image tapped index=\(index) id=\(id) type=\(mediaType) name=\(name)")
                                    self.handleHomeItemTap(id: id, mediaType: mediaType, name: name, itemDict: itemDict)
                                    completion()
                                }

                                sectionListItems.append(imageRow)
                            } else {
                                // Other sections: title with disclosure indicator, no icon
                                let li = CPListItem(text: subTitle, detailText: nil)
                                li.accessoryType = .disclosureIndicator
                                li.handler = { [weak self] _, completion in
                                    guard let self, let controller = self.interfaceController else { completion(); return }
                                    print("[CarPlay] [NAV][HOME] open section title=\(subTitle) items=\(subItems.count)")
                                    let leafItems = self.makeListItems(from: subItems, parentTitle: subTitle)
                                    let section = CPListSection(items: leafItems)
                                    let next = CPListTemplate(title: subTitle, sections: [section])
                                    DispatchQueue.main.async {
                                        self.isNowPlayingShown = false
                                        controller.pushTemplate(next, animated: true)
                                        completion()
                                    }
                                }
                                sectionListItems.append(li)
                            }
                        }
                        if !sectionListItems.isEmpty {
                            cpSections.append(CPListSection(items: sectionListItems))
                        }
                        print("[CarPlay] [NAV] section-based file=\(fileName) produced \(sectionListItems.count) tappable sections")
                    } else {
                        // Fallback for iOS < 14: simple list items
                        var topItems: [CPListItem] = []
                        for (sidx, subSection) in children.enumerated() {
                            let subTitle = (subSection["text"] as? String) ?? "Section \(sidx+1)"
                            let subItems = subSection["items"] as? [[String: Any]] ?? []
                            if subItems.isEmpty { continue }
                            let li = CPListItem(text: subTitle, detailText: "\(subItems.count) items")
                            li.handler = { [weak self] _, completion in
                                guard let self, let controller = self.interfaceController else { completion(); return }
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
                        if !topItems.isEmpty {
                            cpSections.append(CPListSection(items: topItems))
                        }
                    }
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
            if #available(iOS 13.0, *) { cpList.tabImage = carPlayTabImage(from: sectionIcon, sectionTitle: sectionTitle, fileName: fileName) }
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
                if #available(iOS 13.0, *) { list.tabImage = carPlayTabImage(from: nil, sectionTitle: "Playlists", fileName: nil) }
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
                        let itemType = (itemDict["itemType"] as? String) ?? (itemDict["type"] as? String)
                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            print("[CarPlay] [LIB][WARN] item with empty name. keys=\(Array(itemDict.keys))")
                        }
                        let listItem = CPListItem(text: name, detailText: subtitle)
                        let itemImage = (itemDict["artwork"] as? String) ?? (itemDict["image"] as? String) ?? (itemDict["icon"] as? String)
                        if let itemImage, !itemImage.isEmpty { print("[CarPlay][IMG] library item image URL: \(itemImage)") }
                        setListItemImage(listItem, from: itemImage, itemType: itemType, itemId: pid, itemDict: itemDict)
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
                    if #available(iOS 13.0, *) { cpList.tabImage = carPlayTabImage(from: nil, sectionTitle: title, fileName: nil) }
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
            if #available(iOS 13.0, *) { list.tabImage = carPlayTabImage(from: nil, sectionTitle: "Browse", fileName: nil) }
            navTemplates.append(list)
        }

        // Add Search tab
        let searchTab = buildSearchTab()
        navTemplates.append(searchTab)
        
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
        // CPTabBarTemplate allows a maximum of 4 tabs — truncate if needed.
        let tabTemplates: [CPTemplate] = Array(navTemplates.prefix(4))
        if navTemplates.count > 4 {
            print("[CarPlay][WARN] Truncated \(navTemplates.count) tabs to 4 (CarPlay max)")
        }

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

        // Remove previous observer before adding to prevent duplicates on reconnect
        NotificationCenter.default.removeObserver(self, name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showNowPlayingTemplate), name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        print("[CarPlay] setupTemplates: end")
    }

    // MARK: - Search Tab
    /// Build a search tab with Siri assistant cell (like Spotify)
    /// Uses CPAssistantCellConfiguration (iOS 15+) to trigger Siri when tapped
    private func buildSearchTab() -> CPListTemplate {
        print("[CarPlay] buildSearchTab: creating search tab")
        
        // Empty section - the assistant cell is added via CPAssistantCellConfiguration
        let emptySection = CPListSection(items: [])
        
        var searchTemplate: CPListTemplate
        
        // Use CPAssistantCellConfiguration to add Siri button (iOS 15+)
        if #available(iOS 15.0, *) {
            // Configure assistant cell - this triggers Siri when tapped (like Spotify)
            let assistantConfig = CPAssistantCellConfiguration(
                position: .top,
                visibility: .always,
                assistantAction: .playMedia
            )
            
            searchTemplate = CPListTemplate(
                title: "Buscar",
                sections: [emptySection],
                assistantCellConfiguration: assistantConfig
            )
            print("[CarPlay] buildSearchTab: using CPAssistantCellConfiguration for Siri button")
        } else {
            // Fallback for iOS 14 - just show instructions
            let siriSearchItem = CPListItem(
                text: "Pídele a Siri",
                detailText: "reproducir audio"
            )
            let siriSection = CPListSection(items: [siriSearchItem])
            searchTemplate = CPListTemplate(title: "Buscar", sections: [siriSection])
            print("[CarPlay] buildSearchTab: iOS 14 fallback - showing instructions only")
        }
        
        searchTemplate.tabTitle = "Buscar"
        if #available(iOS 13.0, *) {
            searchTemplate.tabImage = UIImage(systemName: "magnifyingglass")
        }
        
        return searchTemplate
    }
    
    // MARK: - Offline Mode Templates
    /// Setup templates for offline mode - shows downloaded albums and playlists
    private func setupOfflineTemplates(_ controller: CPInterfaceController) {
        print("[CarPlay] setupOfflineTemplates: begin")

        let offlineItems = CDVPlaylistProvider.loadOfflineLibrary()
        print("[CarPlay] setupOfflineTemplates: loaded \(offlineItems.count) offline items")

        var listItems: [CPListItem] = []

        if offlineItems.isEmpty {
            // No offline content available - show a message
            let emptyItem = CPListItem(text: "No hay contenido offline", detailText: "Descarga música para escuchar sin conexión")
            if #available(iOS 15.0, *) {
                emptyItem.isEnabled = false
            }
            listItems.append(emptyItem)
        } else {
            // Build list items for each offline album/playlist
            for item in offlineItems {
                let title = CDVPlaylistProvider.getOfflineItemTitle(item)
                let subtitle = CDVPlaylistProvider.getOfflineItemSubtitle(item)
                let itemId = CDVPlaylistProvider.getOfflineItemId(item)
                let itemType = CDVPlaylistProvider.getOfflineItemType(item)
                let imageUrl = CDVPlaylistProvider.getOfflineItemImageUrl(item)

                print("[CarPlay] setupOfflineTemplates: adding item type=\(itemType) id=\(itemId) title=\(title)")

                let listItem = CPListItem(text: title, detailText: subtitle)

                // Set image - try local first, then remote
                setListItemImage(listItem, from: imageUrl, itemType: itemType, itemId: itemId, itemDict: item)

                // Handler to load and play tracks from this album/playlist
                listItem.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    print("[CarPlay] Offline item selected: type=\(itemType) id=\(itemId) title=\(title)")

                    // Load tracks for this item from local storage
                    self.loadOfflineTracksAndPlay(itemType: itemType, itemId: itemId, itemDict: item)
                    completion()
                }

                listItems.append(listItem)
            }
        }

        // Create the offline library section
        let section = CPListSection(items: listItems, header: "Biblioteca Offline", sectionIndexTitle: nil)
        let offlineList = CPListTemplate(title: "Sin conexión", sections: [section])
        offlineList.tabTitle = "Offline"

        // Try to set an offline icon
        if #available(iOS 13.0, *) {
            offlineList.tabImage = UIImage(systemName: "arrow.down.circle.fill")
        }

        // Configure Now Playing template
        let now = CPNowPlayingTemplate.shared
        musicPlayer.setNowPlayingTemplate(now)

        // Set as root template (single tab for offline mode)
        let tabBar = CPTabBarTemplate(templates: [offlineList])
        tabBar.delegate = self

        print("[CarPlay] setupOfflineTemplates: presenting TabBar with offline library")
        DispatchQueue.main.async {
            controller.setRootTemplate(tabBar, animated: true, completion: { success, error in
                if let error = error { print("[CarPlay] setRootTemplate(Offline) error: \(error)") }
                else { print("[CarPlay] setRootTemplate(Offline) success: \(success)") }
            })
            self.isNowPlayingShown = false
        }

        // Remove previous observer before adding to prevent duplicates on reconnect
        NotificationCenter.default.removeObserver(self, name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showNowPlayingTemplate), name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        print("[CarPlay] setupOfflineTemplates: end")
    }

    /// Load tracks for an offline album or playlist and start playback
    private func loadOfflineTracksAndPlay(itemType: String, itemId: String, itemDict: [String: Any], fromSiri: Bool = false) {
        print("[CarPlay] loadOfflineTracksAndPlay: type=\(itemType) id=\(itemId) fromSiri=\(fromSiri)")

        // Load tracks from OFFLINE_TRACKS file filtered by album/playlist ID
        // This mirrors the Android implementation in MediaItemTree.loadOfflineTracksByMediaTypeMediaId
        var tracks = CDVPlaylistProvider.loadOfflineTracks(itemType: itemType, itemId: itemId)
        print("[CarPlay] loadOfflineTracksAndPlay: loaded \(tracks.count) tracks from OFFLINE_TRACKS")

        guard !tracks.isEmpty else {
            print("[CarPlay] loadOfflineTracksAndPlay: no tracks found for \(itemType) \(itemId)")
            return
        }

        // Normalize and play
        let normalized = normalizeQueueItems(tracks)
        print("[CarPlay] loadOfflineTracksAndPlay: normalized \(normalized.count) tracks")

        if !normalized.isEmpty {
            self.isNowPlayingShown = false
            let selectedId = normalized.first?["idAlbumTrack"] as? String ?? normalized.first?["id"] as? String
            self.musicPlayer.updateQueue(normalized, selectedTrackId: selectedId, persist: true, fromNative: fromSiri)
            self.musicPlayer.play()
        }
    }

    // MARK: - Siri Search
    
    /// Handle Siri search intent - performs API search and starts playback
    /// Called from CDVSiriIntentHandler when user says "Hey Siri, play X on AppName"
    @objc func handleSiriSearch(searchParams: [String: Any]) {
        let mediaName = searchParams["mediaName"] as? String ?? ""
        let artistName = searchParams["artistName"] as? String
        let albumName = searchParams["albumName"] as? String
        let mediaType = searchParams["mediaType"] as? Int ?? 0
        
        print("🎤 [CarPlay][Siri] handleSiriSearch called")
        print("🎤 [CarPlay][Siri] mediaName='\(mediaName)' artistName='\(artistName ?? "nil")' albumName='\(albumName ?? "nil")' mediaType=\(mediaType)")
        
        // Ensure remote command center is set up for Siri-initiated playback
        // This is important because Siri can trigger playback before CarPlay UI fully connects
        musicPlayer.activateForCarPlay()
        // Clear initial setup flag immediately since this is direct Siri playback
        musicPlayer.clearInitialSetupFlag()
        
        // Build search query - combine available parameters
        var searchQuery = mediaName
        if let artist = artistName, !artist.isEmpty {
            searchQuery = "\(artist) \(searchQuery)"
        }
        if let album = albumName, !album.isEmpty {
            searchQuery = "\(searchQuery) \(album)"
        }
        
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [CarPlay][Siri] Empty search query, cannot search")
            return
        }
        
        print("🔍 [CarPlay][Siri] Searching for: '\(searchQuery)'")
        
        // Check network availability
        guard CDVNetworkUtils.shared.isNetworkAvailable else {
            print("⚠️ [CarPlay][Siri] No network available, searching offline")
            searchOffline(query: searchQuery)
            return
        }
        
        // Perform API search
        let api: MusicApi = MusicApiImpl()
        api.search(text: searchQuery, limit: 30) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                print("✅ [CarPlay][Siri] Search successful")
                self.processSiriSearchResults(response: response, originalQuery: mediaName, artistHint: artistName)
                
            case .failure(let error):
                print("❌ [CarPlay][Siri] Search failed: \(error.localizedDescription)")
                // Try offline search as fallback
                self.searchOffline(query: searchQuery)
            }
        }
    }
    
    /// Process search results and start playback
    private func processSiriSearchResults(response: SearchResponse, originalQuery: String, artistHint: String?) {
        print("🎵 [CarPlay][Siri] Processing search results...")
        print("🎵 [CarPlay][Siri] tracks=\(response.tracks?.list?.count ?? 0) artists=\(response.artists?.list?.count ?? 0) albums=\(response.albums?.list?.count ?? 0) playlists=\(response.playlists?.list?.count ?? 0)")
        
        // Strategy: Prioritize based on what was found
        // 1. If tracks found, play tracks directly
        // 2. If artist found matching the query, fetch artist tracks
        // 3. If album found, fetch album tracks
        // 4. If playlist found, fetch playlist tracks
        
        let queryLower = originalQuery.lowercased()
        
        // Check for "best" result first (from Android logic)
        if let best = response.best {
            print("🌟 [CarPlay][Siri] Found best result: \(best.name ?? "unknown") (type=\(best.itemType ?? "unknown"), id=\(best.id))")
            playBestResult(best: best)
            return
        }
        
        // Check for tracks first - if we have tracks, play them
        if let tracks = response.tracks?.list, !tracks.isEmpty {
            print("🎵 [CarPlay][Siri] Found \(tracks.count) tracks, building queue...")
            buildQueueFromTracks(tracks: tracks, contextName: "Siri Search: \(originalQuery)")
            return
        }
        
        // Check for matching artist
        if let artists = response.artists?.list, !artists.isEmpty {
            // Find best matching artist
            let matchingArtist = artists.first { artist in
                artist.name.lowercased().contains(queryLower) || queryLower.contains(artist.name.lowercased())
            } ?? artists.first
            
            if let artist = matchingArtist {
                print("🎤 [CarPlay][Siri] Found artist: \(artist.name) (id=\(artist.id)), fetching tracks...")
                fetchArtistTracksAndPlay(artistId: artist.id, artistName: artist.name)
                return
            }
        }
        
        // Check for matching album
        if let albums = response.albums?.list, !albums.isEmpty {
            let matchingAlbum = albums.first { album in
                album.title.lowercased().contains(queryLower) || queryLower.contains(album.title.lowercased())
            } ?? albums.first
            
            if let album = matchingAlbum {
                print("💿 [CarPlay][Siri] Found album: \(album.title) (id=\(album.id)), fetching tracks...")
                fetchAlbumTracksAndPlay(albumId: album.id, albumName: album.title)
                return
            }
        }
        
        // Check for matching playlist
        if let playlists = response.playlists?.list, !playlists.isEmpty {
            let matchingPlaylist = playlists.first { playlist in
                playlist.name.lowercased().contains(queryLower) || queryLower.contains(playlist.name.lowercased())
            } ?? playlists.first
            
            if let playlist = matchingPlaylist {
                print("📋 [CarPlay][Siri] Found playlist: \(playlist.name) (id=\(playlist.id)), fetching tracks...")
                fetchPlaylistTracksAndPlay(playlistId: playlist.id, playlistName: playlist.name)
                return
            }
        }
        
        print("[CarPlay][Siri] No suitable results found for '\(originalQuery)'")
    }

    // MARK: - Grouped Search Results (Phase 8)

    /// Build a CPListTemplate with grouped search results (mirrors Android MediaItemTree.search())
    /// Called from CarPlay UI search, NOT from Siri (Siri continues with auto-play)
    private func buildSearchResultsTemplate(response: SearchResponse, query: String) -> CPListTemplate {
        var sections: [CPListSection] = []
        let maxPerSection = 4

        // Best Result
        if let best = response.best {
            let bestItem = CPListItem(text: best.name ?? "...", detailText: best.itemType ?? "")
            bestItem.handler = { [weak self] _, completion in
                guard let self = self else { completion(); return }
                self.playBestResult(best: best)
                completion()
            }
            sections.append(CPListSection(items: [bestItem], header: "Mejor resultado", sectionIndexTitle: nil))
        }

        // Artists
        if let artists = response.artists?.list?.prefix(maxPerSection), !artists.isEmpty {
            let items = artists.map { artist -> CPListItem in
                let li = CPListItem(text: artist.name, detailText: "Artista")
                li.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    self.fetchArtistTracksAndPlay(artistId: artist.id, artistName: artist.name)
                    completion()
                }
                return li
            }
            sections.append(CPListSection(items: items, header: "Artistas", sectionIndexTitle: nil))
        }

        // Albums
        if let albums = response.albums?.list?.prefix(maxPerSection), !albums.isEmpty {
            let items = albums.map { album -> CPListItem in
                let artistName = album.artists?.first?.name ?? "Album"
                let li = CPListItem(text: album.title, detailText: artistName)
                li.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    self.fetchAlbumTracksAndPlay(albumId: album.id, albumName: album.title)
                    completion()
                }
                return li
            }
            sections.append(CPListSection(items: items, header: "Albums", sectionIndexTitle: nil))
        }

        // Playlists
        if let playlists = response.playlists?.list?.prefix(maxPerSection), !playlists.isEmpty {
            let items = playlists.map { playlist -> CPListItem in
                let li = CPListItem(text: playlist.name, detailText: "Playlist")
                li.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    self.fetchPlaylistTracksAndPlay(playlistId: playlist.id, playlistName: playlist.name)
                    completion()
                }
                return li
            }
            sections.append(CPListSection(items: items, header: "Playlists", sectionIndexTitle: nil))
        }

        // Tags
        if let tags = response.tags?.list?.prefix(maxPerSection), !tags.isEmpty {
            let items = tags.map { tag -> CPListItem in
                let li = CPListItem(text: tag.name, detailText: "Tag")
                li.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    let parentContext = QueueParentContext(id: tag.id, type: "TAG", name: tag.name)
                    self.fetchTracksRemote(mediaType: "tag", itemId: tag.id, parentContext: parentContext) { remote in
                        if !remote.isEmpty {
                            self.musicPlayer.setCurrentParentContext([
                                "id": parentContext.id, "type": parentContext.type, "name": parentContext.name
                            ])
                            self.isNowPlayingShown = false
                            let firstData = remote.first?["data"] as? [String: Any]
                            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
                            self.musicPlayer.updateQueue(remote, selectedTrackId: selectedId, persist: true)
                            self.musicPlayer.play()
                        }
                    }
                    completion()
                }
                return li
            }
            sections.append(CPListSection(items: items, header: "Tags", sectionIndexTitle: nil))
        }

        // Tracks
        if let tracks = response.tracks?.list?.prefix(maxPerSection), !tracks.isEmpty {
            let items = tracks.map { track -> CPListItem in
                let artistName = track.artists.first?.name ?? ""
                let li = CPListItem(text: track.name, detailText: artistName)
                li.handler = { [weak self] _, completion in
                    guard let self = self else { completion(); return }
                    self.handleTrackTap(trackId: track.id, trackName: track.name)
                    completion()
                }
                return li
            }
            sections.append(CPListSection(items: items, header: "Canciones", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            let emptyItem = CPListItem(text: "Sin resultados", detailText: "Intenta con otra busqueda")
            if #available(iOS 15.0, *) { emptyItem.isEnabled = false }
            sections.append(CPListSection(items: [emptyItem]))
        }

        return CPListTemplate(title: "Resultados: \(query)", sections: sections)
    }

    /// Perform a search from CarPlay UI and show grouped results (not from Siri)
    @objc func showSearchResults(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard CDVNetworkUtils.shared.isNetworkAvailable else {
            print("[CarPlay] showSearchResults: no network available")
            return
        }
        let api: MusicApi = MusicApiImpl()
        api.search(text: query, limit: 30) { [weak self] result in
            guard let self = self, let controller = self.interfaceController else { return }
            switch result {
            case .success(let response):
                let resultsTemplate = self.buildSearchResultsTemplate(response: response, query: query)
                DispatchQueue.main.async {
                    controller.pushTemplate(resultsTemplate, animated: true)
                }
            case .failure(let error):
                print("[CarPlay] showSearchResults: search failed: \(error.localizedDescription)")
            }
        }
    }

    /// Build queue from track list and start playback
    private func buildQueueFromTracks(tracks: [Track], contextName: String) {
        print("🎵 [CarPlay][Siri] Building queue from \(tracks.count) tracks...")
        
        let api: MusicApi = MusicApiImpl()
        let group = DispatchGroup()
        var queueItems: [[String: Any]?] = Array(repeating: nil, count: tracks.count)
        
        let parentContext = QueueParentContext(id: "0", type: "SEARCH", name: contextName)
        
        for (index, track) in tracks.enumerated() {
            group.enter()
            let req = TrackRequest(
                idAlbumTrack: String(track.idAlbumTrack ?? 0),
                idTrack: track.id,
                forceDevice: false,
                useCloudFront: true,
                forcePreview: false,
                extraLife: true
            )
            api.getTrackUrl(trackRequest: req) { [weak self] result in
                defer { group.leave() }
                guard let self = self, let signed = try? result.get() else { return }
                let entry = self.queueEntry(from: track, signedUrl: signed.signedUrl, parent: parentContext, index: index)
                queueItems[index] = entry
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let validItems = queueItems.compactMap { $0 }
            
            if validItems.isEmpty {
                print("⚠️ [CarPlay][Siri] No valid tracks to play after URL resolution")
                return
            }
            
            print("✅ [CarPlay][Siri] Queue built with \(validItems.count) tracks, starting playback...")
            self.isNowPlayingShown = false
            let firstData = validItems.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(validItems, selectedTrackId: selectedId, persist: true, fromNative: true)
            self.musicPlayer.play()
        }
    }
    
    /// Fetch artist tracks and start playback
    private func fetchArtistTracksAndPlay(artistId: String, artistName: String) {
        let parentContext = QueueParentContext(id: artistId, type: "ARTIST", name: artistName)
        fetchTracksRemote(mediaType: "artist", itemId: artistId, parentContext: parentContext) { [weak self] queueItems in
            guard let self = self, !queueItems.isEmpty else {
                print("⚠️ [CarPlay][Siri] No tracks found for artist \(artistName)")
                return
            }
            print("✅ [CarPlay][Siri] Loaded \(queueItems.count) tracks for artist \(artistName)")
            self.isNowPlayingShown = false
            let firstData = queueItems.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(queueItems, selectedTrackId: selectedId, persist: true, fromNative: true)
            self.musicPlayer.play()
        }
    }
    
    /// Fetch album tracks and start playback
    private func fetchAlbumTracksAndPlay(albumId: String, albumName: String) {
        let parentContext = QueueParentContext(id: albumId, type: "ALBUM", name: albumName)
        fetchTracksRemote(mediaType: "album", itemId: albumId, parentContext: parentContext) { [weak self] queueItems in
            guard let self = self, !queueItems.isEmpty else {
                print("⚠️ [CarPlay][Siri] No tracks found for album \(albumName)")
                return
            }
            print("✅ [CarPlay][Siri] Loaded \(queueItems.count) tracks for album \(albumName)")
            self.isNowPlayingShown = false
            let firstData = queueItems.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(queueItems, selectedTrackId: selectedId, persist: true, fromNative: true)
            self.musicPlayer.play()
        }
    }
    
    /// Play the "best" result from search (can be artist, album, playlist, track, or tag)
    private func playBestResult(best: AnyMediaItem) {
        let itemType = best.itemType ?? ""
        let itemId = best.id
        let itemName = best.name ?? "Unknown"
        
        print("🌟 [CarPlay][Siri] Playing best result: type=\(itemType) id=\(itemId) name=\(itemName)")
        
        switch itemType.lowercased() {
        case "artist":
            fetchArtistTracksAndPlay(artistId: itemId, artistName: itemName)
        case "album":
            fetchAlbumTracksAndPlay(albumId: itemId, albumName: itemName)
        case "playlist":
            fetchPlaylistTracksAndPlay(playlistId: itemId, playlistName: itemName)
        case "track":
            // For a single track, we need to fetch it and play
            fetchSingleTrackAndPlay(trackId: itemId, trackName: itemName)
        case "tag":
            // For tags, fetch playlists from the tag
            fetchTagPlaylistsAndPlay(tagId: itemId, tagName: itemName)
        default:
            print("⚠️ [CarPlay][Siri] Unknown best result type: \(itemType)")
        }
    }
    
    /// Fetch a single track and play it
    private func fetchSingleTrackAndPlay(trackId: String, trackName: String) {
        print("🎵 [CarPlay][Siri] Fetching single track: \(trackName) (id=\(trackId))")
        
        let api: MusicApi = MusicApiImpl()
        let req = TrackRequest(
            idAlbumTrack: trackId,
            idTrack: trackId,
            forceDevice: false,
            useCloudFront: true,
            forcePreview: false,
            extraLife: true
        )
        
        api.getTrackUrl(trackRequest: req) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let signed):
                print("✅ [CarPlay][Siri] Got signed URL for track")
                // Create a simple queue entry for the single track
                let parentContext = QueueParentContext(id: "0", type: "SEARCH", name: "Siri: \(trackName)")
                let entry: [String: Any] = [
                    "data": [
                        "id": trackId,
                        "idAlbumTrack": trackId,
                        "name": trackName,
                        "signedUrl": signed.signedUrl,
                        "indice": 0,
                        "context": [
                            "id": parentContext.id,
                            "type": parentContext.type,
                            "name": parentContext.name
                        ]
                    ] as [String : Any]
                ]
                
                DispatchQueue.main.async {
                    self.isNowPlayingShown = false
                    self.musicPlayer.updateQueue([entry], selectedTrackId: trackId, persist: true, fromNative: true)
                    self.musicPlayer.play()
                }
                
            case .failure(let error):
                print("❌ [CarPlay][Siri] Failed to get track URL: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch playlists from a tag and play the first one
    private func fetchTagPlaylistsAndPlay(tagId: String, tagName: String) {
        print("🏷️ [CarPlay][Siri] Fetching playlists for tag: \(tagName) (id=\(tagId))")
        
        let api: MusicApi = MusicApiImpl()
        api.getTagPlaylists(tagId: tagId) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let playlists):
                if let firstPlaylist = playlists.first,
                   let playlistId = firstPlaylist["id"] as? String ?? (firstPlaylist["id"] as? Int).map({ String($0) }),
                   let playlistName = firstPlaylist["name"] as? String {
                    print("✅ [CarPlay][Siri] Found \(playlists.count) playlists for tag, playing first: \(playlistName)")
                    self.fetchPlaylistTracksAndPlay(playlistId: playlistId, playlistName: playlistName)
                } else {
                    print("⚠️ [CarPlay][Siri] No playlists found for tag \(tagName)")
                }
            case .failure(let error):
                print("❌ [CarPlay][Siri] Failed to get tag playlists: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch playlist tracks and start playback
    private func fetchPlaylistTracksAndPlay(playlistId: String, playlistName: String) {
        let parentContext = QueueParentContext(id: playlistId, type: "PLAYLIST", name: playlistName)
        fetchTracksRemote(mediaType: "playlist", itemId: playlistId, parentContext: parentContext) { [weak self] queueItems in
            guard let self = self, !queueItems.isEmpty else {
                print("⚠️ [CarPlay][Siri] No tracks found for playlist \(playlistName)")
                return
            }
            print("✅ [CarPlay][Siri] Loaded \(queueItems.count) tracks for playlist \(playlistName)")
            self.isNowPlayingShown = false
            let firstData = queueItems.first?["data"] as? [String: Any]
            let selectedId = firstData?["idAlbumTrack"] as? String ?? firstData?["id"] as? String
            self.musicPlayer.updateQueue(queueItems, selectedTrackId: selectedId, persist: true, fromNative: true)
            self.musicPlayer.play()
        }
    }
    
    /// Search offline content when network is unavailable
    private func searchOffline(query: String) {
        print("🔍 [CarPlay][Siri] Searching offline for: '\(query)'")
        
        let queryLower = query.lowercased()
        let offlineItems = CDVPlaylistProvider.loadOfflineLibrary()
        
        // Find matching offline items
        let matchingItem = offlineItems.first { item in
            let title = CDVPlaylistProvider.getOfflineItemTitle(item).lowercased()
            return title.contains(queryLower) || queryLower.contains(title)
        }
        
        guard let item = matchingItem else {
            print("⚠️ [CarPlay][Siri] No matching offline content found for '\(query)'")
            return
        }
        
        let itemType = CDVPlaylistProvider.getOfflineItemType(item)
        let itemId = CDVPlaylistProvider.getOfflineItemId(item)
        let itemTitle = CDVPlaylistProvider.getOfflineItemTitle(item)
        
        print("✅ [CarPlay][Siri] Found offline match: \(itemTitle) (type=\(itemType), id=\(itemId))")
        
        // Load and play offline tracks (fromSiri: true to notify JS about native queue update)
        loadOfflineTracksAndPlay(itemType: itemType, itemId: itemId, itemDict: item, fromSiri: true)
    }

    @objc private func showNowPlayingTemplate() {
      guard let controller = interfaceController else {
        print("[CarPlay] showNowPlayingTemplate: interfaceController nil")
        return
      }

      // CRITICAL: Don't try to push template if root template isn't set yet
      // This prevents the crash: "Attempting to push a template without a root template"
      guard isRootTemplateSet else {
        print("[CarPlay] showNowPlayingTemplate: root template not set yet, skipping")
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

