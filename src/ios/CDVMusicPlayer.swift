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
    private var lastLocalArtworkPath: String?  // Track to avoid log spam
    private var forceClearOnNextApply: Bool = false
    private var lastQueueModifiedDate: Date?
    private var debugTimer: Timer?
    private var lastKnownTrackId: String?

    // Serial queue to protect mutations to self.queue and self.currentIndex (Phase 0 stabilization)
    private let playerQueue = DispatchQueue(label: "com.kuack.carplay.player")

    // Cached playback context (Phase 1: PLAYLIST_DATA persistence)
    // Updated when queue changes via setCurrentParentContext(), read in updateNowPlayingInfo()
    var currentParentContext: [String: Any]?

    // Phase 9: Preloaded next track item for seamless transitions
    private var nextPlayerItem: AVPlayerItem?
    private var nextPlayerTrackId: String?

    // Dynamic queue loading (mirrors Android QueueManager/QueueLoadingState)
    var queueLoadingState: CDVQueueLoadingState?
    var isDynamicQueue: Bool = false

    // Consecutive failed track skip counter — prevents infinite skip loops when offline
    private var consecutiveFailedSkips: Int = 0
    private let maxConsecutiveFailedSkips: Int = 3

    // Shuffle & Repeat state (synced with JS via CDVAutoMusicPlugin)
    var isShuffleEnabled: Bool = false
    var repeatMode: Int = 0  // 0 = off, 1 = one, 2 = all (MPRepeatType raw values)
    private var originalQueue: [[String: Any]] = []  // Preserved original order when shuffle is ON

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
        // NOTE: Do NOT call setupAudioSession(), setupRemoteCommandCenter() or startDebugMonitoring() here!
        // These should only be called when CarPlay is connected to avoid conflicts
        // with cordova-plugin-music-controls2 which also registers MPRemoteCommandCenter handlers.
        // setupAudioSession() calls beginReceivingRemoteControlEvents() which would steal
        // remote control ownership from MusicControls2 at app startup.
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
        // Don't play if CarPlay has been deactivated (prevents ghost playback)
        guard isCarPlayActive else {
            print("[DQ] ⚠️ play(): CarPlay not active, IGNORING play request")
            return
        }
        let hadItem = (player.currentItem != nil)
        if !hadItem { print("[DQ] play(): currentItem is nil -> calling loadCurrentTrack()") }
        if player.currentItem == nil { loadCurrentTrack() }
        print("[DQ] ▶ play(): queue.count=\(queue.count) index=\(currentIndex) hadItem=\(hadItem)")
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

        // Stop the old track immediately so it doesn't briefly resume
        // when we call play() after loading the new track
        player.pause()
        player.replaceCurrentItem(with: nil)

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
        let remaining = queue.count - currentIndex - 1
        print("[DQ] ▶▶ skipToNext: idx=\(currentIndex)/\(queue.count) remaining=\(remaining) isDynamic=\(isDynamicQueue) hasMore=\(queueLoadingState?.hasMore ?? false) isLoading=\(queueLoadingState?.isLoading ?? false) repeat=\(repeatMode)")

        // Repeat One: just restart current track
        if repeatMode == 1 {
            print("[CDVMusicPlayer] Repeat ONE: restarting current track")
            player.seek(to: .zero)
            play()
            updateNowPlayingInfo()
            return
        }

        var didWrap = false
        var reachedEnd = false
        playerQueue.sync {
            guard !queue.isEmpty else { return }
            let nextIdx = currentIndex + 1
            if nextIdx >= queue.count {
                // Dynamic queue: don't wrap if more tracks may arrive
                if isDynamicQueue, let state = queueLoadingState, state.hasMore {
                    print("[DQ] ⚠️ skipToNext: AT END of partial queue (idx=\(currentIndex), count=\(queue.count)), NOT wrapping — triggering loadMore")
                    return
                }
                // Repeat Off: stop at end
                if repeatMode == 0 {
                    reachedEnd = true
                    print("[CDVMusicPlayer] Repeat OFF: reached end of queue, stopping")
                    return
                }
                // Repeat All: wrap around
                currentIndex = 0
                didWrap = true
                print("[DQ] skipToNext: wrapped to index 0 (didWrap=true, repeatAll)")
            } else {
                currentIndex = nextIdx
            }
        }

        // Repeat Off and reached end: pause playback
        if reachedEnd {
            pause()
            return
        }
        // If dynamic queue is loading more and we're at the end, trigger load and wait
        if isDynamicQueue, let state = queueLoadingState, state.hasMore, !didWrap, currentIndex == queue.count - 1 {
            print("[DQ] skipToNext: at last track (idx=\(currentIndex)), triggering preemptive loadMore")
            loadMore()
        }
        // Phase 9: Try to use preloaded next track for seamless transition
        var usedPreload = false
        if let preloaded = nextPlayerItem, let preloadedId = nextPlayerTrackId {
            let currentTrackData = extractTrackData(queue[currentIndex])
            let currentId = (currentTrackData["id"] as? String) ?? ""
            if currentId == preloadedId {
                print("[DQ] [Preload] Using preloaded item for track \(preloadedId)")
                attachItemObservers(preloaded)
                player.replaceCurrentItem(with: preloaded)
                invalidatePreload()
                usedPreload = true
            }
        }
        if !usedPreload {
            loadCurrentTrack()
        }
        // Explicitly seek to 0 to ensure position is reset
        player.seek(to: .zero)
        play()
        persistQueueState()
        // Check if we need to load more tracks
        if shouldLoadMore() {
            loadMore()
        }
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
        playerQueue.sync {
            guard !queue.isEmpty else { return }
            currentIndex = (currentIndex - 1 + queue.count) % queue.count
        }
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

    @objc func seekToPosition(_ position: Double) {
        let seconds = position / 1000.0
        let currentSecs = CMTimeGetSeconds(player.currentTime())
        print("[DQ] seekToPosition: \(currentSecs)s -> \(seconds)s (posMs=\(position)) hasItem=\(player.currentItem != nil)")
        let time = CMTimeMakeWithSeconds(seconds, preferredTimescale: Int32(NSEC_PER_SEC))
        player.seek(to: time) { [weak self] finished in
            let newSecs = CMTimeGetSeconds(self?.player.currentTime() ?? .zero)
            print("[DQ] seekToPosition complete: finished=\(finished) newPosition=\(newSecs)s")
            self?.updateNowPlayingInfo()
        }
    }
    @objc func currentPlaybackPosition() -> Double {
        let secs = CMTimeGetSeconds(player.currentTime())
        return secs.isFinite ? secs * 1000.0 : 0.0
    }
    @objc func currentPlaybackState() -> String { isPlaying ? "PLAYING" : (player.currentItem != nil ? "PAUSED" : "STOPPED") }

    // MARK: - Queue
    @objc func updateQueue(_ queue: [[String: Any]]) {
        updateQueue(queue, selectedTrackId: nil, persist: true, fromNative: false)
    }

    func updateQueue(_ queue: [[String: Any]], selectedTrackId: String?, persist: Bool = true, fromNative: Bool = false) {
        print("[DQ] updateQueue(persist=\(persist)) selectedId=\(selectedTrackId ?? "<nil>") incomingCount=\(queue.count)")
        // Mitigation: If updateQueue comes from mobile app (not native), deactivate dynamic mode
        if isDynamicQueue && !fromNative {
            print("[DQ] updateQueue from mobile app — deactivating dynamic queue mode")
            isDynamicQueue = false
            queueLoadingState = nil
        }
        invalidatePreload() // Phase 9: Invalidate preloaded item when queue changes
        playerQueue.sync {
            self.queue = queue
        }

        guard !queue.isEmpty else {
            print("[DQ] updateQueue(): received empty queue")
            if persist { persistQueueState() }
            return
        }

        let persistedId = CDVQueueStorage.currentTrackId()
        let candidateId = stringValue(selectedTrackId) ?? stringValue(persistedId)

        playerQueue.sync {
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
        }

        let preview = queue.prefix(3).map { (item) -> String in
            guard let data = item["data"] as? [String: Any] else { return "<invalid>" }
            let title = (data["name"] as? String) ?? (data["title"] as? String) ?? "<untitled>"
            let idAlbum = stringValue(data["idAlbumTrack"]) ?? stringValue(data["id"]) ?? ""
            return idAlbum.isEmpty ? title : "\(title) [\(idAlbum)]"
        }.joined(separator: " | ")
        print("[DQ] updateQueue(): received \(queue.count) items firstItems=\(preview) selectedIdx=\(currentIndex)")

        loadCurrentTrack()
        updateNowPlayingInfo()

        // Always update current track ID in UserDefaults (even for dynamic queue)
        if let trackId = currentTrackIdForPersistence() {
            CDVQueueStorage.setCurrentTrackId(trackId)
        }

        if persist {
            persistQueueState()
        } else {
            print("[DQ] updateQueue(): persist=FALSE skipping queue disk write")
        }

        // Always notify JavaScript about the track change (for onMediaUpdate / app sync)
        let currentTrack = queue[currentIndex]
        NotificationCenter.default.post(
            name: Notification.Name("CDVMediaTrackChanged"),
            object: nil,
            userInfo: ["track": currentTrack]
        )
        print("[DQ] updateQueue(): posted CDVMediaTrackChanged notification")

        // If this update came from native code (Siri/CarPlay), notify JS to sync its state
        // Only notify when persist=true to avoid feedback loop: native notifies JS → JS writes to disk
        // → reloadQueueInternal detects newer file → resets index. For persist=false (dynamic queue init),
        // play() will call persistQueueState() which writes to disk, and the debug timer will sync JS.
        if fromNative && persist {
            NotificationCenter.default.post(
                name: Notification.Name("CDVNativeQueueUpdated"),
                object: nil,
                userInfo: ["source": "siri", "queueCount": queue.count, "currentIndex": currentIndex]
            )
            print("[DQ] updateQueue(): posted CDVNativeQueueUpdated notification (fromNative=true, persist=true)")
        }
    }
    @objc func reloadQueue() { reloadQueueInternal(force: false) }

    @objc func reloadQueueForced() { reloadQueueInternal(force: true) }

    private func reloadQueueInternal(force: Bool) {
        // When isDynamicQueue, only reload if the disk file was written by someone else (mobile app)
        if isDynamicQueue {
            let status = CDVQueueStorage.queueFileStatus()
            let diskDate = status.attributes?[.modificationDate] as? Date
            if let diskDate = diskDate, let lastDate = lastQueueModifiedDate, diskDate > lastDate {
                // Disk file is newer than our last write — mobile app updated the queue
                print("[DQ] reloadQueueInternal: disk queue NEWER than dynamic (\(diskDate) > \(lastDate)) — deactivating dynamic mode, accepting mobile app queue")
                isDynamicQueue = false
                queueLoadingState = nil
            } else {
                print("[DQ] reloadQueueInternal: skipping disk reload (isDynamicQueue=true, count=\(queue.count))")
                updateNowPlayingInfoIfNeeded()
                return
            }
        }

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

        playerQueue.sync {
            self.queue = items
            self.currentIndex = resolvedIndex
        }

        let formattedDate = modifiedDate.map { ISO8601DateFormatter().string(from: $0) } ?? "<nil>"
        print("[CDVMusicPlayer][diag] reloadQueue(force=\(force)): loaded=\(items.count) currentIndex=\(self.currentIndex) currentId=\(currentId ?? "<nil>") fileMTime=\(formattedDate)")

        if let modifiedDate {
            lastQueueModifiedDate = modifiedDate
        } else if let fileModifiedDate {
            lastQueueModifiedDate = fileModifiedDate
        }

        if !items.isEmpty {
            // Load cached playback context if not already set (Phase 2)
            if currentParentContext == nil {
                currentParentContext = CDVQueueStorage.getPlaylistData()
            }
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
        guard currentIndex < queue.count else { print("[DQ] ❌ loadCurrentTrack: currentIndex OUT OF RANGE — queue.count=\(queue.count) idx=\(currentIndex)"); return }
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

        print("[DQ] 🎵 loadCurrentTrack: idx=\(currentIndex)/\(queue.count) hasSource=\(!trimmedSource.isEmpty) title=\(title) idTrack=\(idTrack)")
        if isDynamicQueue {
            let stateDesc = queueLoadingState.map { "type=\($0.contentType) offset=\($0.currentOffset) hasMore=\($0.hasMore) isLoading=\($0.isLoading) total=\($0.totalExpected ?? -1)" } ?? "nil"
            print("[DQ] 🎵 loadCurrentTrack: dynamicQueue state: \(stateDesc)")
        }

        // PRIORITY 1: Check if track exists locally (offline mode)
        if !idTrack.isEmpty, let localPath = CDVLocalStorageUtils.getLocalTrackPath(idTrack) {
            let localUrl = URL(fileURLWithPath: localPath)
            print("[DQ] 📂 loadCurrentTrack: using LOCAL track: \(localPath)")
            let item = AVPlayerItem(url: localUrl)
            attachItemObservers(item)
            player.replaceCurrentItem(with: item)
            // IMPORTANT: Resume playback after replacing item - AVPlayer stops when item changes
            // BUT skip auto-play during initial CarPlay setup to prevent double playback
            if isPlaying && !isInitialCarPlaySetup { player.play(); startPeriodicUpdates() }
            // Phase 9: Preload next track in background
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.preloadNextTrack() }
            // Trigger disk-level preloader for next N tracks
            CDVTrackPreloader.shared.preloadNextTracks(queue: queue, currentIndex: currentIndex)
            return
        }

        // PRIORITY 1.5: Check if track exists in auto_cache (preloaded for CarPlay)
        if !idTrack.isEmpty, let cachePath = CDVTrackPreloader.shared.getAutoCachePath(idTrack) {
            let cacheUrl = URL(fileURLWithPath: cachePath)
            print("[DQ] 📂 loadCurrentTrack: using AUTO_CACHE track: \(cachePath)")
            let item = AVPlayerItem(url: cacheUrl)
            attachItemObservers(item)
            player.replaceCurrentItem(with: item)
            if isPlaying && !isInitialCarPlaySetup { player.play(); startPeriodicUpdates() }
            // Phase 9: Preload next track in background
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.preloadNextTrack() }
            // Trigger disk-level preloader for next N tracks
            CDVTrackPreloader.shared.preloadNextTracks(queue: queue, currentIndex: currentIndex)
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
                print("[DQ] 📂 loadCurrentTrack: using source URL=\(url.absoluteString.prefix(80))…")
                // IMPORTANT: Resume playback after replacing item - AVPlayer stops when item changes
                // BUT skip auto-play during initial CarPlay setup to prevent double playback
                if isPlaying && !isInitialCarPlaySetup { player.play(); startPeriodicUpdates() }
                // Phase 9: Preload next track in background
                DispatchQueue.global(qos: .utility).async { [weak self] in self?.preloadNextTrack() }
                // Trigger disk-level preloader for next N tracks
                CDVTrackPreloader.shared.preloadNextTracks(queue: queue, currentIndex: currentIndex)
                return
            }
        }

        // PRIORITY 3: Fallback - resolve signed URL from API when we only have IDs
        if !idTrack.isEmpty {
            print("[DQ] 🌐 loadCurrentTrack: resolving signed URL for idTrack=\(idTrack) idAlbumTrack=\(idAlbumTrack)")
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
                    print("[DQ] 🌐 loadCurrentTrack: resolved signed URL: \(urlStr.prefix(80))...")
                    if let url = URL(string: urlStr) {
                        DispatchQueue.main.async {
                            let item = AVPlayerItem(url: url)
                            self.attachItemObservers(item)
                            self.player.replaceCurrentItem(with: item)
                            print("[DQ] 🌐 loadCurrentTrack: replaced currentItem with signed URL (main-thread)")
                            // Skip auto-play during initial CarPlay setup to prevent double playback
                            if self.isPlaying && !self.isInitialCarPlaySetup { self.player.play(); self.startPeriodicUpdates() }
                            self.updateNowPlayingInfoIfNeeded()
                            // Phase 9: Preload next track in background
                            DispatchQueue.global(qos: .utility).async { [weak self] in self?.preloadNextTrack() }
                            // Trigger disk-level preloader for next N tracks
                            CDVTrackPreloader.shared.preloadNextTracks(queue: self.queue, currentIndex: self.currentIndex)
                        }
                    }
                case .failure(let err):
                    print("[DQ] ❌ loadCurrentTrack: FAILED to resolve track URL: \(err)")
                }
            }
        } else {
            print("[DQ] ❌ loadCurrentTrack: NO source/ids to play current track")
        }
    }

    // MARK: - Phase 9: Preload next track for seamless transitions

    /// Resolve the URL for the next track in the queue and create an AVPlayerItem
    private func preloadNextTrack() {
        let nextIdx: Int
        if isDynamicQueue {
            // In dynamic mode, don't wrap around — only preload if there's a real next track
            let candidate = currentIndex + 1
            guard candidate < queue.count else {
                nextPlayerItem = nil
                nextPlayerTrackId = nil
                return
            }
            nextIdx = candidate
        } else {
            nextIdx = (currentIndex + 1) % queue.count
        }
        guard nextIdx != currentIndex, nextIdx < queue.count else {
            nextPlayerItem = nil
            nextPlayerTrackId = nil
            return
        }
        let nextTrack = extractTrackData(queue[nextIdx])
        let nextId = (nextTrack["id"] as? String) ?? ""
        guard !nextId.isEmpty else { return }

        // Skip if already preloaded for this track
        if nextPlayerTrackId == nextId, nextPlayerItem != nil { return }

        print("[DQ] [Preload] Preloading next track idx=\(nextIdx) id=\(nextId)")

        // Check local offline first
        if let localPath = CDVLocalStorageUtils.getLocalTrackPath(nextId) {
            let item = AVPlayerItem(url: URL(fileURLWithPath: localPath))
            playerQueue.sync {
                self.nextPlayerItem = item
                self.nextPlayerTrackId = nextId
            }
            print("[DQ] [Preload] Preloaded LOCAL track: \(nextId)")
            return
        }

        // Check auto_cache (preloaded by TrackPreloader)
        if let cachePath = CDVTrackPreloader.shared.getAutoCachePath(nextId) {
            let item = AVPlayerItem(url: URL(fileURLWithPath: cachePath))
            playerQueue.sync {
                self.nextPlayerItem = item
                self.nextPlayerTrackId = nextId
            }
            print("[DQ] [Preload] Preloaded AUTO_CACHE track: \(nextId)")
            return
        }

        // Try source URL
        let source = (nextTrack["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !source.isEmpty, let url = URL(string: source), url.scheme != nil {
            let item = AVPlayerItem(url: url)
            playerQueue.sync {
                self.nextPlayerItem = item
                self.nextPlayerTrackId = nextId
            }
            print("[DQ] [Preload] Preloaded from source URL: \(nextId)")
            return
        }

        // Resolve signed URL
        let idAlbumTrack = (nextTrack["idAlbumTrack"] as? String) ?? ""
        let api: MusicApi = MusicApiImpl()
        let req = TrackRequest(
            idAlbumTrack: !idAlbumTrack.isEmpty ? idAlbumTrack : "0",
            idTrack: nextId,
            forceDevice: false, useCloudFront: true, forcePreview: false, extraLife: true
        )
        api.getTrackUrl(trackRequest: req) { [weak self] result in
            guard let self = self else { return }
            if let signed = try? result.get(), let url = URL(string: signed.signedUrl) {
                let item = AVPlayerItem(url: url)
                self.playerQueue.sync {
                    self.nextPlayerItem = item
                    self.nextPlayerTrackId = nextId
                }
                print("[DQ] [Preload] Preloaded from signed URL: \(nextId)")
            }
        }
    }

    /// Invalidate any preloaded item (call when queue changes)
    private func invalidatePreload() {
        playerQueue.sync {
            nextPlayerItem = nil
            nextPlayerTrackId = nil
        }
    }

    // MARK: - Dynamic Queue Loading

    /// Append new items to the end of the queue (thread-safe)
    func appendQueue(_ newItems: [[String: Any]]) {
        playerQueue.sync {
            self.queue.append(contentsOf: newItems)
        }
        print("[DQ] appendQueue: added \(newItems.count) items, total=\(queue.count)")
    }

    /// Check if we need to load more tracks based on proximity to end of queue
    func shouldLoadMore(threshold: Int = 3) -> Bool {
        guard isDynamicQueue, let state = queueLoadingState, state.hasMore, !state.isLoading else { return false }
        let remaining = queue.count - currentIndex - 1
        let should = remaining <= threshold
        if should {
            print("[DQ] 📡 shouldLoadMore=YES remaining=\(remaining) threshold=\(threshold) offset=\(state.currentOffset) type=\(state.contentType)")
        }
        return should
    }

    /// Load the next batch of tracks from the API based on current queue loading state
    func loadMore() {
        guard var state = queueLoadingState, state.hasMore, !state.isLoading else {
            let reason = queueLoadingState == nil ? "no state" : (!queueLoadingState!.hasMore ? "hasMore=false" : "isLoading=true")
            print("[DQ] loadMore: SKIPPED (\(reason))")
            return
        }

        // Check network availability — don't make API calls without connectivity
        guard CDVNetworkUtils.shared.isNetworkAvailable else {
            print("[DQ] loadMore: SKIPPED (no network) — will retry when connectivity returns")
            return
        }

        state.isLoading = true
        queueLoadingState = state

        let api: MusicApi = MusicApiImpl()
        let batchSize = 15

        print("[DQ] 🔄 loadMore START: type=\(state.contentType) id=\(state.contentId) offset=\(state.currentOffset) queueCount=\(queue.count) currentIdx=\(currentIndex)")

        switch state.contentType {
        case "ALBUM":
            api.getAlbumTracks(albumId: state.contentId, limit: batchSize, offset: state.currentOffset) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let albumTracks):
                    let tracks = albumTracks.tracks.items
                    if tracks.isEmpty {
                        self.finishLoadMore(newTracks: [], hasMore: false)
                    } else {
                        let total = albumTracks.tracks.total
                        self.resolveAndAppend(tracks: tracks, state: state, totalExpected: total)
                    }
                case .failure(let error):
                    print("[DQ] loadMore ALBUM error: \(error)")
                    self.finishLoadMore(newTracks: [], hasMore: true) // retry on next trigger
                }
            }

        case "PLAYLIST", "MIX":
            api.getPlayListTracks(playListId: state.contentId, limit: batchSize, offset: state.currentOffset) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let playlistTracks):
                    let tracks = playlistTracks.tracks.items.map { $0.track }
                    if tracks.isEmpty {
                        self.finishLoadMore(newTracks: [], hasMore: false)
                    } else {
                        let total = playlistTracks.tracks.total
                        self.resolveAndAppend(tracks: tracks, state: state, totalExpected: total)
                    }
                case .failure(let error):
                    print("[DQ] loadMore PLAYLIST error: \(error)")
                    self.finishLoadMore(newTracks: [], hasMore: true)
                }
            }

        case "ARTIST":
            api.getArtistTracks(artistId: state.contentId, order: "popularity", limit: batchSize, offset: state.currentOffset) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let artistTracks):
                    let tracks = artistTracks.list
                    if tracks.isEmpty {
                        self.finishLoadMore(newTracks: [], hasMore: false)
                    } else {
                        self.resolveAndAppend(tracks: tracks, state: state, totalExpected: artistTracks.total)
                    }
                case .failure(let error):
                    print("[DQ] loadMore ARTIST error: \(error)")
                    self.finishLoadMore(newTracks: [], hasMore: true)
                }
            }

        case "RADIO":
            let lastId = state.lastIdAlbumTrack.flatMap { Int64($0) }
            api.getRadioTracks(stationId: state.contentId, count: batchSize, lastIdAlbumTrack: lastId) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let tracks):
                    if tracks.isEmpty {
                        self.finishLoadMore(newTracks: [], hasMore: false)
                    } else {
                        // For radio, update lastIdAlbumTrack cursor
                        let lastTrack = tracks.last
                        let newCursor = lastTrack?.idAlbumTrack.map { String($0) }
                        self.resolveAndAppend(tracks: tracks, state: state, totalExpected: nil, radioCursor: newCursor)
                    }
                case .failure(let error):
                    print("[DQ] loadMore RADIO error: \(error)")
                    self.finishLoadMore(newTracks: [], hasMore: true)
                }
            }

        case "TRACK_RADIO":
            let last5 = extractLast5AlbumTrackIds()
            print("[DQ] TRACK_RADIO: context albumTrackIds=\(last5) excludeCount=\(state.excludeAlbumTrackIds.count) seedIds=\(state.seedAlbumTrackIds)")
            let request = RelatedTracksByQueueRequest(
                albumTrackIds: last5,
                excludeAlbumTrackIds: state.excludeAlbumTrackIds,
                seedAlbumTrackIds: state.seedAlbumTrackIds
            )
            api.getRelatedTracksByQueue(request: request, limit: batchSize) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let artistTracks):
                    let tracks = artistTracks.list
                    if tracks.isEmpty {
                        self.finishLoadMore(newTracks: [], hasMore: false)
                    } else {
                        // Add new idAlbumTrack values to excludeAlbumTrackIds
                        let newExcludeIds = tracks.compactMap { $0.idAlbumTrack }
                        self.resolveAndAppend(tracks: tracks, state: state, totalExpected: nil, trackRadioNewExcludeIds: newExcludeIds)
                    }
                case .failure(let error):
                    print("[DQ] loadMore TRACK_RADIO error: \(error)")
                    self.finishLoadMore(newTracks: [], hasMore: true)
                }
            }

        default:
            print("[DQ] loadMore: unknown contentType=\(state.contentType)")
            state.isLoading = false
            queueLoadingState = state
        }
    }

    /// Resolve signed URLs for tracks and append to queue
    private func resolveAndAppend(tracks: [Track], state: CDVQueueLoadingState, totalExpected: Int?, radioCursor: String? = nil, trackRadioNewExcludeIds: [Int64]? = nil) {
        guard let mgr = manager else {
            print("[DQ] resolveAndAppend: manager is nil")
            finishLoadMore(newTracks: [], hasMore: true)
            return
        }

        let api: MusicApi = MusicApiImpl()
        let group = DispatchGroup()
        let startIndex = queue.count
        var results: [[String: Any]?] = Array(repeating: nil, count: tracks.count)
        let parentContext = CDVCarPlayManager.QueueParentContext(
            id: state.contentId,
            type: state.contentType,
            name: state.contentName
        )

        for (i, track) in tracks.enumerated() {
            group.enter()
            let req = TrackRequest(
                idAlbumTrack: String(track.idAlbumTrack ?? 0),
                idTrack: track.id,
                forceDevice: false,
                useCloudFront: true,
                forcePreview: false,
                extraLife: true
            )
            api.getTrackUrl(trackRequest: req) { result in
                defer { group.leave() }
                guard let signed = try? result.get() else { return }
                let entry = mgr.queueEntry(from: track, signedUrl: signed.signedUrl, parent: parentContext, index: startIndex + i)
                results[i] = entry
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let validItems = results.compactMap { $0 }

            // Update loading state
            var newState = state
            newState.currentOffset += tracks.count
            newState.isLoading = false
            if let total = totalExpected {
                newState.totalExpected = total
                newState.hasMore = newState.currentOffset < total
            } else if validItems.isEmpty {
                newState.hasMore = false
            }
            // RADIO cursor update
            if let cursor = radioCursor {
                newState.lastIdAlbumTrack = cursor
            }
            // TRACK_RADIO exclude list update (capped at 100 to avoid oversized API requests)
            if let newExcludeIds = trackRadioNewExcludeIds {
                newState.excludeAlbumTrackIds.append(contentsOf: newExcludeIds)
                if newState.excludeAlbumTrackIds.count > 100 {
                    newState.excludeAlbumTrackIds = Array(newState.excludeAlbumTrackIds.suffix(100))
                }
            }
            self.queueLoadingState = newState

            if !validItems.isEmpty {
                self.appendQueue(validItems)
                self.updateNowPlayingInfo()
                let trackNames = validItems.prefix(3).compactMap { ($0["data"] as? [String: Any])?["name"] as? String }
                print("[DQ] ✅ loadMore DONE: +\(validItems.count) tracks (total=\(self.queue.count)) hasMore=\(newState.hasMore) offset=\(newState.currentOffset) total=\(newState.totalExpected ?? -1)")
                print("[DQ]    first tracks: \(trackNames.joined(separator: " | "))")
            } else {
                print("[DQ] ⚠️ loadMore: API returned tracks but none resolved to valid items (URL resolution failed)")
            }

            // When content is exhausted, transition to TRACK_RADIO for related tracks
            if !newState.hasMore {
                self.transitionToTrackRadioIfNeeded()
            }
        }
    }

    /// Finish a loadMore cycle (update state flags)
    private func finishLoadMore(newTracks: [[String: Any]], hasMore: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, var state = self.queueLoadingState else { return }
            state.isLoading = false
            state.hasMore = hasMore
            self.queueLoadingState = state
            if !newTracks.isEmpty {
                self.appendQueue(newTracks)
                self.updateNowPlayingInfo()
            }
            // When content is exhausted, transition to TRACK_RADIO for related tracks
            if !hasMore {
                self.transitionToTrackRadioIfNeeded()
            }
        }
    }

    /// Extract the last 5 idAlbumTrack values from the queue (for TRACK_RADIO context)
    private func extractLast5AlbumTrackIds() -> [Int64] {
        let startIdx = max(0, queue.count - 5)
        var ids: [Int64] = []
        for i in startIdx..<queue.count {
            let data = extractTrackData(queue[i])
            if let idAlbumTrack = data["idAlbumTrack"] {
                if let intVal = idAlbumTrack as? Int64 {
                    ids.append(intVal)
                } else if let intVal = idAlbumTrack as? Int {
                    ids.append(Int64(intVal))
                } else if let strVal = idAlbumTrack as? String, let intVal = Int64(strVal) {
                    ids.append(intVal)
                }
            }
        }
        return ids
    }

    /// Extract ALL idAlbumTrack values from the queue (for TRACK_RADIO exclude list)
    private func extractAllAlbumTrackIds() -> [Int64] {
        var ids: [Int64] = []
        for item in queue {
            let data = extractTrackData(item)
            if let idAlbumTrack = data["idAlbumTrack"] {
                if let intVal = idAlbumTrack as? Int64 {
                    ids.append(intVal)
                } else if let intVal = idAlbumTrack as? Int {
                    ids.append(Int64(intVal))
                } else if let strVal = idAlbumTrack as? String, let intVal = Int64(strVal) {
                    ids.append(intVal)
                }
            }
        }
        return ids
    }

    /// Transition from content-specific loading (ALBUM/PLAYLIST/ARTIST/MIX) to TRACK_RADIO
    /// when the original content is exhausted. Related tracks continue playing seamlessly.
    func transitionToTrackRadioIfNeeded() {
        guard var state = queueLoadingState, !state.hasMore, !state.isLoading else { return }

        let transitionTypes = ["ALBUM", "PLAYLIST", "ARTIST", "MIX"]
        guard transitionTypes.contains(state.contentType) else { return }

        // Extract seeds (last 5 valid idAlbumTrack)
        let seeds = extractLast5AlbumTrackIds()
        guard !seeds.isEmpty else {
            print("[DQ] transitionToTrackRadio: no valid seeds found, stopping")
            return
        }

        // Extract excludes (all idAlbumTrack in queue, capped at 100)
        let allExcludes = extractAllAlbumTrackIds()
        let cappedExcludes = Array(allExcludes.suffix(100))

        print("[DQ] 🔄 Transitioning from \(state.contentType) to TRACK_RADIO: seeds=\(seeds) excludeCount=\(cappedExcludes.count) queueCount=\(queue.count)")

        // Mutate state to TRACK_RADIO
        state.contentType = "TRACK_RADIO"
        state.hasMore = true
        state.totalExpected = nil
        state.seedAlbumTrackIds = seeds
        state.excludeAlbumTrackIds = cappedExcludes
        state.currentOffset = 0
        queueLoadingState = state

        // Trigger loadMore for the first batch of related tracks
        if shouldLoadMore() {
            loadMore()
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
        setupAudioSession()
        setupRemoteCommandCenter()
        startDebugMonitoring()

        // Double cleanup: clear stale auto_cache from previous session
        CDVTrackPreloader.shared.setMusicPlayer(self)
        CDVTrackPreloader.shared.clearCache()
    }

    /// Clears the initial setup flag without applying start position
    /// Used when Siri initiates direct playback (not going through normal CarPlay connection flow)
    @objc func clearInitialSetupFlag() {
        if isInitialCarPlaySetup {
            print("[CDVMusicPlayer] clearInitialSetupFlag: clearing initial setup flag for direct Siri playback")
            isInitialCarPlaySetup = false
        }
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
        // Clear auto_cache on disconnect
        CDVTrackPreloader.shared.clearCache()
        // Reset dynamic queue state
        isDynamicQueue = false
        queueLoadingState = nil
        // Fully stop playback when CarPlay disconnects to avoid ghost playback
        // This is more aggressive than pause() - it removes the current item entirely
        stopPlayback()
    }

    /// Fully stops playback by pausing and removing the current AVPlayerItem
    /// This ensures no audio continues playing from this player after CarPlay disconnects
    private func stopPlayback() {
        print("[CDVMusicPlayer] stopPlayback: fully stopping CarPlay audio player")
        
        // 1. Pause the player first
        player.pause()
        isPlaying = false
        
        // 2. Remove the current item to fully stop any audio
        // This is crucial - pause() alone may not prevent ghost playback
        player.replaceCurrentItem(with: nil)
        
        // 3. Clear now playing info from MPNowPlayingInfoCenter
        // This removes this player's metadata from the system
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        
        // 4. Stop periodic updates
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        print("[CDVMusicPlayer] stopPlayback: CarPlay audio player fully stopped")
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
        cc.changePlaybackPositionCommand.isEnabled = true
        commandTargets.append(cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let cmd = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            print("[DQ] changePlaybackPosition: seeking to \(cmd.positionTime)s")
            self.seekToPosition(cmd.positionTime * 1000)
            return .success
        })

        // Shuffle command
        cc.changeShuffleModeCommand.isEnabled = true
        commandTargets.append(cc.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let self = self, let cmd = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }
            let enable = cmd.shuffleType != .off
            print("[CDVMusicPlayer] changeShuffleMode: \(cmd.shuffleType.rawValue) -> enable=\(enable)")
            self.setShuffleEnabled(enable)
            return .success
        })

        // Repeat command
        cc.changeRepeatModeCommand.isEnabled = true
        commandTargets.append(cc.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self = self, let cmd = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            print("[CDVMusicPlayer] changeRepeatMode: \(cmd.repeatType.rawValue)")
            self.setRepeatMode(Int(cmd.repeatType.rawValue))
            return .success
        })

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
            cc.changePlaybackPositionCommand.removeTarget(target)
            cc.changeShuffleModeCommand.removeTarget(target)
            cc.changeRepeatModeCommand.removeTarget(target)
        }
        cc.changePlaybackPositionCommand.isEnabled = false
        cc.changeShuffleModeCommand.isEnabled = false
        cc.changeRepeatModeCommand.isEnabled = false
        commandTargets.removeAll()
        print("[CDVMusicPlayer] teardownRemoteCommandCenter: removed all command targets")
    }

    private func stopDebugMonitoring() {
        debugTimer?.invalidate()
        debugTimer = nil
        print("[CDVMusicPlayer] stopDebugMonitoring: timer invalidated")
    }

    /// Set the current playback context and persist to PLAYLIST_DATA file
    @objc func setCurrentParentContext(_ context: [String: Any]?) {
        self.currentParentContext = context
        CDVQueueStorage.setPlaylistData(context)
    }

    @objc func updatePlaybackState(_ state: String) { /* could map to MPNowPlayingInfoCenter states if needed */ }

    // MARK: - Shuffle & Repeat

    /// Toggle shuffle on/off. When enabling, shuffles the queue preserving the current track.
    /// When disabling, restores original order preserving the current track.
    func setShuffleEnabled(_ enabled: Bool) {
        guard enabled != isShuffleEnabled else { return }
        isShuffleEnabled = enabled

        if enabled {
            // Save original order
            originalQueue = queue
            // Shuffle queue but keep current track at currentIndex
            guard !queue.isEmpty else { return }
            let currentTrack = queue[currentIndex]
            var others = queue
            others.remove(at: currentIndex)
            others.shuffle()
            others.insert(currentTrack, at: currentIndex)
            playerQueue.sync {
                self.queue = others
            }
            print("[CDVMusicPlayer] Shuffle ON: queue shuffled, currentIndex=\(currentIndex) preserved")
        } else {
            // Restore original order, find current track in it
            guard !originalQueue.isEmpty else { return }
            let currentTrackData = extractTrackData(queue[currentIndex])
            let currentId = (currentTrackData["id"] as? String) ?? ""
            var restoredIndex = 0
            for (i, item) in originalQueue.enumerated() {
                let data = extractTrackData(item)
                if (data["id"] as? String) == currentId {
                    restoredIndex = i
                    break
                }
            }
            playerQueue.sync {
                self.queue = self.originalQueue
                self.currentIndex = restoredIndex
            }
            originalQueue = []
            print("[CDVMusicPlayer] Shuffle OFF: original order restored, currentIndex=\(currentIndex)")
        }

        notifyShuffleRepeatChanged()
        updateNowPlayingInfo()
    }

    /// Set repeat mode: 0 = off, 1 = one, 2 = all (MPRepeatType raw values)
    func setRepeatMode(_ mode: Int) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        print("[CDVMusicPlayer] Repeat mode set to \(mode) (0=off, 1=one, 2=all)")
        notifyShuffleRepeatChanged()
        updateNowPlayingInfo()
    }

    /// Post notification so CDVAutoMusicPlugin can forward to JS
    private func notifyShuffleRepeatChanged() {
        NotificationCenter.default.post(
            name: Notification.Name("CDVShuffleRepeatChanged"),
            object: nil,
            userInfo: [
                "shuffle": isShuffleEnabled,
                "repeat": repeatMode
            ]
        )
    }

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
        // Phase 2: If no album title, use playback context name ("Playing from...")
        if !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        } else if let contextName = currentParentContext?["name"] as? String, !contextName.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = contextName
        }

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
                // Only log when artwork path changes to avoid log spam
                if lastLocalArtworkPath != localImage {
                    print("[CDVMusicPlayer][ART] Using LOCAL artwork: \(localImage)")
                    lastLocalArtworkPath = localImage
                }
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
            // For dynamic queues, show totalExpected (from API) instead of partial queue.count
            if self.isDynamicQueue, let total = self.queueLoadingState?.totalExpected, total > 0 {
                enriched[MPNowPlayingInfoPropertyPlaybackQueueCount] = total
            } else {
                enriched[MPNowPlayingInfoPropertyPlaybackQueueCount] = self.queue.count
            }
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
    @objc func playTrack(_ track: [String: Any]) { playerQueue.sync { self.queue = [track]; currentIndex = 0 }; loadCurrentTrack(); play() }

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
        // Dynamic queues are persisted normally — the mobile app needs the queue
        // file on disk to sync its UI with what CarPlay is playing
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
            print("[DQ] [persist] queue saved count=\(items.count) path=\(path)")
            if let first = queue.first, let firstData = first["data"] as? [String: Any] {
                let title = (firstData["name"] as? String) ?? (firstData["title"] as? String) ?? "<untitled>"
                let idAlbum = stringValue(firstData["idAlbumTrack"]) ?? stringValue(firstData["id"]) ?? ""
                print("[DQ] [persist] first item title=\(title) idAlbumTrack=\(idAlbum)")
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path), let modDate = attrs[.modificationDate] as? Date {
                lastQueueModifiedDate = modDate
            } else {
                lastQueueModifiedDate = Date()
            }
        } catch {
            print("[DQ] [persist][ERROR] failed to save queue: \(error.localizedDescription)")
        }

        if let currentId = currentTrackIdForPersistence() {
            UserDefaults.standard.setValue(currentId, forKey: "CURRENT_TRACK_KEY")
            UserDefaults.standard.synchronize()

            // Also call CDVQueueStorage.setCurrentTrackId to store in mobile app's format
            CDVQueueStorage.setCurrentTrackId(currentId)

            print("[DQ] [persist] current track stored id=\(currentId)")
        } else {
            print("[DQ] [persist][WARN] current track id unavailable while persisting queue")
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
        if isDynamicQueue, let total = queueLoadingState?.totalExpected, total > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = total
        } else {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = self.queue.count
        }
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
            print("[DQ] AVPlayerItem ready to play, isInitialSetup=\(isInitialCarPlaySetup) pendingStartMs=\(pendingStartPositionMs)")
            consecutiveFailedSkips = 0  // Reset skip counter on successful load
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
            print("[DQ] ❌ AVPlayerItem FAILED: \(item.error?.localizedDescription ?? "unknown error")")
            skipToNextCachedTrack()
        case .unknown:
            print("[CDVMusicPlayer] AVPlayerItem status unknown")
        @unknown default:
            print("[CDVMusicPlayer] AVPlayerItem status unknown (future)")
        }
    }

    @objc private func itemFailed(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem {
            print("[DQ] ❌ FailedToPlayToEnd: \(item.error?.localizedDescription ?? "unknown")")
            skipToNextCachedTrack()
        }
    }

    /// When a track fails to load (e.g., no network), try to skip to the next track
    /// that is available in offline/ or auto_cache/. Caps consecutive skips to prevent loops.
    private func skipToNextCachedTrack() {
        consecutiveFailedSkips += 1
        let remaining = queue.count - currentIndex - 1
        print("[DQ] skipToNextCachedTrack: consecutiveSkips=\(consecutiveFailedSkips)/\(maxConsecutiveFailedSkips) remaining=\(remaining)")

        guard consecutiveFailedSkips <= maxConsecutiveFailedSkips else {
            print("[DQ] ⛔ Max consecutive failed skips reached (\(maxConsecutiveFailedSkips)) — stopping playback to avoid loop")
            return
        }
        guard remaining > 0 else {
            print("[DQ] ⛔ No more tracks in queue to skip to")
            return
        }

        // Check if next track is available locally (offline/ or auto_cache/)
        let nextIdx = currentIndex + 1
        let nextData = extractTrackData(queue[nextIdx])
        let nextId = (nextData["id"] as? String) ?? String(describing: nextData["idTrack"] ?? "")
        let hasLocal = !nextId.isEmpty && (CDVLocalStorageUtils.getLocalTrackPath(nextId) != nil)
        let hasCache = !nextId.isEmpty && CDVTrackPreloader.shared.isInAutoCache(nextId)

        if hasLocal || hasCache {
            print("[DQ] ➡️ Skipping to next track (id=\(nextId), local=\(hasLocal), cache=\(hasCache))")
            skipToNext()
        } else {
            print("[DQ] ⛔ Next track (id=\(nextId)) not available locally — stopping")
        }
    }

    @objc private func itemDidPlayToEnd(_ notification: Notification) {
        // Auto-advance to next track
        let remaining = queue.count - currentIndex - 1
        print("[DQ] 🏁 itemDidPlayToEnd: idx=\(currentIndex)/\(queue.count) remaining=\(remaining) isDynamic=\(isDynamicQueue) hasMore=\(queueLoadingState?.hasMore ?? false) repeat=\(repeatMode)")

        // Repeat One: replay same track immediately
        if repeatMode == 1 {
            print("[CDVMusicPlayer] Repeat ONE: replaying current track")
            player.seek(to: .zero)
            play()
            updateNowPlayingInfo()
            return
        }

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
