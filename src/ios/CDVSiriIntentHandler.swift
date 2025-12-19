import Foundation
import Intents

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
        
        // Extract and log detailed intent information
        if let mediaSearch = intent.mediaSearch {
            print("🎵 Media Name: \(mediaSearch.mediaName ?? "none")")
            print("🎤 Artist Name: \(mediaSearch.artistName ?? "none")")
            print("💿 Album Name: \(mediaSearch.albumName ?? "none")")
            print("📱 Media Type: \(mediaSearch.mediaType.rawValue)")
            print("🎼 Genre Names: \(mediaSearch.genreNames ?? [])")
            print("🎧 Mood Names: \(mediaSearch.moodNames ?? [])")
            print("📻 Reference: \(String(describing: mediaSearch.reference))")
        } else {
            print("⚠️ No media search in intent")
        }
        
        // Log playback mode
        if #available(iOS 13.0, *) {
            print("▶️ Playback Mode: \(intent.playbackRepeatMode.rawValue)")
            print("🔀 Playback Speed: \(intent.playbackSpeed ?? 1.0)")
        }
        
        // Log resume playback flag
        if #available(iOS 13.4, *) {
            let resumePlayback = intent.resumePlayback as? Bool ?? false
            print("⏯️ Resume Playback: \(resumePlayback)")
        }
        
        print("========================================")
        
        // Create user activity to pass data to the app
        let userActivity = NSUserActivity(activityType: "INPlayMediaIntent")
        if let mediaSearch = intent.mediaSearch {
            var userInfo: [String: Any] = [:]
            if let mediaName = mediaSearch.mediaName {
                userInfo["mediaName"] = mediaName
            }
            if let artistName = mediaSearch.artistName {
                userInfo["artistName"] = artistName
            }
            if let albumName = mediaSearch.albumName {
                userInfo["albumName"] = albumName
            }
            userInfo["mediaType"] = mediaSearch.mediaType.rawValue
            userActivity.userInfo = userInfo
        }
        
        // Respond to Siri that we're handling the request
        let response = INPlayMediaIntentResponse(code: .handleInApp, userActivity: userActivity)
        completion(response)
        
        print("✅ [SiriIntentHandler] Intent handled - opening app with user activity")
    }
    
    // MARK: - Optional: Resolve methods for better Siri interaction
    
    /// Resolve media items before handling (optional but recommended)
    @objc func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        print("🔍 [SiriIntentHandler] Resolving media items...")
        
        // For now, we'll let the app handle the search
        // Return .needsValue to indicate we need more info, or .notRequired if app will handle it
        completion([INPlayMediaMediaItemResolutionResult.notRequired()])
    }
}
