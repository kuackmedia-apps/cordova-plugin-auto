import Foundation
import AVFoundation
import MediaPlayer
import CarPlay
import UIKit

@objc(CDVMusicPlayer)
class CDVMusicPlayer: NSObject {
    private weak var manager: CDVCarPlayManager?

    @objc var player: AVPlayer = AVPlayer()
    @objc var queue: [[String: Any]] = []
    @objc var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private var nowPlayingTemplate: CPNowPlayingTemplate?
    private var timeObserverToken: Any?
    private let artworkCache = NSCache<NSURL, UIImage>()
    private var forceClearOnNextApply: Bool = false
    private var lastQueueModifiedDate: Date?
    private var debugTimer: Timer?
    private var lastKnownTrackId: String?

    // Flag to prevent auto-play during initial CarPlay setup
    // This prevents double playback (plugin's AVPlayer + app's AVPlayer playing simultaneously)
    // The flag is set in activateForCarPlay() and cleared after initial setup completes
    private(set) var isInitialCarPlaySetup: Bool = false

    // Pending start position (ms) to apply when AVPlayerItem becomes ready
    // This is needed because for streaming tracks, the signed URL loads asynchronously
    // and replaces the AVPlayerItem, which resets position to 0
    private var pendingStartPositionMs: Double = 0

    // Helper to extract the nested 'data' field from a queue item
    private func extractTrackData(_ item: [String: Any]) -> [String: Any] {
        return CDVQueueStorage.extractFlattenedData(item)
    }

    @objc var currentTrack: [String: Any]? {
        guard currentIndex < queue.count else { return nil }
        return extractTrackData(queue[currentIndex])
    }

    @objc init(manager: CDVCarPlayManager) {
        self.manager = manager
        super.init()
        setupAudioSession()
        // NOTE: Do NOT call setupRemoteCommandCenter() or startDebugMonitoring() here!
        // These should only be called when CarPlay is connected to avoid conflicts
        // with cordova-plugin-music-controls2 which also registers MPRemoteCommandCenter handlers.
        // Call activateForCarPlay() when CarPlay connects and deactivateForCarPlay() when it disconnects.
    }

    deinit {
        debugTimer?.invalidate()
        debugTimer = nil
    }

