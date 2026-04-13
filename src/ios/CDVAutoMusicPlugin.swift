import Foundation
import CarPlay
import Intents

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
    private var siriIntentCallbackId: String?
    private var shuffleRepeatCallbackId: String?

    override func pluginInitialize() {
        super.pluginInitialize()
        CDVAutoMusicPlugin.shared = self
        self.carPlayManager = CDVCarPlayManager(plugin: self)

        NotificationCenter.default.addObserver(self, selector: #selector(carPlayConnectionChanged(_:)), name: Notification.Name("CDVCarPlayConnectionChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaTrackChanged(_:)), name: Notification.Name("CDVMediaTrackChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStateChanged(_:)), name: Notification.Name("CDVPlaybackStateChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(nativeQueueUpdated(_:)), name: Notification.Name("CDVNativeQueueUpdated"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(shuffleRepeatChanged(_:)), name: Notification.Name("CDVShuffleRepeatChanged"), object: nil)

        // Listen for pending Siri intents that arrived before plugin was ready
        NotificationCenter.default.addObserver(self, selector: #selector(handlePendingSiriIntent(_:)), name: Notification.Name("CDVPendingSiriIntent"), object: nil)

        // Load any existing queue stored by the app so play can immediately reflect on CarPlay
        carPlayManager?.musicPlayer?.reloadQueue()
        
        // Register Siri intent handler
        if #available(iOS 13.0, *) {
            registerSiriIntentHandler()
        }
    }
    
    /// Handle pending Siri intent that was received before plugin was ready
    @objc private func handlePendingSiriIntent(_ notification: Notification) {
        if let userActivity = notification.object as? NSUserActivity {
            handleSiriIntent(userActivity: userActivity)
        } else if let userInfo = notification.userInfo as? [String: Any] {
            handleSiriSearchFromIntent(searchParams: userInfo)
        }
    }

    override func onAppTerminate() {
        NotificationCenter.default.removeObserver(self)
        carPlayManager?.musicPlayer?.cleanup()
        super.onAppTerminate()
    }

    // MARK: - Connection
    @objc(isConnected:)
    func isConnected(command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: carPlayManager?.isConnected() ?? false)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(registerAutoConnectListener:)
    func registerAutoConnectListener(command: CDVInvokedUrlCommand) {
        connectionCallbackId = command.callbackId
        let result = CDVPluginResult(status: CDVCommandStatus_NO_RESULT)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(unregisterAutoConnectListener:)
    func unregisterAutoConnectListener(command: CDVInvokedUrlCommand) {
        connectionCallbackId = nil
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // Unified JS event registration used by www/myplugin.js (registerEvents)
    // Supported events: onConnectionChange, onMediaUpdate, onPlaybackStateChange
    @objc(registerEvents:)
    func registerEvents(command: CDVInvokedUrlCommand) {
        let event = (command.argument(at: 0) as? String) ?? ""

        switch event {
        case "onConnectionChange":
            connectionCallbackId = command.callbackId
        case "onMediaUpdate":
            mediaUpdateCallbackId = command.callbackId
        case "onPlaybackStateChange":
            playbackStateCallbackId = command.callbackId
        case "onNativeQueueUpdate":
            queueUpdateCallbackId = command.callbackId
        case "onShuffleRepeatChange":
            shuffleRepeatCallbackId = command.callbackId
        default:
            let err = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Unknown event: \(event)")
            commandDelegate.send(err, callbackId: command.callbackId)
            return
        }

        let result = CDVPluginResult(status: CDVCommandStatus_NO_RESULT)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Playback Control
    @objc(play:)
    func play(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.play()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(pause:)
    func pause(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.pause()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(skipToNext:)
    func skipToNext(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.skipToNext()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(skipToPrevious:)
    func skipToPrevious(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.skipToPrevious()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(seekTo:)
    func seekTo(command: CDVInvokedUrlCommand) {
        let rawArg = command.argument(at: 0)
        let position = (rawArg as? NSNumber)?.doubleValue ?? 0
        carPlayManager?.musicPlayer?.seekToPosition(position)
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getPosition:)
    func getPosition(command: CDVInvokedUrlCommand) {
        let pos = carPlayManager?.musicPlayer?.currentPlaybackPosition() ?? 0
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: pos)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getCurrentPlaybackState:)
    func getCurrentPlaybackState(command: CDVInvokedUrlCommand) {
        let state = carPlayManager?.musicPlayer?.currentPlaybackState() ?? "stopped"
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: state)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Queue
    @objc(updateQueue:)
    func updateQueue(command: CDVInvokedUrlCommand) {
        let queue = command.argument(at: 0) as? [[String: Any]] ?? []
        carPlayManager?.musicPlayer?.updateQueue(queue)
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(notifyQueueStorageUpdated:)
    func notifyQueueStorageUpdated(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.reloadQueue()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(notifyCurrentTrackUpdated:)
    func notifyCurrentTrackUpdated(command: CDVInvokedUrlCommand) {
        carPlayManager?.musicPlayer?.updateCurrentTrack()
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(playCurrentTrack:)
    func playCurrentTrack(command: CDVInvokedUrlCommand) {
        // First sync currentIndex with the track ID from UserDefaults (like Android does)
        // This ensures we play the correct track even if reloadQueue() exits early
        if let trackId = CDVQueueStorage.currentTrackId() {
            carPlayManager?.musicPlayer?.syncToTrackIdAndPlay(trackId)
        } else {
            // Fallback: reload queue and play (old behavior)
            carPlayManager?.musicPlayer?.reloadQueue()
            carPlayManager?.musicPlayer?.play()
        }
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Hardcoded content
    @objc(getHardcodedPlaylists:)
    func getHardcodedPlaylists(command: CDVInvokedUrlCommand) {
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

    // MARK: - Navigation
    @objc(updateNavigation:)
    func updateNavigation(command: CDVInvokedUrlCommand) {
        carPlayManager?.refreshNavigation()
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Navigation updated successfully")
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Auth Config (UserDefaults bridge)
    @objc(setAuthConfig:)
    func setAuthConfig(command: CDVInvokedUrlCommand) {
        // Expected args: accessToken, refreshToken, appCode, baseUrl, expirationAt
        let accessToken = command.argument(at: 0) as? String
        let refreshToken = command.argument(at: 1) as? String
        let appCode = command.argument(at: 2) as? String
        let baseUrlRaw = command.argument(at: 3) as? String
        let expirationAt = command.argument(at: 4) as? String

        // Normalize base URL: trim and ensure trailing '/'
        let normalizedBaseUrl: String? = {
            guard let raw = baseUrlRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return raw.hasSuffix("/") ? raw : raw + "/"
        }()

        let defaults = UserDefaults.standard
        if let accessToken = accessToken { defaults.setValue(accessToken, forKey: "AT_TOKEN_KEY") }
        if let refreshToken = refreshToken { defaults.setValue(refreshToken, forKey: "REFRESH_TOKEN_KEY") }
        if let appCode = appCode { defaults.setValue(appCode, forKey: "APP_KUACK_CODE") }
        if let normalizedBaseUrl = normalizedBaseUrl { defaults.setValue(normalizedBaseUrl, forKey: "API_URL") }
        if let expirationAt = expirationAt { defaults.setValue(expirationAt, forKey: "AT_EXP_TIME_KEY") }

        defaults.synchronize()

        let payload: [String: Any] = [
            "accessToken": accessToken as Any,
            "refreshToken": refreshToken as Any,
            "appCode": appCode as Any,
            "baseUrl": normalizedBaseUrl as Any,
            "expirationAt": expirationAt as Any
        ]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(getAuthConfig:)
    func getAuthConfig(command: CDVInvokedUrlCommand) {
        let defaults = UserDefaults.standard
        let payload: [String: Any] = [
            "accessToken": defaults.string(forKey: "AT_TOKEN_KEY") as Any,
            "refreshToken": defaults.string(forKey: "REFRESH_TOKEN_KEY") as Any,
            "appCode": defaults.string(forKey: "APP_KUACK_CODE") as Any,
            "baseUrl": defaults.string(forKey: "API_URL") as Any,
            "expirationAt": defaults.string(forKey: "AT_EXP_TIME_KEY") as Any
        ]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Notifications
    @objc private func carPlayConnectionChanged(_ note: Notification) {
        let connected = (note.userInfo?["connected"] as? Bool) ?? false
        
        guard let cb = connectionCallbackId else {
            print("[AutoMusicPlugin] WARNING: No connectionCallbackId registered! Call onConnectionChange() first.")
            return
        }
        
        let payload: [String: Any] = ["connected": connected]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    @objc private func mediaTrackChanged(_ note: Notification) {
        // Only send media updates when CarPlay is connected to avoid double playback
        guard carPlayManager?.isConnected() == true else { return }
        guard let cb = mediaUpdateCallbackId,
              let track = note.userInfo?["track"] as? [String: Any] else { return }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: track)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    @objc private func playbackStateChanged(_ note: Notification) {
        let action = note.userInfo?["action"] as? String ?? "unknown"
        let isConnected = carPlayManager?.isConnected() ?? false

        // Only send playback state updates when CarPlay is connected
        guard isConnected else { return }

        guard let cb = playbackStateCallbackId else { return }

        // Send as object with "action" key to match Android format
        let payload: [String: Any] = ["action": action]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    /// Called when native code (Siri/CarPlay) updates the queue
    /// This notifies JavaScript to reload its queue from storage and sync UI
    @objc private func nativeQueueUpdated(_ note: Notification) {
        // Build payload with queue info
        var payload: [String: Any] = [
            "source": note.userInfo?["source"] as? String ?? "native",
            "queueCount": carPlayManager?.musicPlayer?.queue.count ?? 0
        ]

        // Include current track info if available
        if let currentTrack = carPlayManager?.musicPlayer?.currentTrack {
            payload["currentTrack"] = currentTrack
        }
        if let currentIndex = carPlayManager?.musicPlayer?.currentIndex {
            payload["currentIndex"] = currentIndex
        }

        // Send to JavaScript callback if registered
        if let cb = queueUpdateCallbackId {
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
            result?.setKeepCallbackAs(true)
            commandDelegate.send(result, callbackId: cb)
        }
    }

    // MARK: - Shuffle & Repeat

    @objc private func shuffleRepeatChanged(_ note: Notification) {
        guard let cb = shuffleRepeatCallbackId,
              let info = note.userInfo else { return }
        let payload: [String: Any] = [
            "shuffle": info["shuffle"] as? Bool ?? false,
            "repeat": info["repeat"] as? Int ?? 0
        ]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: cb)
    }

    /// Called from JavaScript when user toggles shuffle/repeat in the app UI
    @objc(setShuffleRepeat:)
    func setShuffleRepeat(command: CDVInvokedUrlCommand) {
        guard let params = command.argument(at: 0) as? [String: Any] else {
            let err = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid params")
            commandDelegate.send(err, callbackId: command.callbackId)
            return
        }

        if let shuffle = params["shuffle"] as? Bool {
            carPlayManager?.musicPlayer?.setShuffleEnabled(shuffle)
        }
        if let repeatVal = params["repeat"] as? Int {
            // JS repeat: 0=off, 1=all, 2=one → iOS: 0=off, 1=one, 2=all
            let iosRepeat = repeatVal == 1 ? 2 : (repeatVal == 2 ? 1 : 0)
            carPlayManager?.musicPlayer?.setRepeatMode(iosRepeat)
        }

        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Siri Intent Handling
    
    /// Register the Siri intent handler with the system
    @available(iOS 13.0, *)
    private func registerSiriIntentHandler() {
        // The intent handler is registered automatically via Info.plist INIntentsRestrictionsKey
        // This method can be used for additional setup if needed
    }

    /// Request Siri authorization from the user
    /// Call this from JavaScript to prompt the user for Siri permissions
    @objc(requestSiriAuthorization:)
    func requestSiriAuthorization(command: CDVInvokedUrlCommand) {
        if #available(iOS 10.0, *) {
            INPreferences.requestSiriAuthorization { status in
                DispatchQueue.main.async {
                    var statusString = "unknown"
                    switch status {
                    case .authorized:
                        statusString = "authorized"
                    case .denied:
                        statusString = "denied"
                        print("❌ [AutoMusicPlugin] Siri authorization: denied")
                    case .restricted:
                        statusString = "restricted"
                    case .notDetermined:
                        statusString = "notDetermined"
                    @unknown default:
                        statusString = "unknown"
                    }

                    let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: statusString)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
            }
        } else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Siri requires iOS 10 or later")
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    /// Get current Siri authorization status without prompting
    @objc(getSiriAuthorizationStatus:)
    func getSiriAuthorizationStatus(command: CDVInvokedUrlCommand) {
        if #available(iOS 10.0, *) {
            let status = INPreferences.siriAuthorizationStatus()
            var statusString = "unknown"
            switch status {
            case .authorized:
                statusString = "authorized"
            case .denied:
                statusString = "denied"
            case .restricted:
                statusString = "restricted"
            case .notDetermined:
                statusString = "notDetermined"
            @unknown default:
                statusString = "unknown"
            }

            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: statusString)
            self.commandDelegate.send(result, callbackId: command.callbackId)
        } else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Siri requires iOS 10 or later")
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }
    
    /// Pending Siri intent saved when JavaScript callback is not yet registered
    private var pendingSiriIntent: [String: Any]? = nil
    
    /// JavaScript method to register a callback for Siri intents
    @objc(registerSiriIntentListener:)
    func registerSiriIntentListener(command: CDVInvokedUrlCommand) {
        siriIntentCallbackId = command.callbackId

        let result = CDVPluginResult(status: CDVCommandStatus_NO_RESULT)
        result?.setKeepCallbackAs(true)
        commandDelegate.send(result, callbackId: command.callbackId)

        // If there's a pending intent, send it now
        if let pending = pendingSiriIntent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let pendingResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: pending)
                pendingResult?.setKeepCallbackAs(true)
                self.commandDelegate.send(pendingResult, callbackId: command.callbackId)
            }
            pendingSiriIntent = nil
        }
    }

    /// Handle Siri intent when app is opened via "Hey Siri, play..."
    /// This should be called from AppDelegate's application:continueUserActivity:restorationHandler:
    @objc public func handleSiriIntent(userActivity: NSUserActivity) {
        guard userActivity.activityType == "INPlayMediaIntent" else { return }

        // Extract search parameters from userInfo
        guard let userInfo = userActivity.userInfo else { return }

        var searchParams: [String: Any] = [:]

        if let mediaName = userInfo["mediaName"] as? String {
            searchParams["mediaName"] = mediaName
        }
        if let artistName = userInfo["artistName"] as? String {
            searchParams["artistName"] = artistName
        }
        if let albumName = userInfo["albumName"] as? String {
            searchParams["albumName"] = albumName
        }
        if let mediaType = userInfo["mediaType"] as? Int {
            searchParams["mediaType"] = mediaType
        }

        // Add CarPlay connection status
        let isCarPlayConnected = carPlayManager?.isConnected() ?? false
        searchParams["isCarPlayConnected"] = isCarPlayConnected

        // Send to JavaScript
        if let callbackId = siriIntentCallbackId {
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: searchParams)
            result?.setKeepCallbackAs(true)
            commandDelegate.send(result, callbackId: callbackId)
        }
    }

    /// Handle Siri search directly from intent handler (for CarPlay mode)
    /// This is called when CarPlay is connected and we need to process the intent without opening the app UI
    @objc public func handleSiriSearchFromIntent(searchParams: [String: Any]) {
        // Send to JavaScript callback if registered
        if let callbackId = siriIntentCallbackId {
            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: searchParams)
            result?.setKeepCallbackAs(true)
            commandDelegate.send(result, callbackId: callbackId)
        } else {
            // Save the intent for when JavaScript registers its callback
            pendingSiriIntent = searchParams
        }
    }

    /// Called from JavaScript after search results are ready to play
    /// This ensures the queue is updated in both phone and CarPlay
    @objc(playSiriSearchResults:)
    func playSiriSearchResults(command: CDVInvokedUrlCommand) {
        // Only trigger native playback if CarPlay is connected.
        // When CarPlay is NOT connected, JS handles playback via MusicControls2.
        guard carPlayManager?.isConnected() == true else {
            let result = CDVPluginResult(status: CDVCommandStatus_OK)
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        // JavaScript should have already updated the queue via updateQueue()
        // and set the current track via notifyCurrentTrackUpdated()
        // Now we just need to trigger playback

        // Reload queue from storage to ensure CarPlay has latest data
        carPlayManager?.musicPlayer?.reloadQueue()

        // Start playback
        carPlayManager?.musicPlayer?.play()

        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    /// Search for music and start playback - can be triggered from app UI
    /// This provides the same functionality as Siri search but callable from JavaScript
    @objc(searchAndPlay:)
    func searchAndPlay(command: CDVInvokedUrlCommand) {
        guard let searchParams = command.argument(at: 0) as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid search parameters")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        // Add CarPlay connection status
        var params = searchParams
        params["isCarPlayConnected"] = carPlayManager?.isConnected() ?? false

        // Trigger native search in CarPlay manager
        carPlayManager?.handleSiriSearch(searchParams: params)

        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Search started")
        commandDelegate.send(result, callbackId: command.callbackId)
    }
}
