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
        print("🎤 [SiriIntentHandler] Initialized")
    }
    
    // MARK: - INPlayMediaIntentHandling
    
    /// Called when Siri receives a play media command
    @objc func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        print("========================================")
        print("🎤 [SiriIntentHandler] SIRI INTENT RECEIVED!")
        print("========================================")
        
        // Check if CarPlay is connected
        let isCarPlayConnected = CDVAutoMusicPlugin.sharedInstance()?.carPlayManager?.isConnected() ?? false
        print("🚗 [SiriIntentHandler] CarPlay connected: \(isCarPlayConnected)")
        
        // Extract search parameters
        var searchParams: [String: Any] = [:]
        
        if let mediaSearch = intent.mediaSearch {
            print("🎵 Media Name: \(mediaSearch.mediaName ?? "none")")
            print("🎤 Artist Name: \(mediaSearch.artistName ?? "none")")
            print("💿 Album Name: \(mediaSearch.albumName ?? "none")")
            print("📱 Media Type: \(mediaSearch.mediaType.rawValue)")
            
            if let mediaName = mediaSearch.mediaName {
                searchParams["mediaName"] = mediaName
            }
            if let artistName = mediaSearch.artistName {
                searchParams["artistName"] = artistName
            }
            if let albumName = mediaSearch.albumName {
                searchParams["albumName"] = albumName
            }
            searchParams["mediaType"] = mediaSearch.mediaType.rawValue
        } else {
            print("⚠️ No media search in intent")
        }
        
        searchParams["isCarPlayConnected"] = isCarPlayConnected
        
        print("========================================")
        
        // Handle the search natively in CarPlay manager
        DispatchQueue.main.async {
            if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                print("🎤 [SiriIntentHandler] Notifying plugin")
                plugin.handleSiriSearchFromIntent(searchParams: searchParams)
                
                // Also trigger native search in CarPlay manager
                if let carPlayManager = plugin.carPlayManager {
                    print("🔍 [SiriIntentHandler] Triggering native search in CarPlay manager")
                    carPlayManager.handleSiriSearch(searchParams: searchParams)
                }
            } else {
                print("⚠️ [SiriIntentHandler] Plugin not available, posting notification")
                NotificationCenter.default.post(
                    name: Notification.Name("CDVPendingSiriIntent"),
                    object: nil,
                    userInfo: searchParams
                )
            }
        }
        
        // Return success - this tells Siri the intent was handled
        // Using .success instead of .handleInApp to avoid "doesn't allow" error
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        completion(response)
        
        print("✅ [SiriIntentHandler] Responding with .success")
    }
    
    // MARK: - Resolution methods (REQUIRED for Siri to work properly)
    
    /// Confirm the intent can be handled
    @objc func confirm(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        print("🎤 [SiriIntentHandler] Confirming intent...")
        
        // Return ready to play - this confirms we can handle the request
        let response = INPlayMediaIntentResponse(code: .ready, userActivity: nil)
        completion(response)
        
        print("✅ [SiriIntentHandler] Confirmed with .ready")
    }
    
    /// Resolve media items before handling (optional but recommended)
    @objc func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        print("🔍 [SiriIntentHandler] Resolving media items...")
        
        // For now, we'll let the app handle the search
        // Return .notRequired to indicate app will handle it
        completion([INPlayMediaMediaItemResolutionResult.notRequired()])
    }
    
    /// Resolve playback speed
    @objc func resolvePlaybackSpeed(for intent: INPlayMediaIntent, with completion: @escaping (INPlayMediaPlaybackSpeedResolutionResult) -> Void) {
        print("🔍 [SiriIntentHandler] Resolving playback speed...")
        completion(.notRequired())
    }
    
    /// Resolve shuffle mode
    @objc func resolvePlayShuffled(for intent: INPlayMediaIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
        print("🔍 [SiriIntentHandler] Resolving shuffle mode...")
        completion(.notRequired())
    }
    
    /// Resolve repeat mode
    @objc func resolveResumePlayback(for intent: INPlayMediaIntent, with completion: @escaping (INBooleanResolutionResult) -> Void) {
        print("🔍 [SiriIntentHandler] Resolving resume playback...")
        completion(.notRequired())
    }
}
