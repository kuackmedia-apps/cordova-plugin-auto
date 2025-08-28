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
    @objc func currentPlaybackPosition() -> Double { CMTimeGetSeconds(player.currentTime()) * 1000.0 }
    @objc func currentPlaybackState() -> String { isPlaying ? "playing" : (player.currentItem != nil ? "paused" : "stopped") }

    // MARK: - Queue
    @objc func updateQueue(_ queue: [[String: Any]]) { self.queue = queue; currentIndex = 0; if !queue.isEmpty { loadCurrentTrack(); updateNowPlayingInfo() } }
    @objc func reloadQueue() {}
    @objc func updateCurrentTrack() { if !queue.isEmpty { loadCurrentTrack(); updateNowPlayingInfo() } }

    // MARK: - Internals
    @objc func loadCurrentTrack() {
        guard currentIndex < queue.count else { return }
        let track = queue[currentIndex]
        guard let urlStr = track["source"] as? String, let url = URL(string: urlStr) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
}
