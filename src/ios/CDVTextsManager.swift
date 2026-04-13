import Foundation

/// Reads localized strings from the AUTO_TEXTS JSON file written by JavaScript.
/// Mirrors Android's TextsManager.kt implementation.
///
/// The JS app writes AUTO_TEXTS via FileSystemJSONStorage during AutoSession.initTextData().
/// This class reads it once and provides getText(key) for native UI strings.
class CDVTextsManager: NSObject {

    private static let TAG = "[CDVTextsManager]"

    /// Shared instance
    static let shared = CDVTextsManager()

    /// Parsed key→value map from AUTO_TEXTS
    private var texts: [String: String] = [:]

    private override init() {
        super.init()
        reload()
    }

    /// Reload texts from the AUTO_TEXTS file on disk.
    /// Call this when the app language may have changed or on plugin init.
    func reload() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("\(CDVTextsManager.TAG) Could not find Documents directory")
            return
        }

        let fileURL = documentsDir.appendingPathComponent("AUTO_TEXTS")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("\(CDVTextsManager.TAG) AUTO_TEXTS file not found at \(fileURL.path)")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Convert all values to String
                texts = json.compactMapValues { value in
                    if let str = value as? String { return str }
                    return String(describing: value)
                }
            }
        } catch {
            print("\(CDVTextsManager.TAG) Error reading AUTO_TEXTS: \(error)")
        }
    }

    /// Get a localized string by key. Returns the fallback if key is not found.
    /// - Parameters:
    ///   - key: The text key (e.g. "no_offline_content")
    ///   - fallback: Default value if key is missing (defaults to empty string)
    /// - Returns: The localized string or fallback
    func getText(_ key: String, fallback: String = "") -> String {
        return texts[key] ?? fallback
    }
}
