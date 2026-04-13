import Foundation
import AVFoundation
import Network

/// Downloads the next N tracks to Documents/auto_cache/ for uninterrupted playback.
/// Mirrors Android's TrackPreloader.kt implementation.
///
/// Features:
/// - Sliding window: preloads next PRELOAD_WINDOW tracks from currentIndex
/// - Skips tracks already in offline/ (user downloads) or auto_cache/
/// - Sequential downloads (one at a time) to minimize bandwidth competition
/// - Pauses downloads when AVPlayer is buffering (waitWhileBuffering)
/// - Atomic writes: downloads to .tmp, renames to .mp3 on success
/// - Network-aware: reduces window on cellular, full window on WiFi
/// - Double cleanup: clears cache on both CarPlay connect and disconnect
class CDVTrackPreloader {
    static let shared = CDVTrackPreloader()

    private let TAG = "[DQ] [Preloader]"
    private let PRELOAD_WINDOW_WIFI = 10
    private let PRELOAD_WINDOW_CELLULAR = 3
    private let MIN_FREE_SPACE_BYTES: UInt64 = 100 * 1024 * 1024 // 100MB

    private var currentTask: URLSessionDownloadTask?
    private var preloadWorkItem: DispatchWorkItem?
    private weak var musicPlayer: CDVMusicPlayer?

    /// The auto_cache directory path (Documents/auto_cache/)
    private lazy var cacheDir: String = {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        return (documentsPath as NSString).appendingPathComponent("auto_cache")
    }()

    private init() {
        // Ensure the auto_cache directory exists
        ensureCacheDirectory()
    }

    /// Set the music player reference for buffering detection
    func setMusicPlayer(_ player: CDVMusicPlayer) {
        self.musicPlayer = player
    }

    // MARK: - Public API

    /// Preload the next tracks from the queue, starting after currentIndex
    /// Call this after each track change (skipToNext, loadCurrentTrack)
    func preloadNextTracks(queue: [[String: Any]], currentIndex: Int) {
        // Cancel any previous preload operation
        preloadWorkItem?.cancel()
        currentTask?.cancel()

        // Check network availability — don't attempt downloads without connectivity
        guard CDVNetworkUtils.shared.isNetworkAvailable else {
            return
        }

        let preloadWindow = currentPreloadWindow()
        guard preloadWindow > 0 else {
            return
        }

        // Check available disk space
        guard hasSufficientDiskSpace() else {
            print("\(TAG) Preload skipped: insufficient disk space (< \(MIN_FREE_SPACE_BYTES / 1024 / 1024)MB)")
            return
        }

        // Calculate window: currentIndex+1 ... currentIndex+preloadWindow
        let windowTracks = calculateWindow(queue: queue, currentIndex: currentIndex, windowSize: preloadWindow)
        guard !windowTracks.isEmpty else {
            return
        }

        // Get track IDs in window for cleanup — ALSO keep the currently playing track
        var windowTrackIds = Set(windowTracks.map { $0.trackId })
        if currentIndex >= 0 && currentIndex < queue.count {
            let currentData = CDVQueueStorage.extractFlattenedData(queue[currentIndex])
            let currentId = (currentData["id"] as? String) ?? String(describing: currentData["idTrack"] ?? "")
            if !currentId.isEmpty {
                windowTrackIds.insert(currentId)
            }
        }

        // Clean up auto_cache files outside the current window
        cleanupOutsideWindow(keepTrackIds: windowTrackIds)

        // Download sequentially on background queue
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            for trackInfo in windowTracks {
                guard !(self.preloadWorkItem?.isCancelled ?? true) else {
                    break
                }

                // Skip if already in offline/ (user download)
                if CDVLocalStorageUtils.getLocalTrackPath(trackInfo.trackId) != nil {
                    continue
                }

                // Skip if already in auto_cache/
                if self.isInAutoCache(trackInfo.trackId) {
                    continue
                }

                // Pause while player is buffering
                self.waitWhileBuffering()

                // Check cancellation again after potential wait
                guard !(self.preloadWorkItem?.isCancelled ?? true) else { break }

                // Check network again (may have dropped during wait)
                guard CDVNetworkUtils.shared.isNetworkAvailable else {
                    break
                }

                // Download the track
                self.downloadTrack(trackInfo)
            }
        }
        preloadWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    /// Clear the entire auto_cache directory
    /// Call on CarPlay connect (clear stale) AND disconnect (cleanup)
    func clearCache() {
        preloadWorkItem?.cancel()
        currentTask?.cancel()

        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDir) else {
            return
        }

