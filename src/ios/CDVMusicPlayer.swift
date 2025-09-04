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

    @objc var currentTrack: [String: Any]? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    @objc init(manager: CDVCarPlayManager) {
        self.manager = manager
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
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
        if player.currentItem == nil { loadCurrentTrack() }
        player.play()
        isPlaying = true
        startPeriodicUpdates()
        updateNowPlayingInfoIfNeeded()
        MPNowPlayingInfoCenter.default().playbackState = .playing
        NotificationCenter.default.post(name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
    }

    @objc func pause() { player.pause(); isPlaying = false; updateNowPlayingInfoIfNeeded(); MPNowPlayingInfoCenter.default().playbackState = .paused }
    @objc func togglePlayPause() { isPlaying ? pause() : play() }

    @objc func skipToNext() { guard !queue.isEmpty else { return }; currentIndex = (currentIndex + 1) % queue.count; loadCurrentTrack(); play() }
    @objc func skipToPrevious() { guard !queue.isEmpty else { return }; currentIndex = (currentIndex - 1 + queue.count) % queue.count; loadCurrentTrack(); play() }

    @objc func seekToPosition(_ position: Double) { player.seek(to: CMTimeMakeWithSeconds(position / 1000.0, preferredTimescale: Int32(NSEC_PER_SEC))) }
    @objc func currentPlaybackPosition() -> Double {
        let secs = CMTimeGetSeconds(player.currentTime())
        return secs.isFinite ? secs * 1000.0 : 0.0
    }
    @objc func currentPlaybackState() -> String { isPlaying ? "playing" : (player.currentItem != nil ? "paused" : "stopped") }

    // MARK: - Queue
    @objc func updateQueue(_ queue: [[String: Any]]) { self.queue = queue; currentIndex = 0; if !queue.isEmpty { loadCurrentTrack(); updateNowPlayingInfo() } }
    @objc func reloadQueue() {}
    @objc func updateCurrentTrack() { if !queue.isEmpty { loadCurrentTrack(); updateNowPlayingInfo() } }

    // MARK: - Internals
    @objc func loadCurrentTrack() {
        guard currentIndex < queue.count else { return }
        let track = queue[currentIndex]
        if let urlStr = track["source"] as? String, let url = URL(string: urlStr), !urlStr.isEmpty {
            let item = AVPlayerItem(url: url)
            attachItemObservers(item)
            player.replaceCurrentItem(with: item)
            // restart periodic updates for new item
            if isPlaying { startPeriodicUpdates() }
            return
        }

        // Fallback: resolve signed URL like Android when we only have IDs
        let idTrack = (track["id"] as? String) ?? String(describing: track["idTrack"] ?? "")
        let idAlbumTrack = (track["idAlbumTrack"] as? String)
            ?? String(describing: track["idAlbumTrack"] ?? "")
        if !idTrack.isEmpty {
            print("[CDVMusicPlayer] No source URL in queue item. Resolving signed URL for idTrack=\(idTrack) idAlbumTrack=\(idAlbumTrack)")
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
                            if self.isPlaying { self.player.play(); self.startPeriodicUpdates() }
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


    @objc func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.nextTrackCommand.isEnabled = true
        cc.previousTrackCommand.isEnabled = true
        cc.togglePlayPauseCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.skipToNext(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.skipToPrevious(); return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
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
        if let artStr = track["artwork"] as? String, let artURL = URL(string: artStr) {
            print("[CDVMusicPlayer][ART] artwork URL found: \(artStr)")
            let nsurl = artURL as NSURL
            if let cached = artworkCache.object(forKey: nsurl) {
                print("[CDVMusicPlayer][ART] cache hit for artwork: \(artStr) size=\(Int(cached.size.width))x\(Int(cached.size.height)))")
                let artwork = MPMediaItemArtwork(boundsSize: cached.size) { _ in cached }
                info[MPMediaItemPropertyArtwork] = artwork
            } else {
                print("[CDVMusicPlayer][ART] cache miss, downloading artwork: \(artStr)")
                URLSession.shared.dataTask(with: artURL) { [weak self] data, resp, err in
                    if let err = err { print("[CDVMusicPlayer][ART][ERROR] download failed: \(err.localizedDescription)"); return }
                    guard let self = self, let data = data, let image = UIImage(data: data) else {
                        print("[CDVMusicPlayer][ART][ERROR] invalid image data for: \(artStr)")
                        return
                    }
                    print("[CDVMusicPlayer][ART] download success bytes=\(data.count) size=\(Int(image.size.width))x\(Int(image.size.height))) for \(artStr)")
                    self.artworkCache.setObject(image, forKey: nsurl)
                    DispatchQueue.main.async {
                        var current: [String: Any] = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        current[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                    }
                }.resume()
            }
        } else {
            print("[CDVMusicPlayer][ART] no artwork URL in current track dict keys=\(Array(track.keys))")
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
                    let keys = Array(enrichedCopy.keys).map { String(describing: $0) }
                    print("[CDVMusicPlayer] Applied NowPlayingInfo (delayed after clear) keys=\(keys)")
                }
                return
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = enriched
            MPNowPlayingInfoCenter.default().playbackState = self.isPlaying ? .playing : .paused
            let keys = Array(enriched.keys).map { String(describing: $0) }
            print("[CDVMusicPlayer] Applied NowPlayingInfo keys=\(keys)")
        }
        if Thread.isMainThread { applyInfo() } else { DispatchQueue.main.async { applyInfo() } }

        // Lightweight diagnostics
        print("[CDVMusicPlayer] NowPlaying updated — title=\(title) artist=\(artist) elapsed=\(elapsed.isFinite ? elapsed : 0) rate=\(isPlaying ? 1.0 : 0.0)")
    }

    @objc func updateNowPlayingInfoIfNeeded() { updateNowPlayingInfo() }

    // MARK: - Hardcoded content
    @objc func playTrack(_ track: [String: Any]) { self.queue = [track]; currentIndex = 0; loadCurrentTrack(); play() }

    @objc func cleanup() { player.pause(); player.replaceCurrentItem(with: nil) }

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
            print("[CDVMusicPlayer] AVPlayerItem ready to play")
            updateNowPlayingInfo()
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
