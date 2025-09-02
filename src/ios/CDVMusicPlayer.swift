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

    // MARK: - Playback
    @objc func play() {
        if player.currentItem == nil { loadCurrentTrack() }
        player.play()
        isPlaying = true
        updateNowPlayingInfoIfNeeded()
        NotificationCenter.default.post(name: Notification.Name("CDVShowNowPlayingTemplate"), object: nil)
    }

    @objc func pause() { player.pause(); isPlaying = false; updateNowPlayingInfoIfNeeded() }
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
                            if self.isPlaying { self.player.play() }
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
    }

    @objc func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.skipToNext(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.skipToPrevious(); return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
    }

    @objc func updatePlaybackState(_ state: String) { /* could map to MPNowPlayingInfoCenter states if needed */ }

    @objc func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        // Core metadata
        let title = track["title"] as? String
        let artist = track["artist"] as? String
        let album = track["album"] as? String
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPMediaItemPropertyAlbumTitle] = album

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
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Media type
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        // Optional artwork
        if let artStr = track["artwork"] as? String, let artURL = URL(string: artStr) {
            if let data = try? Data(contentsOf: artURL), let image = UIImage(data: data) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Lightweight diagnostics
        print("[CDVMusicPlayer] NowPlaying updated — title=\(title ?? "-") artist=\(artist ?? "-") elapsed=\(elapsed.isFinite ? elapsed : 0) rate=\(isPlaying ? 1.0 : 0.0)")
    }

    @objc func updateNowPlayingInfoIfNeeded() { updateNowPlayingInfo() }

    // MARK: - Hardcoded content
    @objc func playTrack(_ track: [String: Any]) { self.queue = [track]; currentIndex = 0; loadCurrentTrack(); play() }

    @objc func cleanup() { player.pause(); player.replaceCurrentItem(with: nil) }

    // MARK: - Diagnostics
    private func attachItemObservers(_ item: AVPlayerItem) {
        NotificationCenter.default.addObserver(self, selector: #selector(itemFailed(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        item.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "status", let item = object as? AVPlayerItem else { return }
        switch item.status {
        case .readyToPlay:
            print("[CDVMusicPlayer] AVPlayerItem ready to play")
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
}