        do {
            let files = try fm.contentsOfDirectory(atPath: cacheDir)
            for file in files {
                let filePath = (cacheDir as NSString).appendingPathComponent(file)
                try fm.removeItem(atPath: filePath)
            }
        } catch {
            print("\(TAG) Error clearing auto_cache: \(error)")
        }
    }

    // MARK: - Auto Cache Lookup

    /// Check if a track exists in auto_cache
    /// - Parameter trackId: The track ID to check
    /// - Returns: true if the track is cached
    func isInAutoCache(_ trackId: String) -> Bool {
        return getAutoCachePath(trackId) != nil
    }

    /// Get the file path for a track in auto_cache if it exists
    /// - Parameter trackId: The track ID
    /// - Returns: The file path or nil if not cached
    func getAutoCachePath(_ trackId: String) -> String? {
        guard !trackId.isEmpty else { return nil }
        let path = (cacheDir as NSString).appendingPathComponent("\(trackId).mp3")
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Internal

    private struct PreloadTrackInfo {
        let trackId: String
        let idAlbumTrack: String
    }

    private func currentPreloadWindow() -> Int {
        // Use CDVNetworkUtils for WiFi detection
        // Since CDVNetworkUtils doesn't expose interface type, use NWPathMonitor snapshot
        let monitor = NWPathMonitor()
        let path = monitor.currentPath
        monitor.cancel()
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return PRELOAD_WINDOW_WIFI
        }
        return PRELOAD_WINDOW_CELLULAR
    }

    private func calculateWindow(queue: [[String: Any]], currentIndex: Int, windowSize: Int) -> [PreloadTrackInfo] {
        var tracks: [PreloadTrackInfo] = []
        let startIdx = currentIndex + 1
        let endIdx = min(startIdx + windowSize, queue.count)

        for i in startIdx..<endIdx {
            let item = queue[i]
            let data = CDVQueueStorage.extractFlattenedData(item)
            let trackId = (data["id"] as? String) ?? String(describing: data["idTrack"] ?? "")
            let idAlbumTrack: String
            if let iat = data["idAlbumTrack"] {
                idAlbumTrack = String(describing: iat)
            } else {
                idAlbumTrack = "0"
            }
            if !trackId.isEmpty {
                tracks.append(PreloadTrackInfo(trackId: trackId, idAlbumTrack: idAlbumTrack))
            }
        }
        return tracks
    }

    private func cleanupOutsideWindow(keepTrackIds: Set<String>) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDir) else { return }

        do {
            let files = try fm.contentsOfDirectory(atPath: cacheDir)
            for file in files {
                // Extract trackId from filename (e.g., "12345.mp3" -> "12345")
                let trackId = (file as NSString).deletingPathExtension
                if !keepTrackIds.contains(trackId) {
                    let filePath = (cacheDir as NSString).appendingPathComponent(file)
                    try fm.removeItem(atPath: filePath)
                }
            }
        } catch {
            print("\(TAG) Error cleaning up auto_cache: \(error)")
        }
    }

    private func downloadTrack(_ trackInfo: PreloadTrackInfo) {
        let api: MusicApi = MusicApiImpl()
        let req = TrackRequest(
            idAlbumTrack: trackInfo.idAlbumTrack,
            idTrack: trackInfo.trackId,
            forceDevice: false,
            useCloudFront: true,
            forcePreview: false,
            extraLife: true
        )

        let semaphore = DispatchSemaphore(value: 0)

        api.getTrackUrl(trackRequest: req) { [weak self] result in
            guard let self = self else { semaphore.signal(); return }

            switch result {
            case .success(let response):
                guard let url = URL(string: response.signedUrl) else {
                    print("\(self.TAG) Invalid signed URL for track \(trackInfo.trackId)")
                    semaphore.signal()
                    return
                }
                self.downloadFile(from: url, trackId: trackInfo.trackId, semaphore: semaphore)

            case .failure(let error):
                print("\(self.TAG) Failed to get signed URL for track \(trackInfo.trackId): \(error)")
                semaphore.signal()
            }
        }

        // Wait for download to complete before moving to next track
        semaphore.wait()
    }

    private func downloadFile(from url: URL, trackId: String, semaphore: DispatchSemaphore) {
        let tmpPath = (cacheDir as NSString).appendingPathComponent("\(trackId).tmp")
        let finalPath = (cacheDir as NSString).appendingPathComponent("\(trackId).mp3")

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { semaphore.signal(); return }

            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("\(self.TAG) Download failed for track \(trackId): \(error.localizedDescription)")
                }
                semaphore.signal()
                return
            }

            guard let tempURL = tempURL else {
                print("\(self.TAG) No temp file for track \(trackId)")
                semaphore.signal()
                return
            }

            let fm = FileManager.default
            do {
                // Move downloaded file to tmp path first
                if fm.fileExists(atPath: tmpPath) {
                    try fm.removeItem(atPath: tmpPath)
                }
                try fm.moveItem(at: tempURL, to: URL(fileURLWithPath: tmpPath))

                // Atomic rename: tmp -> final
                if fm.fileExists(atPath: finalPath) {
                    try fm.removeItem(atPath: finalPath)
                }
                try fm.moveItem(atPath: tmpPath, toPath: finalPath)
            } catch {
                print("\(self.TAG) File operation failed for track \(trackId): \(error)")
                // Clean up tmp file
                try? fm.removeItem(atPath: tmpPath)
            }

            semaphore.signal()
        }

        currentTask = task
        task.resume()
    }

    private func waitWhileBuffering() {
        guard let player = musicPlayer else { return }

        // Check if player is waiting to play (buffering)
        var attempts = 0
        let maxAttempts = 60 // Max 30 seconds of waiting (60 * 500ms)

        while attempts < maxAttempts {
            var isBuffering = false
            // Must read player state on main thread
            DispatchQueue.main.sync {
                isBuffering = player.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }

            if !isBuffering { break }

            Thread.sleep(forTimeInterval: 0.5)
            attempts += 1

            // Check cancellation during wait
            if preloadWorkItem?.isCancelled ?? true { break }
        }
    }

    private func ensureCacheDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheDir) {
            do {
                try fm.createDirectory(atPath: cacheDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("\(TAG) Failed to create auto_cache directory: \(error)")
            }
        }
    }

    private func hasSufficientDiskSpace() -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: cacheDir)
            if let freeSize = attrs[.systemFreeSize] as? UInt64 {
                return freeSize >= MIN_FREE_SPACE_BYTES
            }
        } catch {
            print("\(TAG) Error checking disk space: \(error)")
        }
        // Default to allowing preload if we can't check
        return true
    }
}
