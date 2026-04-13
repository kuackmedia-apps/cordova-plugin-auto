import Foundation
import Intents
import MediaPlayer

/// Handles Siri intents for music playback
/// Detects voice commands like "Hey Siri, play Shakira on Brisamusic"
@available(iOS 13.0, *)
@objc(CDVSiriIntentHandler)
class CDVSiriIntentHandler: NSObject, INPlayMediaIntentHandling {
    
    // Singleton instance
    @objc static let shared = CDVSiriIntentHandler()
    
    private override init() {
        super.init()
    }

    /// Stores the last resolved Track from search, consumed by handle() for rich playback data (album, images, artists)
    private var lastResolvedTrack: Track?

    // MARK: - INPlayMediaIntentHandling
    
    /// Called when Siri receives a play media command.
    /// If resolveMediaItems succeeded, intent.mediaItems contains the resolved item
    /// and we play it directly. Otherwise falls back to handleSiriSearch.
    @objc func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        // Build search params for JS notification
        let isCarPlayConnected = CDVAutoMusicPlugin.sharedInstance()?.carPlayManager?.isConnected() ?? false
        var searchParams: [String: Any] = [:]

        if let mediaSearch = intent.mediaSearch {
            if let mediaName = mediaSearch.mediaName { searchParams["mediaName"] = mediaName }
            if let artistName = mediaSearch.artistName { searchParams["artistName"] = artistName }
            if let albumName = mediaSearch.albumName { searchParams["albumName"] = albumName }
            searchParams["mediaType"] = mediaSearch.mediaType.rawValue
        }
        searchParams["isCarPlayConnected"] = isCarPlayConnected

