import Foundation
import CarPlay

@objc(CDVAutoMusicPlugin)
class CDVAutoMusicPlugin: CDVPlugin {
    static private weak var shared: CDVAutoMusicPlugin?
    @objc static func sharedInstance() -> CDVAutoMusicPlugin? { shared }

    @objc var carPlayManager: CDVCarPlayManager!

    private var connectionCallbackId: String?
    private var mediaUpdateCallbackId: String?
    private var playbackStateCallbackId: String?
    private var queueUpdateCallbackId: String?
    private var seekCallbackId: String?
    private var customActionCallbackId: String?

    override func pluginInitialize() {
        super.pluginInitialize()
        CDVAutoMusicPlugin.shared = self
        self.carPlayManager = CDVCarPlayManager(plugin: self)

        NotificationCenter.default.addObserver(self, selector: #selector(carPlayConnectionChanged(_:)), name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaTrackChanged(_:)), name: Notification.Name("CDVMediaTrackChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStateChanged(_:)), name: Notification.Name("CDVPlaybackStateChanged"), object: nil)
        print("[AutoMusicPlugin] pluginInitialize: manager created, observers registered")
    }

    override func onAppTerminate() {
        NotificationCenter.default.removeObserver(self)
        carPlayManager?.musicPlayer?.cleanup()
        super.onAppTerminate()
    }

    // MARK: - Connection
    @objc(isConnected:)
    func isConnected(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] isConnected called")
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: carPlayManager?.isConnected() ?? false)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(registerAutoConnectListener:)
    func registerAutoConnectListener(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] registerAutoConnectListener called")
        connectionCallbackId = command.callbackId
        let result = CDVPluginResult(status: CDVCommandStatus_NO_RESULT)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(unregisterAutoConnectListener:)
    func unregisterAutoConnectListener(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] unregisterAutoConnectListener called")
        connectionCallbackId = nil
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Playback Control
    @objc(play:)
    func play(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] play called")
        carPlayManager?.musicPlayer?.play()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(pause:)
    func pause(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] pause called")
        carPlayManager?.musicPlayer?.pause()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(skipToNext:)
    func skipToNext(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] skipToNext called")
        carPlayManager?.musicPlayer?.skipToNext()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(skipToPrevious:)
    func skipToPrevious(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] skipToPrevious called")
        carPlayManager?.musicPlayer?.skipToPrevious()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(seekTo:)
    func seekTo(command: CDVInvokedUrlCommand) {
        let position = (command.argument(at: 0) as? NSNumber)?.doubleValue ?? 0
        print("[AutoMusicPlugin] seekTo called position=\(position)")
        carPlayManager?.musicPlayer?.seekToPosition(position)
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getPosition:)
    func getPosition(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] getPosition called")
        let pos = carPlayManager?.musicPlayer?.currentPlaybackPosition() ?? 0
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: pos)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getCurrentPlaybackState:)
    func getCurrentPlaybackState(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] getCurrentPlaybackState called")
        let state = carPlayManager?.musicPlayer?.currentPlaybackState() ?? "stopped"
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: state)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Queue
    @objc(updateQueue:)
    func updateQueue(command: CDVInvokedUrlCommand) {
        let queue = command.argument(at: 0) as? [[String: Any]] ?? []
        print("[AutoMusicPlugin] updateQueue called count=\(queue.count)")
        carPlayManager?.musicPlayer?.updateQueue(queue)
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(notifyQueueStorageUpdated:)
    func notifyQueueStorageUpdated(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] notifyQueueStorageUpdated called")
        carPlayManager?.musicPlayer?.reloadQueue()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(notifyCurrentTrackUpdated:)
    func notifyCurrentTrackUpdated(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] notifyCurrentTrackUpdated called")
        carPlayManager?.musicPlayer?.updateCurrentTrack()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Hardcoded content
    @objc(getHardcodedPlaylists:)
    func getHardcodedPlaylists(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] getHardcodedPlaylists called")
        let playlists = CDVPlaylistProvider.loadPlaylistsFromJSON()
        // Map to JS-expected shape
        let mapped: [[String: Any]] = playlists.map { p in
            [
                "id": p["id"] ?? "",
                "name": p["title"] ?? "",
                "description": p["description"] ?? ""
            ]
        }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: mapped)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getHardcodedPlaylistTracks:)
    func getHardcodedPlaylistTracks(command: CDVInvokedUrlCommand) {
        print("[AutoMusicPlugin] getHardcodedPlaylistTracks called")
        let playlistId = command.argument(at: 0) as? String ?? ""
        let tracks = CDVPlaylistProvider.loadTracks(forPlaylist: playlistId)
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: tracks)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(playHardcodedTrack:)
    func playHardcodedTrack(command: CDVInvokedUrlCommand) {
        let trackUrl = command.argument(at: 0) as? String ?? ""
        let metadata = command.argument(at: 1) as? [String: Any] ?? [:]
        var track: [String: Any] = [
            "id": "hardcoded_track",
            "url": trackUrl
        ]
        track["title"] = metadata["title"] ?? "Unknown Title"
        track["artist"] = metadata["artist"] ?? "Unknown Artist"
        track["album"] = metadata["album"] ?? "Unknown Album"
        print("[AutoMusicPlugin] playHardcodedTrack called url=\(trackUrl) title=\(track["title"] ?? "-") artist=\(track["artist"] ?? "-")")
        carPlayManager?.musicPlayer?.playTrack(track)
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Playing hardcoded track")
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Logging (no-op placeholders)
    @objc(getLogs:)
    func getLogs(command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: [])
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(clearLogs:)
    func clearLogs(command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(addLog:)
    func addLog(command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Notifications
    @objc private func carPlayConnectionChanged(_ note: Notification) {
        guard let cb = connectionCallbackId,
              let connected = (note.userInfo?["connected"] as? Bool) else { return }
        let payload: [String: Any] = ["connected": connected]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    @objc private func mediaTrackChanged(_ note: Notification) {
        guard let cb = mediaUpdateCallbackId,
              let track = note.userInfo?["track"] as? [String: Any] else { return }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: track)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    @objc private func playbackStateChanged(_ note: Notification) {
        guard let cb = playbackStateCallbackId,
              let state = note.userInfo?["state"] as? String else { return }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: state)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }
}