    private func startDebugMonitoring() {
        debugTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.logStoredTrackInfo()
        }
    }

    private func logStoredTrackInfo() {
        let resolvedId = CDVQueueStorage.currentTrackId()

        // Detect if current_track changed and sync currentIndex
        if let resolvedId, resolvedId != lastKnownTrackId {
            print("[CDVMusicPlayer] Track change detected: \(lastKnownTrackId ?? "none") -> \(resolvedId)")
            lastKnownTrackId = resolvedId
            syncCurrentIndexToTrackId(resolvedId)
        }
    }

    private func syncCurrentIndexToTrackId(_ trackId: String) {
        guard !queue.isEmpty else { return }

        // Search for the track in the queue by idAlbumTrack or id
        if let idx = queue.firstIndex(where: { item in
            guard let data = item["data"] as? [String: Any] else { return false }
            let idAlbumTrack = stringValue(data["idAlbumTrack"])
            let id = stringValue(data["id"])
            return idAlbumTrack == trackId || id == trackId
        }) {
            if idx != currentIndex {
                let trackData = queue[idx]["data"] as? [String: Any]
                let trackName = trackData?["name"] as? String ?? "Unknown"
                print("[CDVMusicPlayer] Synced to track: \(trackName) (index \(idx))")
                currentIndex = idx
                loadCurrentTrack()
                // Seek to 0 when mobile app changes tracks
                player.seek(to: .zero)
                updateNowPlayingInfo()
                // Store the current track ID in the same format as mobile app
                CDVQueueStorage.setCurrentTrackId(trackId)
                // Notify JavaScript about the track change from mobile app
                let currentTrack = queue[currentIndex]
                NotificationCenter.default.post(
                    name: Notification.Name("CDVMediaTrackChanged"),
                    object: nil,
                    userInfo: ["track": currentTrack]
                )
            }
        } else {
            // Track not found in current queue - mobile app may have changed playlists
            print("[CDVMusicPlayer] Track ID \(trackId) not found in current queue, reloading queue from disk...")
            reloadQueueForced()

            // Try again with the newly loaded queue
            if let idx = queue.firstIndex(where: { item in
                guard let data = item["data"] as? [String: Any] else { return false }
                let idAlbumTrack = stringValue(data["idAlbumTrack"])
                let id = stringValue(data["id"])
                return idAlbumTrack == trackId || id == trackId
            }) {
                let trackData = queue[idx]["data"] as? [String: Any]
                let trackName = trackData?["name"] as? String ?? "Unknown"
                print("[CDVMusicPlayer] Found track after queue reload: \(trackName) (index \(idx))")
                currentIndex = idx
                loadCurrentTrack()
                updateNowPlayingInfo()
                CDVQueueStorage.setCurrentTrackId(trackId)

                // Notify manager to update CarPlay UI with new queue
                manager?.refreshQueueUI()
            } else {
                print("[CDVMusicPlayer] Warning: Track ID \(trackId) still not found after queue reload")
            }
        }
    }

    @objc func setNowPlayingTemplate(_ template: CPNowPlayingTemplate) {
        self.nowPlayingTemplate = template
    }

    // Request a one-time clear to force UI refresh on next metadata apply
    @objc func requestNowPlayingClearRefresh() {
        forceClearOnNextApply = true
    }

    // Indicates whether the current AVPlayerItem is ready to play.
    @objc func isCurrentItemReady() -> Bool {
        return player.currentItem?.status == .readyToPlay
    }

    // MARK: - Playback
    @objc func play() {
        let hadItem = (player.currentItem != nil)
        if !hadItem { print("[CDVMusicPlayer][diag] play(): currentItem is nil -> calling loadCurrentTrack()") }
        if player.currentItem == nil { loadCurrentTrack() }
        print("[CDVMusicPlayer][diag] play(): invoking AVPlayer.play(); queue.count=\(queue.count) index=\(currentIndex)")
        player.play()
        isPlaying = true
        startPeriodicUpdates()
        updateNowPlayingInfoIfNeeded()
        MPNowPlayingInfoCenter.default().playbackState = .playing
        print("[CDVMusicPlayer][diag] play(): posted playbackState=.playing and CDVShowNowPlayingTemplate")
        NotificationCenter.default.post(name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
        // Notify JavaScript about playing state
        NotificationCenter.default.post(
            name: Notification.Name("CDVPlaybackStateChanged"),
            object: nil,
            userInfo: ["action": "play"]
        )
        persistQueueState()
    }

    @objc func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfoIfNeeded()
        MPNowPlayingInfoCenter.default().playbackState = .paused
        // Notify JavaScript about pause
        NotificationCenter.default.post(
            name: Notification.Name("CDVPlaybackStateChanged"),
            object: nil,
            userInfo: ["action": "pause"]
        )
    }
    @objc func togglePlayPause() { isPlaying ? pause() : play() }

    /// Syncs currentIndex to the given trackId and starts playback.
    /// This is called from playCurrentTrack() to ensure we play the correct track
    /// based on UserDefaults, similar to how Android Auto handles this.
    @objc func syncToTrackIdAndPlay(_ trackId: String) {
        print("[CDVMusicPlayer] syncToTrackIdAndPlay: trackId=\(trackId)")

        // Helper function to find track index - handles both nested and flat structures
        func findTrackIndex(_ searchId: String, in items: [[String: Any]]) -> Int? {
            return items.firstIndex(where: { item in
                // Try nested structure first: { "data": { "idAlbumTrack": "...", "id": "..." } }
                let data = (item["data"] as? [String: Any]) ?? item
                let idAlbumTrack = stringValue(data["idAlbumTrack"])
                let id = stringValue(data["id"])
                return idAlbumTrack == searchId || id == searchId
            })
        }

        // ALWAYS reload queue from disk when playCurrentTrack is called
        // This ensures we have the latest queue from the app
        print("[CDVMusicPlayer] syncToTrackIdAndPlay: reloading queue from disk")
        reloadQueueForced()

        guard !queue.isEmpty else {
            print("[CDVMusicPlayer] syncToTrackIdAndPlay: queue empty after reload, cannot play")
            return
        }

        // Find the track in the queue
        if let idx = findTrackIndex(trackId, in: queue) {
            let trackData = (queue[idx]["data"] as? [String: Any]) ?? queue[idx]
            let trackName = trackData["name"] as? String ?? trackData["title"] as? String ?? "Unknown"

            if idx != currentIndex {
                print("[CDVMusicPlayer] syncToTrackIdAndPlay: changing from index \(currentIndex) to \(idx) (\(trackName))")
                currentIndex = idx
                loadCurrentTrack()
                player.seek(to: .zero)
            } else {
                print("[CDVMusicPlayer] syncToTrackIdAndPlay: already at correct index \(idx) (\(trackName))")
                // Ensure track is loaded even if index matches
                if player.currentItem == nil {
                    loadCurrentTrack()
                }
            }

            // Update stored track ID
            CDVQueueStorage.setCurrentTrackId(trackId)
        } else {
            // Track not found by ID - use whatever currentIndex was resolved by reloadQueueForced
            print("[CDVMusicPlayer] syncToTrackIdAndPlay: trackId \(trackId) not found, using resolved currentIndex \(currentIndex)")

            // Ensure track is loaded
            if player.currentItem == nil || currentIndex < queue.count {
                loadCurrentTrack()
            }
        }

        // ALWAYS start playback if we have a valid queue
        // This is critical - the app expects playback to start
        print("[CDVMusicPlayer] syncToTrackIdAndPlay: starting playback")
        play()
    }

    @objc func skipToNext() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        loadCurrentTrack()
        // Explicitly seek to 0 to ensure position is reset
        player.seek(to: .zero)
        play()
        persistQueueState()
        // Update current_track in UserDefaults to sync with mobile app
        if let trackId = currentTrackIdForPersistence() {
            CDVQueueStorage.setCurrentTrackId(trackId)
        }
        // Notify JavaScript about the track change (for onMediaUpdate callback)
        let currentTrack = queue[currentIndex]
        NotificationCenter.default.post(
            name: Notification.Name("CDVMediaTrackChanged"),
            object: nil,
            userInfo: ["track": currentTrack]
        )
        // Also notify playback state change
        NotificationCenter.default.post(
            name: Notification.Name("CDVPlaybackStateChanged"),
            object: nil,
            userInfo: ["action": "skipToNext"]
        )
    }
    @objc func skipToPrevious() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadCurrentTrack()
        // Explicitly seek to 0 to ensure position is reset
        player.seek(to: .zero)
        play()
        persistQueueState()
        // Update current_track in UserDefaults to sync with mobile app
        if let trackId = currentTrackIdForPersistence() {
            CDVQueueStorage.setCurrentTrackId(trackId)
        }
        // Notify JavaScript about the track change (for onMediaUpdate callback)
        let currentTrack = queue[currentIndex]
        NotificationCenter.default.post(
            name: Notification.Name("CDVMediaTrackChanged"),
            object: nil,
            userInfo: ["track": currentTrack]
        )
        // Also notify playback state change
        NotificationCenter.default.post(
            name: Notification.Name("CDVPlaybackStateChanged"),
            object: nil,
            userInfo: ["action": "skipToPrevious"]
        )
    }

    @objc func seekToPosition(_ position: Double) { player.seek(to: CMTimeMakeWithSeconds(position / 1000.0, preferredTimescale: Int32(NSEC_PER_SEC))) }
    @objc func currentPlaybackPosition() -> Double {
        let secs = CMTimeGetSeconds(player.currentTime())
        return secs.isFinite ? secs * 1000.0 : 0.0
    }
    @objc func currentPlaybackState() -> String { isPlaying ? "PLAYING" : (player.currentItem != nil ? "PAUSED" : "STOPPED") }

    // MARK: - Queue
    @objc func updateQueue(_ queue: [[String: Any]]) {
        updateQueue(queue, selectedTrackId: nil, persist: true)
    }

    func updateQueue(_ queue: [[String: Any]], selectedTrackId: String?, persist: Bool = true) {
        print("[CDVMusicPlayer][diag] updateQueue(persist=\(persist)) selectedId=\(selectedTrackId ?? "<nil>") incomingCount=\(queue.count)")
        self.queue = queue

        guard !queue.isEmpty else {
            print("[CDVMusicPlayer][diag] updateQueue(): received empty queue")
            if persist { persistQueueState() }
            return
        }

        let persistedId = CDVQueueStorage.currentTrackId()
        let candidateId = stringValue(selectedTrackId) ?? stringValue(persistedId)

        if let candidateId,
           let idx = queue.firstIndex(where: { item in
               guard let data = item["data"] as? [String: Any] else { return false }
               let directId = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"])
               return directId == candidateId
           }) {
            currentIndex = idx
        } else {
            currentIndex = min(max(0, currentIndex), max(0, queue.count - 1))
        }

        let preview = queue.prefix(3).map { (item) -> String in
            guard let data = item["data"] as? [String: Any] else { return "<invalid>" }
            let title = (data["name"] as? String) ?? (data["title"] as? String) ?? "<untitled>"
            let idAlbum = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"]) ?? ""
            return idAlbum.isEmpty ? title : "\(title) [\(idAlbum)]"
        }.joined(separator: " | ")
        print("[CDVMusicPlayer][diag] updateQueue(): received \(queue.count) items firstItems=\(preview) selectedIdx=\(currentIndex)")

        loadCurrentTrack()
        updateNowPlayingInfo()
        if persist {
            persistQueueState()
            // Update current_track in UserDefaults to sync with mobile app
            if let trackId = currentTrackIdForPersistence() {
                CDVQueueStorage.setCurrentTrackId(trackId)
            }
            // Notify JavaScript about the queue/track change (for onMediaUpdate callback)
            let currentTrack = queue[currentIndex]
            NotificationCenter.default.post(
                name: Notification.Name("CDVMediaTrackChanged"),
                object: nil,
                userInfo: ["track": currentTrack]
            )
            print("[CDVMusicPlayer][diag] updateQueue(): posted CDVMediaTrackChanged notification")
        } else {
            if let currentId = currentTrackIdForPersistence() {
                print("[CDVMusicPlayer][diag] updateQueue(): persist=FALSE keeping host storage untouched (currentId=\(currentId))")
            } else {
                print("[CDVMusicPlayer][diag] updateQueue(): persist=FALSE keeping host storage untouched (no current id)")
            }
        }
    }
    @objc func reloadQueue() { reloadQueueInternal(force: false) }

    @objc func reloadQueueForced() { reloadQueueInternal(force: true) }

    private func reloadQueueInternal(force: Bool) {
        let status = CDVQueueStorage.queueFileStatus()
        let fileModifiedDate = status.attributes?[.modificationDate] as? Date
        let hasActiveItem = player.currentItem != nil || !queue.isEmpty
        let existingCurrentId = currentTrackIdForPersistence()

        if !force {
            if hasActiveItem {
                if let fileModifiedDate {
                    if let last = lastQueueModifiedDate, fileModifiedDate <= last {
                        let title = (currentTrack?["title"] as? String) ?? "<unknown>"
                        print("[CDVMusicPlayer][diag] reloadQueue(): skipping (queue already loaded) currentIndex=\(currentIndex) title=\(title) fileMTime=\(fileModifiedDate)")
                        updateNowPlayingInfoIfNeeded()
                        return
                    }
                    print("[CDVMusicPlayer][diag] reloadQueue(): detected newer queue file (mtime=\(fileModifiedDate)) -> refreshing")
                } else {
                    let title = (currentTrack?["title"] as? String) ?? "<unknown>"
                    print("[CDVMusicPlayer][diag] reloadQueue(): skipping (queue already loaded, no file mtime) currentIndex=\(currentIndex) title=\(title)")
                    updateNowPlayingInfoIfNeeded()
                    return
                }
            }
        }

        print("[CDVMusicPlayer][diag] reloadQueueInternal(force=\(force)) fileExists=\(status.exists) mtime=\(String(describing: fileModifiedDate)) path=\(status.path)")

        let (items, currentId, modifiedDate) = CDVQueueStorage.loadQueueFromDisk(usingAttributes: status.attributes)

        if items.isEmpty && !queue.isEmpty {
            print("[CDVMusicPlayer][diag] reloadQueue(): disk queue empty but in-memory queue has \(queue.count) items — preserving current state")
            updateNowPlayingInfoIfNeeded()
            return
        }

        if !force && hasActiveItem && !items.isEmpty {
            let candidateId = stringValue(currentId) ?? existingCurrentId
            if let candidateId, !candidateId.isEmpty {
                let containsCandidate = items.firstIndex(where: { item in
                    guard let data = item["data"] as? [String: Any] else { return false }
                    let directId = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"])
                    return directId == candidateId
                }) != nil
                if !containsCandidate {
                    let title = (currentTrack?["title"] as? String) ?? "<unknown>"
                    print("[CDVMusicPlayer][diag] reloadQueue(): skipping new file (no matching track id=\(candidateId)) currentTitle=\(title)")
                    updateNowPlayingInfoIfNeeded()
                    return
                }
            }
        }

        // Determine which index from the new file matches our current selection before mutating state.
        let resolvedIndex: Int = {
            let candidateId = stringValue(currentId) ?? existingCurrentId
            if let candidateId, !candidateId.isEmpty,
               let idx = items.firstIndex(where: { item in
                   guard let data = item["data"] as? [String: Any] else { return false }
                   let directId = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"])
                   return directId == candidateId
               }) {
                return idx
            }
            if let persisted = CDVQueueStorage.currentTrackId(),
               let idx = items.firstIndex(where: { item in
                   guard let data = item["data"] as? [String: Any] else { return false }
                   let directId = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"])
                   return directId == persisted
               }) {
                return idx
            }
            if let current = currentTrack,
               let existingId = stringValue(current["idAlbumTrack"]) ?? stringValue(current["id"]),
               let idx = items.firstIndex(where: { item in
                   guard let data = item["data"] as? [String: Any] else { return false }
                   let directId = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"])
                   return directId == existingId
               }) {
                return idx
            }
            return min(currentIndex, max(0, items.count - 1))
        }()

        self.queue = items
        self.currentIndex = resolvedIndex

        let formattedDate = modifiedDate.map { ISO8601DateFormatter().string(from: $0) } ?? "<nil>"
        print("[CDVMusicPlayer][diag] reloadQueue(force=\(force)): loaded=\(items.count) currentIndex=\(self.currentIndex) currentId=\(currentId ?? "<nil>") fileMTime=\(formattedDate)")

        if let modifiedDate {
            lastQueueModifiedDate = modifiedDate
        } else if let fileModifiedDate {
            lastQueueModifiedDate = fileModifiedDate
        }

        if !items.isEmpty {
            // Prepare current item and metadata without forcing playback
            loadCurrentTrack()
            updateNowPlayingInfo()
        } else {
            updateNowPlayingInfoIfNeeded()
        }
    }
    @objc func updateCurrentTrack() {
        // Read the new track ID from UserDefaults (set by the mobile app)
        guard let newTrackId = CDVQueueStorage.currentTrackId() else {
            print("[CDVMusicPlayer][diag] updateCurrentTrack(): no track ID in UserDefaults")
            return
        }

        // Check if the currently loaded track already matches - avoid reloading if same track
        // This preserves playback position during CarPlay connection (seamless transition)
        let currentLoadedId = currentTrackIdForPersistence()
        if currentLoadedId == newTrackId {
            print("[CDVMusicPlayer][diag] updateCurrentTrack(): track already matches (\(newTrackId)), skipping")
            return
        }

        print("[CDVMusicPlayer][diag] updateCurrentTrack(): changing track from \(currentLoadedId ?? "nil") to \(newTrackId)")

        // Sync currentIndex to the new track ID (this handles finding the track and loading it)
        syncCurrentIndexToTrackId(newTrackId)
    }

    // MARK: - Internals
    @objc func loadCurrentTrack() {
        guard currentIndex < queue.count else { print("[CDVMusicPlayer][diag] loadCurrentTrack(): currentIndex out of range — queue.count=\(queue.count) idx=\(currentIndex)"); return }
        // Extract flattened data from the nested structure
        let track = extractTrackData(queue[currentIndex])
        let title = (track["title"] as? String) ?? ""
        let artist = (track["artist"] as? String) ?? ""
        let album = (track["album"] as? String) ?? ""
        let explicitSource = (track["source"] as? String) ?? ""
        let fallbackSource = (track["filePath"] as? String) ?? (track["path"] as? String) ?? ""
        let effectiveSource = !explicitSource.isEmpty ? explicitSource : fallbackSource
        let trimmedSource = effectiveSource.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract track ID for local file lookup
        let idTrack = (track["id"] as? String) ?? String(describing: track["idTrack"] ?? "")
        let idAlbumTrack = (track["idAlbumTrack"] as? String) ?? String(describing: track["idAlbumTrack"] ?? "")

        print("[CDVMusicPlayer][diag] loadCurrentTrack(): idx=\(currentIndex) hasSource=\(!trimmedSource.isEmpty) title=\(title) artist=\(artist) album=\(album) idTrack=\(idTrack)")

        // PRIORITY 1: Check if track exists locally (offline mode)
        if !idTrack.isEmpty, let localPath = CDVLocalStorageUtils.getLocalTrackPath(idTrack) {
            let localUrl = URL(fileURLWithPath: localPath)
            print("[CDVMusicPlayer] Using LOCAL track: \(localPath)")
            let item = AVPlayerItem(url: localUrl)
            attachItemObservers(item)
            player.replaceCurrentItem(with: item)
            // IMPORTANT: Resume playback after replacing item - AVPlayer stops when item changes
            // BUT skip auto-play during initial CarPlay setup to prevent double playback
            if isPlaying && !isInitialCarPlaySetup { player.play(); startPeriodicUpdates() }
            return
        }

        // PRIORITY 2: Use explicit source URL if provided
        if !trimmedSource.isEmpty {
            let candidateURL: URL? = {
                if let remote = URL(string: trimmedSource), remote.scheme != nil {
                    return remote
                }
                return URL(fileURLWithPath: trimmedSource, isDirectory: false)
            }()

            if let url = candidateURL {
                let item = AVPlayerItem(url: url)
                attachItemObservers(item)
                player.replaceCurrentItem(with: item)
                print("[CDVMusicPlayer][diag] loadCurrentTrack(): replaced currentItem with URL=\(url.absoluteString.prefix(80))…")
                // IMPORTANT: Resume playback after replacing item - AVPlayer stops when item changes
                // BUT skip auto-play during initial CarPlay setup to prevent double playback
                if isPlaying && !isInitialCarPlaySetup { player.play(); startPeriodicUpdates() }
                return
            }
        }

        // PRIORITY 3: Fallback - resolve signed URL from API when we only have IDs
        if !idTrack.isEmpty {
            print("[CDVMusicPlayer] No local or source URL. Resolving signed URL for idTrack=\(idTrack) idAlbumTrack=\(idAlbumTrack)")
            let api: MusicApi = MusicApiImpl()
            let req = TrackRequest(
                idAlbumTrack: !idAlbumTrack.isEmpty ? idAlbumTrack : "0",
                idTrack: idTrack,
                forceDevice: false,
                useCloudFront: true,
                forcePreview: false,
                extraLife: false
            )
            api.getTrackUrl(trackRequest: req) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let resp):
                    let urlStr = resp.signedUrl
                    print("[CDVMusicPlayer] Resolved signed URL: \(urlStr.prefix(80))...")
                    if let url = URL(string: urlStr) {
                        DispatchQueue.main.async {
                            let item = AVPlayerItem(url: url)
                            self.attachItemObservers(item)
                            self.player.replaceCurrentItem(with: item)
                            print("[CDVMusicPlayer][diag] loadCurrentTrack(): replaced currentItem with signed URL (main-thread)")
                            // Skip auto-play during initial CarPlay setup to prevent double playback
                            if self.isPlaying && !self.isInitialCarPlaySetup { self.player.play(); self.startPeriodicUpdates() }
                            self.updateNowPlayingInfoIfNeeded()
                        }
                    }
                case .failure(let err):
                    print("[CDVMusicPlayer][ERROR] Failed to resolve track URL: \(err)")
                }
            }
        } else {
            print("[CDVMusicPlayer][WARN] Neither 'source' nor ids present to play current track.")
        }
    }

    @objc func nextTrack() { skipToNext() }
    @objc func previousTrack() { skipToPrevious() }

    @objc func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
        try? session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }


    private var isCarPlayActive: Bool = false
    private var commandTargets: [Any] = []

    /// Called when CarPlay connects - activates the remote command center and debug monitoring
    @objc func activateForCarPlay() {
        guard !isCarPlayActive else {
            print("[CDVMusicPlayer] activateForCarPlay: already active, skipping")
            return
        }
        print("[CDVMusicPlayer] activateForCarPlay: setting up remote commands and monitoring")

        // Mark that we're in initial setup - prevents auto-play in loadCurrentTrack()
        // This avoids double playback (plugin + app playing simultaneously)
        isInitialCarPlaySetup = true

        // NOTE: Start position is read from UserDefaults (START_POSITION_KEY)
        // which is written continuously by the mobile app's Player.js onMediaProgress.
        // The applyStartPositionFromUserDefaults() method in completeInitialSetup()
        // will handle seeking and resuming playback.

        isCarPlayActive = true
        setupRemoteCommandCenter()
        startDebugMonitoring()
    }

    /// Called when initial CarPlay setup is complete
    /// This clears the isInitialCarPlaySetup flag, allowing normal playback behavior
    @objc func completeInitialSetup() {
        guard isInitialCarPlaySetup else {
            print("[CDVMusicPlayer] completeInitialSetup: not in initial setup, skipping")
            return
        }
        print("[CDVMusicPlayer] completeInitialSetup: initial setup complete, enabling normal playback")
        isInitialCarPlaySetup = false

        // Read start position from UserDefaults and store in pendingStartPositionMs
        // The actual seek will ALWAYS happen in observeValue when the AVPlayerItem is ready
        // We never apply here because for streaming tracks, the signed URL loads asynchronously
        // and replaces the AVPlayerItem - even if current item shows "ready", it may be a placeholder
        readStartPositionFromUserDefaults()

        let itemStatus = player.currentItem?.status
        print("[CDVMusicPlayer] completeInitialSetup: player.currentItem?.status = \(String(describing: itemStatus)), pendingStartPositionMs = \(pendingStartPositionMs)")

        // Always defer to observeValue - never apply here because the "ready" item
        // might be a placeholder that will be replaced when signed URL resolves
        if pendingStartPositionMs > 0 {
            print("[CDVMusicPlayer] completeInitialSetup: will apply pendingStartPositionMs=\(pendingStartPositionMs) in observeValue when final item is ready")
        }
    }

    /// Reads START_POSITION_KEY from UserDefaults (written by mobile app's Player.js via NativeStorage)
    /// NativeStorage.setItem stores as String, so we need to read as String and convert
    /// Stores the value in pendingStartPositionMs and removes the key from UserDefaults
    private func readStartPositionFromUserDefaults() {
        // DEBUG: Log all keys to see what's in UserDefaults
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("POSITION") || $0.contains("START") }
        print("[CDVMusicPlayer][sync] UserDefaults keys containing POSITION/START: \(Array(allKeys))")

        // NativeStorage.setItem saves as String, so read as object first
        let rawValue = UserDefaults.standard.object(forKey: "START_POSITION_KEY")
        print("[CDVMusicPlayer][sync] START_POSITION_KEY raw value: \(String(describing: rawValue)) type: \(type(of: rawValue))")

        var startPositionMs: Double = 0

        // Handle different types that NativeStorage might store
        if let stringValue = rawValue as? String {
            print("[CDVMusicPlayer][sync] String value: '\(stringValue)' length=\(stringValue.count) bytes=\(Array(stringValue.utf8))")
            // Try parsing - if it fails, log the error
            if let parsed = Double(stringValue) {
                startPositionMs = parsed
                print("[CDVMusicPlayer][sync] Parsed from String: \(startPositionMs)ms")
            } else {
                print("[CDVMusicPlayer][sync] ERROR: Failed to parse '\(stringValue)' as Double")
                // Try trimming whitespace and newlines
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Double(trimmed) {
                    startPositionMs = parsed
                    print("[CDVMusicPlayer][sync] Parsed from trimmed String: \(startPositionMs)ms")
                } else {
                    // NativeStorage double-encodes strings with quotes, e.g. '"102208"'
                    // Strip the embedded quotes
                    let strippedQuotes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    print("[CDVMusicPlayer][sync] After stripping quotes: '\(strippedQuotes)'")
                    if let parsed = Double(strippedQuotes) {
                        startPositionMs = parsed
                        print("[CDVMusicPlayer][sync] Parsed after stripping quotes: \(startPositionMs)ms")
                    }
                }
            }
        } else if let doubleValue = rawValue as? Double {
            startPositionMs = doubleValue
            print("[CDVMusicPlayer][sync] Read as Double: \(startPositionMs)ms")
        } else if let intValue = rawValue as? Int {
            startPositionMs = Double(intValue)
            print("[CDVMusicPlayer][sync] Read as Int: \(startPositionMs)ms")
        } else if let numberValue = rawValue as? NSNumber {
            startPositionMs = numberValue.doubleValue
            print("[CDVMusicPlayer][sync] Read as NSNumber: \(startPositionMs)ms")
        }

        // Remove immediately to prevent re-reading on next call
        UserDefaults.standard.removeObject(forKey: "START_POSITION_KEY")
        UserDefaults.standard.synchronize()

        // Store in pending property - will be applied when AVPlayerItem is ready
        pendingStartPositionMs = startPositionMs
        print("[CDVMusicPlayer][sync] Stored pendingStartPositionMs = \(pendingStartPositionMs)")
    }

    /// Applies the pending start position by seeking to pendingStartPositionMs
    /// Called from observeValue when AVPlayerItem becomes readyToPlay
    private func applyPendingStartPosition() {
        guard pendingStartPositionMs > 0 else {
            print("[CDVMusicPlayer][sync] No pending startPosition to apply (value=\(pendingStartPositionMs))")
            return
        }

        let startPositionMs = pendingStartPositionMs
        pendingStartPositionMs = 0  // Clear immediately to prevent re-applying

        let startPositionSec = startPositionMs / 1000.0
        print("[CDVMusicPlayer][sync] ✅ Applying startPosition: \(String(format: "%.1f", startPositionSec))s (\(Int(startPositionMs))ms)")

        let targetTime = CMTime(seconds: startPositionSec, preferredTimescale: 1000)

        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }

            if finished {
                print("[CDVMusicPlayer][sync] ✅ Seek to startPosition completed: \(String(format: "%.1f", startPositionSec))s")
                self.updateNowPlayingInfo()

                // Auto-play after seeking to start position
                print("[CDVMusicPlayer][sync] ▶️ Starting playback after seek")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.play()
                }
            } else {
                print("[CDVMusicPlayer][sync] ⚠️ Seek to startPosition was interrupted")
            }
        }
    }

    /// Called when CarPlay disconnects - removes remote command center handlers and stops monitoring
    @objc func deactivateForCarPlay() {
        guard isCarPlayActive else {
            print("[CDVMusicPlayer] deactivateForCarPlay: already inactive, skipping")
            return
        }
        print("[CDVMusicPlayer] deactivateForCarPlay: removing remote commands and stopping monitoring")
        isCarPlayActive = false
        teardownRemoteCommandCenter()
        stopDebugMonitoring()
        // Pause playback when CarPlay disconnects to avoid ghost playback
        pause()
    }

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.nextTrackCommand.isEnabled = true
        cc.previousTrackCommand.isEnabled = true
        cc.togglePlayPauseCommand.isEnabled = true

        // Store targets so we can remove them later
        commandTargets.removeAll()
        commandTargets.append(cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success })
        commandTargets.append(cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success })
        commandTargets.append(cc.nextTrackCommand.addTarget { [weak self] _ in self?.skipToNext(); return .success })
        commandTargets.append(cc.previousTrackCommand.addTarget { [weak self] _ in self?.skipToPrevious(); return .success })
        commandTargets.append(cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success })
        print("[CDVMusicPlayer] setupRemoteCommandCenter: registered \(commandTargets.count) command targets")
    }

    private func teardownRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        // Remove all our registered targets
        for target in commandTargets {
            cc.playCommand.removeTarget(target)
            cc.pauseCommand.removeTarget(target)
            cc.nextTrackCommand.removeTarget(target)
            cc.previousTrackCommand.removeTarget(target)
            cc.togglePlayPauseCommand.removeTarget(target)
        }
        commandTargets.removeAll()
        print("[CDVMusicPlayer] teardownRemoteCommandCenter: removed all command targets")
    }

    private func stopDebugMonitoring() {
        debugTimer?.invalidate()
        debugTimer = nil
        print("[CDVMusicPlayer] stopDebugMonitoring: timer invalidated")
    }

    @objc func updatePlaybackState(_ state: String) { /* could map to MPNowPlayingInfoCenter states if needed */ }

    @objc func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        // Build a fresh dictionary to avoid carrying over stale keys
        var info: [String: Any] = [:]

        // Core metadata
        let title = (track["title"] as? String) ?? ""
        let artist = (track["artist"] as? String) ?? ""
        let album = (track["album"] as? String) ?? ""
        if !title.isEmpty { info[MPMediaItemPropertyTitle] = title }
        if !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
        if !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }

        // Playback timing
        let elapsed = CMTimeGetSeconds(player.currentTime())
        if elapsed.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let durationTime = player.currentItem?.asset.duration {
            let duration = CMTimeGetSeconds(durationTime)
            if duration.isFinite && duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        // Include asset URL only for local file URLs. Supplying remote http(s) URLs here can
        // cause CarPlay to ignore/break Now Playing rendering on some iOS versions.
        if let src = (track["source"] as? String), let u = URL(string: src), u.isFileURL {
            info[MPNowPlayingInfoPropertyAssetURL] = u
        }
        // Reflect actual player rate when possible
        let rate = isPlaying ? (player.rate == 0 ? 1.0 : player.rate) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate

        // Media type and stream flags
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false

        // Optional artwork (async, non-blocking)
        // PRIORITY 1: Check for local image first (offline support)
        // Use the original queue item (not the flattened track) to access album.id
        let originalQueueItem = currentIndex < queue.count ? queue[currentIndex] : nil
        let localImagePath: String? = {
            if let queueItem = originalQueueItem {
                return CDVLocalStorageUtils.getTrackCoverPathFromQueueItem(queueItem)
            }
            return CDVLocalStorageUtils.getTrackCoverPath(from: track)
        }()
        if let localImage = localImagePath {
            if let image = UIImage(contentsOfFile: localImage) {
                print("[CDVMusicPlayer][ART] Using LOCAL artwork: \(localImage)")
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
            }
        }
        // PRIORITY 2: Try remote artwork URL if no local found
        else if let artStr = track["artwork"] as? String, let artURL = URL(string: artStr) {
            let nsurl = artURL as NSURL
            if let cached = artworkCache.object(forKey: nsurl) {
                let artwork = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
                info[MPMediaItemPropertyArtwork] = artwork
            } else {
                URLSession.shared.dataTask(with: artURL) { [weak self] data, resp, err in
                    if let err = err { print("[CDVMusicPlayer][ART][ERROR] download failed: \(err.localizedDescription)"); return }
                    guard let self = self, let data = data, let image = UIImage(data: data) else {
                        print("[CDVMusicPlayer][ART][ERROR] invalid image data for: \(artStr)")
                        return
                    }
                    self.artworkCache.setObject(image, forKey: nsurl)
                    DispatchQueue.main.async {
                        var current: [String: Any] = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        current[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                    }
                }.resume()
            }
        }

        let applyInfo: () -> Void = {
            var enriched = info
            // Provide default playback rate key as well; some UIs consult this
            let rate = enriched[MPNowPlayingInfoPropertyPlaybackRate] as? Float ?? 0.0
            enriched[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate == 0 ? 1.0 : rate
            // Provide queue metadata when possible
            enriched[MPNowPlayingInfoPropertyPlaybackQueueCount] = self.queue.count
            enriched[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(self.currentIndex, max(0, self.queue.count - 1))
            // If a one-time refresh was requested, clear then apply
            if self.forceClearOnNextApply {
                // Use nil to force a stronger UI refresh in CarPlay before reapplying metadata
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                self.forceClearOnNextApply = false
                // Give the system a brief moment to register the clear before applying new metadata
                let enrichedCopy = enriched
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = enrichedCopy
                    MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
                }
                return
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = enriched
            MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
        }
        if Thread.isMainThread { applyInfo() } else { DispatchQueue.main.async { applyInfo() } }

    }

    @objc func updateNowPlayingInfoIfNeeded() { updateNowPlayingInfo() }

    // MARK: - Hardcoded content
    @objc func playTrack(_ track: [String: Any]) { self.queue = [track]; currentIndex = 0; loadCurrentTrack(); play() }

    @objc func cleanup() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        persistQueueState()
    }

    private func queueItemsForPersistence() -> [[String: Any]] {
        return queue.enumerated().map { entry -> [String: Any] in
            let (index, item) = entry
            // Queue items already have the structure: { "data": { ...track... } }
            // Update the indice field within the data object
            var mutableItem = item
            if var data = item["data"] as? [String: Any] {
                data["indice"] = index
                mutableItem["data"] = data
            }
            return mutableItem
        }
    }

    private func currentTrackIdForPersistence() -> String? {
        guard currentIndex < queue.count else { return nil }
        let item = queue[currentIndex]
        guard let data = item["data"] as? [String: Any] else { return nil }
        if let id = stringValue(data["idAlbumTrack"]) { return id }
        if let id = stringValue(data["id"]) { return id }
        return nil
    }

    private func persistQueueState() {
        let items = queueItemsForPersistence()
        do {
            var data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])

            // Fix escaped slashes to match mobile app format
            // JSONSerialization escapes forward slashes as \/, but mobile app doesn't
            if let jsonString = String(data: data, encoding: .utf8) {
                let unescaped = jsonString.replacingOccurrences(of: "\\/", with: "/")
                data = unescaped.data(using: .utf8) ?? data
            }

            let path = CDVQueueStorage.queueFilePath()
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: url, options: .atomic)
            print("[CDVMusicPlayer][persist] queue saved count=\(items.count) path=\(path)")
            if let first = queue.first, let firstData = first["data"] as? [String: Any] {
                let title = (firstData["name"] as? String) ?? (firstData["title"] as? String) ?? "<untitled>"
                let idAlbum = stringValue(firstData["idAlbumTrack"]) ?? stringValue(firstData["id"]) ?? ""
                print("[CDVMusicPlayer][persist] first item title=\(title) idAlbumTrack=\(idAlbum)")
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path), let modDate = attrs[.modificationDate] as? Date {
                lastQueueModifiedDate = modDate
            } else {
                lastQueueModifiedDate = Date()
            }
        } catch {
            print("[CDVMusicPlayer][persist][ERROR] failed to save queue: \(error.localizedDescription)")
        }

        if let currentId = currentTrackIdForPersistence() {
            UserDefaults.standard.setValue(currentId, forKey: "CURRENT_TRACK_KEY")
            UserDefaults.standard.synchronize()

            // Also call CDVQueueStorage.setCurrentTrackId to store in mobile app's format
            CDVQueueStorage.setCurrentTrackId(currentId)

            print("[CDVMusicPlayer][persist] current track stored id=\(currentId)")
        } else {
            print("[CDVMusicPlayer][persist][WARN] current track id unavailable while persisting queue")
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let convertible = value as? CustomStringConvertible {
            let description = convertible.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return description.isEmpty ? nil : description
        }
        return nil
    }

    // MARK: - Minimal Now Playing apply (for CarPlay binding)
    // Applies a minimal set of keys to help CarPlay bind without tripping over artwork/duration races
    @objc func applyMinimalNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [:]
        let title = (track["title"] as? String) ?? ""
        let artist = (track["artist"] as? String) ?? ""
        let album = (track["album"] as? String) ?? ""
        if !title.isEmpty { info[MPMediaItemPropertyTitle] = title }
        if !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
        if !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }
        let elapsed = CMTimeGetSeconds(player.currentTime())
        if elapsed.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        let rate = isPlaying ? (player.rate == 0 ? 1.0 : player.rate) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate == 0 ? 1.0 : rate
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        // queue hints
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = self.queue.count
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = min(self.currentIndex, max(0, self.queue.count - 1))
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
            let keys = Array(info.keys).map { String(describing: $0) }
            print("[CDVMusicPlayer] Applied MINIMAL NowPlayingInfo keys=\(keys)")
        }
    }

    // MARK: - Diagnostics
    private func attachItemObservers(_ item: AVPlayerItem) {
        NotificationCenter.default.addObserver(self, selector: #selector(itemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        item.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEnd(_:)), name: .AVPlayerItemDidPlayToEndTime, object: item)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "status", let item = object as? AVPlayerItem else { return }
        switch item.status {
        case .readyToPlay:
            print("[CDVMusicPlayer] AVPlayerItem ready to play, isInitialCarPlaySetup=\(isInitialCarPlaySetup), pendingStartPositionMs=\(pendingStartPositionMs)")
            updateNowPlayingInfo()

            // Apply pending start position if we have one
            // This handles the case where signed URL loads asynchronously and replaces the AVPlayerItem
            if pendingStartPositionMs > 0 {
                print("[CDVMusicPlayer][sync] observeValue: AVPlayerItem ready, applying pendingStartPositionMs=\(pendingStartPositionMs)")
                applyPendingStartPosition()
            } else {
                print("[CDVMusicPlayer][sync] observeValue: no pending startPosition to apply")
            }
        case .failed:
            print("[CDVMusicPlayer][ERROR] AVPlayerItem failed: \(item.error?.localizedDescription ?? "unknown error")")
        case .unknown:
            print("[CDVMusicPlayer] AVPlayerItem status unknown")
        @unknown default:
            print("[CDVMusicPlayer] AVPlayerItem status unknown (future)")
        }
    }

    @objc private func itemFailed(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem {
            print("[CDVMusicPlayer][ERROR] FailedToPlayToEnd: \(item.error?.localizedDescription ?? "unknown")")
        }
    }

    @objc private func itemDidPlayToEnd(_ notification: Notification) {
        // Auto-advance to next track
        skipToNext()
    }

    private func startPeriodicUpdates() {
        // Remove any existing observer first
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.updateNowPlayingInfo()
        }
    }
}