        // Check if we have a resolved media item from resolveMediaItems
        if let mediaItem = intent.mediaItems?.first,
           let identifier = mediaItem.identifier {
            // Parse identifier — format is "type:id" or "track:id:idAlbumTrack"
            let parts = identifier.split(separator: ":")
            if parts.count >= 2 {
                let mediaType = String(parts[0])
                let itemId = String(parts[1])
                let idAlbumTrack = parts.count >= 3 ? String(parts[2]) : nil
                let itemName = mediaItem.title ?? ""

                let resolvedTrack = self.lastResolvedTrack
                self.lastResolvedTrack = nil

                DispatchQueue.main.async {
                    // Notify JS about the Siri search (JS handles playback when CarPlay is NOT connected)
                    if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                        plugin.handleSiriSearchFromIntent(searchParams: searchParams)
                    }
                    // Only play via native CarPlay player when CarPlay is actually connected.
                    // When CarPlay is NOT connected, JS will handle playback through its normal
                    // player + MusicControls2 flow via the handleSiriSearchFromIntent callback.
                    if isCarPlayConnected, let carPlayManager = CDVAutoMusicPlugin.sharedInstance()?.carPlayManager {
                        if mediaType == "track", let track = resolvedTrack {
                            carPlayManager.playSiriResolvedTrack(track)
                        } else {
                            carPlayManager.playSiriResolvedMedia(mediaType: mediaType, itemId: itemId, itemName: itemName, idAlbumTrack: idAlbumTrack)
                        }
                    }
                }

                let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
                completion(response)
                return
            }
        }

        // Fallback: no resolved items (offline, API error, or resolve returned .notRequired)
        DispatchQueue.main.async {
            if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                // Always notify JS (JS handles playback when CarPlay is NOT connected)
                plugin.handleSiriSearchFromIntent(searchParams: searchParams)

                // Only perform native search+playback when CarPlay is connected
                if isCarPlayConnected, let carPlayManager = plugin.carPlayManager {
                    carPlayManager.handleSiriSearch(searchParams: searchParams)
                }
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name("CDVPendingSiriIntent"),
                    object: nil,
                    userInfo: searchParams
                )
            }
        }

        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completion(response)
    }
    
    // MARK: - Resolution methods (REQUIRED for Siri to work properly)
    
    /// Confirm the intent can be handled
    @objc func confirm(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        // Return ready to play - this confirms we can handle the request
        let response = INPlayMediaIntentResponse(code: .ready, userActivity: nil)
        completion(response)
    }
    
    /// Resolve media items by searching the catalog using type-specific endpoints.
    /// Uses mediaSearch.mediaType to pick the right /search/{type} endpoint.
    /// Siri uses the returned INMediaItem to speak "Here's [title] on [App]".
    @objc func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        self.lastResolvedTrack = nil

        guard let mediaSearch = intent.mediaSearch else {
            completion([.unsupported()])
            return
        }

        let mediaName = mediaSearch.mediaName ?? ""
        let artistName = mediaSearch.artistName
        let albumName = mediaSearch.albumName
        let mediaType = mediaSearch.mediaType

        // If offline, skip resolve — let handle() deal with offline search
        guard CDVNetworkUtils.shared.isNetworkAvailable else {
            completion([.notRequired()])
            return
        }

        let api: MusicApi = MusicApiImpl()

        switch mediaType {
        case .song:
            let query = buildQuery(primary: mediaName, secondary: artistName)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveAsTrack(api: api, query: query, completion: completion)

        case .artist:
            let query = (artistName ?? mediaName).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveAsArtist(api: api, query: query, completion: completion)

        case .album:
            let primary = albumName ?? mediaName
            let query = buildQuery(primary: primary, secondary: artistName)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveAsAlbum(api: api, query: query, completion: completion)

        case .playlist:
            let query = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveAsPlaylist(api: api, query: query, completion: completion)

        case .genre:
            let query = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveAsGenre(api: api, query: query, completion: completion)

        default:
            // .unknown, .music, .podcastShow, etc — generic search
            let query = buildQuery(primary: mediaName, secondary: artistName)
            guard !query.isEmpty else { completion([.unsupported()]); return }
            resolveGeneric(api: api, query: query, completion: completion)
        }
    }

    // MARK: - Query building

    /// Builds "{primary} {secondary}" trimmed, skipping nil/empty parts
    private func buildQuery(primary: String?, secondary: String?) -> String {
        let parts = [primary, secondary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    // MARK: - Type-specific resolvers

    private func resolveAsTrack(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.searchTracks(text: query, limit: 5) { [weak self] result in
            switch result {
            case .success(let trackResult):
                if let t = trackResult.list?.first {
                    self?.lastResolvedTrack = t
                    let artistStr = t.artists.first?.name
                    let idAlbumTrack = t.idAlbumTrack.map { String($0) } ?? t.id
                    let item = INMediaItem(identifier: "track:\(t.id):\(idAlbumTrack)", title: t.name, type: .song, artwork: nil, artist: artistStr)
                    completion([.success(with: item)])
                    return
                }
                // Fallback to generic search
                self?.resolveGeneric(api: api, query: query, completion: completion)
            case .failure(let error):
                print("❌ [SiriIntentHandler] searchTracks failed: \(error.localizedDescription), falling back to generic")
                self?.resolveGeneric(api: api, query: query, completion: completion)
            }
        }
    }

    private func resolveAsArtist(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.searchArtists(text: query, limit: 5) { [weak self] result in
            switch result {
            case .success(let artistResult):
                if let a = artistResult.list?.first {
                    let item = INMediaItem(identifier: "artist:\(a.id)", title: a.name, type: .artist, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                self?.resolveGeneric(api: api, query: query, completion: completion)
            case .failure(let error):
                print("❌ [SiriIntentHandler] searchArtists failed: \(error.localizedDescription), falling back to generic")
                self?.resolveGeneric(api: api, query: query, completion: completion)
            }
        }
    }

    private func resolveAsAlbum(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.searchAlbums(text: query, limit: 5) { [weak self] result in
            switch result {
            case .success(let albumResult):
                if let a = albumResult.list?.first {
                    let artistStr = a.artists?.first?.name
                    let item = INMediaItem(identifier: "album:\(a.id)", title: a.title, type: .album, artwork: nil, artist: artistStr)
                    completion([.success(with: item)])
                    return
                }
                self?.resolveGeneric(api: api, query: query, completion: completion)
            case .failure(let error):
                print("❌ [SiriIntentHandler] searchAlbums failed: \(error.localizedDescription), falling back to generic")
                self?.resolveGeneric(api: api, query: query, completion: completion)
            }
        }
    }

    private func resolveAsPlaylist(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.searchPlaylists(text: query, limit: 5) { [weak self] result in
            switch result {
            case .success(let playlistResult):
                if let p = playlistResult.list?.first {
                    let item = INMediaItem(identifier: "playlist:\(p.id)", title: p.name, type: .playlist, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                self?.resolveGeneric(api: api, query: query, completion: completion)
            case .failure(let error):
                print("❌ [SiriIntentHandler] searchPlaylists failed: \(error.localizedDescription), falling back to generic")
                self?.resolveGeneric(api: api, query: query, completion: completion)
            }
        }
    }

    private func resolveAsGenre(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.searchTags(text: query, limit: 5) { [weak self] result in
            switch result {
            case .success(let tagResult):
                if let tag = tagResult.list?.first {
                    let item = INMediaItem(identifier: "tag:\(tag.id)", title: tag.name, type: .genre, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                self?.resolveGeneric(api: api, query: query, completion: completion)
            case .failure(let error):
                print("❌ [SiriIntentHandler] searchTags failed: \(error.localizedDescription), falling back to generic")
                self?.resolveGeneric(api: api, query: query, completion: completion)
            }
        }
    }

    // MARK: - Generic fallback resolver

    /// Generic search using /search endpoint. Priority: playlists > artists > albums > tags > tracks
    private func resolveGeneric(api: MusicApi, query: String, completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        api.search(text: query, limit: 10) { result in
            switch result {
            case .success(let response):
                if let p = response.playlists?.list?.first {
                    let item = INMediaItem(identifier: "playlist:\(p.id)", title: p.name, type: .playlist, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                if let a = response.artists?.list?.first {
                    let item = INMediaItem(identifier: "artist:\(a.id)", title: a.name, type: .artist, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                if let a = response.albums?.list?.first {
                    let artistStr = a.artists?.first?.name
                    let item = INMediaItem(identifier: "album:\(a.id)", title: a.title, type: .album, artwork: nil, artist: artistStr)
                    completion([.success(with: item)])
                    return
                }
                if let tag = response.tags?.list?.first {
                    let item = INMediaItem(identifier: "tag:\(tag.id)", title: tag.name, type: .genre, artwork: nil)
                    completion([.success(with: item)])
                    return
                }
                if let t = response.tracks?.list?.first {
                    self.lastResolvedTrack = t
                    let artistStr = t.artists.first?.name
                    let idAlbumTrack = t.idAlbumTrack.map { String($0) } ?? t.id
                    let item = INMediaItem(identifier: "track:\(t.id):\(idAlbumTrack)", title: t.name, type: .song, artwork: nil, artist: artistStr)
                    completion([.success(with: item)])
                    return
                }

                completion([.unsupported()])

            case .failure(let error):
                print("❌ [SiriIntentHandler] Generic search failed: \(error.localizedDescription), deferring to handle()")
                completion([.notRequired()])
            }
        }
    }

    /// Resolve playback speed
    @objc func resolvePlaybackSpeed(for intent: INPlayMediaIntent, with completion: @escaping (INPlayMediaPlaybackSpeedResolutionResult) -> Void) {
        completion(.notRequired())
    }

    /// Resolve shuffle mode
    @objc func resolvePlayShuffled(for intent: INPlayMediaIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
        completion(.notRequired())
    }

    /// Resolve repeat mode
    @objc func resolveResumePlayback(for intent: INPlayMediaIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
        completion(.notRequired())
    }
}
