import Foundation
import UIKit

/// Utility class for accessing locally stored files (tracks and images)
/// Mirrors the Android LocalStorageUtils.kt implementation
@objc(CDVLocalStorageUtils)
class CDVLocalStorageUtils: NSObject {

    private static let TAG = "[CDVLocalStorageUtils]"

    // MARK: - Base Paths

    /// Returns the Documents directory path (equivalent to cordova.file.dataDirectory)
    @objc static var documentsPath: String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
    }

    /// Returns the Library/NoCloud directory path (alternative storage location)
    static var noCloudPath: String {
        let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""
        return (libraryPath as NSString).appendingPathComponent("NoCloud")
    }

    // MARK: - Track Methods

    /// Check if a track is available locally
    /// - Parameter trackId: The track ID to check
    /// - Returns: true if the track file exists locally
    @objc static func isTrackAvailableLocally(_ trackId: String) -> Bool {
        return getLocalTrackPath(trackId) != nil
    }

    /// Get the local file path for a track if it exists
    /// - Parameter trackId: The track ID to look up
    /// - Returns: The local file path or nil if not found
    @objc static func getLocalTrackPath(_ trackId: String) -> String? {
        guard !trackId.isEmpty else {
            print("\(TAG) getLocalTrackPath: empty trackId")
            return nil
        }

        let filename = "\(trackId).mp3"

        // Check in Documents/offline/ (primary location used by Cordova)
        let documentsOfflinePath = (documentsPath as NSString).appendingPathComponent("offline/\(filename)")
        if FileManager.default.fileExists(atPath: documentsOfflinePath) {
            print("\(TAG) Found local track at: \(documentsOfflinePath)")
            return documentsOfflinePath
        }

        // Check in Library/NoCloud/offline/ (alternative location)
        let noCloudOfflinePath = (noCloudPath as NSString).appendingPathComponent("offline/\(filename)")
        if FileManager.default.fileExists(atPath: noCloudOfflinePath) {
            print("\(TAG) Found local track at: \(noCloudOfflinePath)")
            return noCloudOfflinePath
        }

        print("\(TAG) Track not found locally: \(trackId)")
        return nil
    }

    /// Get the URL for a track, checking local storage first, then falling back to remote
    /// - Parameters:
    ///   - trackId: The track ID
    ///   - idAlbumTrack: The album track ID (needed for API call)
    ///   - completion: Callback with the URL (local file URL or remote signed URL)
    @objc static func getTrackUrl(trackId: String, idAlbumTrack: String?, completion: @escaping (URL?) -> Void) {
        // First check if track exists locally
        if let localPath = getLocalTrackPath(trackId) {
            let localUrl = URL(fileURLWithPath: localPath)
            print("\(TAG) Using local track URL: \(localUrl)")
            completion(localUrl)
            return
        }

        // Track not local, fetch from API
        print("\(TAG) Track not local, fetching from API: trackId=\(trackId) idAlbumTrack=\(idAlbumTrack ?? "nil")")

        guard !trackId.isEmpty else {
            print("\(TAG) Cannot fetch remote track: invalid trackId")
            completion(nil)
            return
        }

        let albumTrackId = idAlbumTrack ?? "0"
        guard !albumTrackId.isEmpty && albumTrackId != "null" else {
            print("\(TAG) Cannot fetch remote track: invalid idAlbumTrack")
            completion(nil)
            return
        }

        let api: MusicApi = MusicApiImpl()
        let request = TrackRequest(
            idAlbumTrack: albumTrackId,
            idTrack: trackId,
            forceDevice: false,
            useCloudFront: true,
            forcePreview: false,
            extraLife: true
        )

        api.getTrackUrl(trackRequest: request) { result in
            switch result {
            case .success(let response):
                if let url = URL(string: response.signedUrl) {
                    print("\(TAG) Got remote track URL: \(response.signedUrl.prefix(80))...")
                    completion(url)
                } else {
                    print("\(TAG) Invalid remote track URL")
                    completion(nil)
                }
            case .failure(let error):
                print("\(TAG) Failed to get remote track URL: \(error)")
                completion(nil)
            }
        }
    }

    // MARK: - Image Methods

    /// Get the local file path for an image if it exists
    /// Based on Android's getLocalPathFromItemTypeAndItemId implementation
    /// - Parameters:
    ///   - itemType: The type of item (track, album, playlist, tag, artist)
    ///   - itemId: The item ID
    /// - Returns: The local file path or nil if not found
    @objc static func getLocalImagePath(itemType: String, itemId: String) -> String? {
        guard !itemType.isEmpty && !itemId.isEmpty else {
            print("\(TAG) getLocalImagePath: empty itemType or itemId")
            return nil
        }

        // Determine candidate paths based on item type
        // Mirrors Android's MediaItemFactory.getLocalPathFromItemTypeAndItemId
        let candidates: [(folder: String, filename: String)]

        switch itemType.lowercased() {
        case "track", "album", "cover":
            // Albums/tracks use cover images with various sizes
            candidates = [
                ("img/cover", "\(itemId)_640.jpg"),
                ("img/cover", "\(itemId).jpg"),
                ("img/cover", "\(itemId)_180.jpg"),
                ("img/cover", "\(itemId)_100.jpg"),
                ("img/cover", "\(itemId)_48.jpg")
            ]
        case "playlist":
            // Playlists use PNG images
            candidates = [
                ("img/playlist", "\(itemId)_180.png"),
                ("img/playlist", "\(itemId).png"),
                ("img/playlist", "\(itemId)_640.png")
            ]
        case "tag":
            // Tags use PNG images
            candidates = [
                ("img/tag", "\(itemId)_180.png"),
                ("img/tag", "\(itemId).png")
            ]
        case "artist", "artists":
            // Artists typically not stored locally, but check anyway
            candidates = [
                ("img/artists", "\(itemId)_180.png"),
                ("img/artists", "\(itemId).png")
            ]
        default:
            // Generic fallback
            candidates = [
                ("img/\(itemType)", "\(itemId).jpg"),
                ("img/\(itemType)", "\(itemId).png")
            ]
        }

        // Check Documents directory first
        for (folder, filename) in candidates {
            let path = (documentsPath as NSString).appendingPathComponent("\(folder)/\(filename)")
            if FileManager.default.fileExists(atPath: path) {
                print("\(TAG) Found local image at: \(path)")
                return path
            }
        }

        // Check NoCloud directory as fallback
        for (folder, filename) in candidates {
            let path = (noCloudPath as NSString).appendingPathComponent("\(folder)/\(filename)")
            if FileManager.default.fileExists(atPath: path) {
                print("\(TAG) Found local image at: \(path)")
                return path
            }
        }

        print("\(TAG) Image not found locally: type=\(itemType) id=\(itemId)")
        return nil
    }

    /// Get the local image URL for an item if it exists
    /// - Parameters:
    ///   - itemType: The type of item
    ///   - itemId: The item ID
    /// - Returns: A file URL or nil if not found locally
    @objc static func getLocalImageUrl(itemType: String, itemId: String) -> URL? {
        guard let path = getLocalImagePath(itemType: itemType, itemId: itemId) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Load a UIImage from local storage if available
    /// - Parameters:
    ///   - itemType: The type of item
    ///   - itemId: The item ID
    /// - Returns: A UIImage or nil if not found locally
    @objc static func getLocalImage(itemType: String, itemId: String) -> UIImage? {
        guard let path = getLocalImagePath(itemType: itemType, itemId: itemId) else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }

    /// Check if an image is available locally
    /// - Parameters:
    ///   - itemType: The type of item
    ///   - itemId: The item ID
    /// - Returns: true if the image exists locally
    @objc static func isImageAvailableLocally(itemType: String, itemId: String) -> Bool {
        return getLocalImagePath(itemType: itemType, itemId: itemId) != nil
    }

    // MARK: - Album Image Helper

    /// Get local image path for an album (convenience method)
    /// Extracts album ID from track data and looks up the cover image
    /// - Parameter albumId: The album ID
    /// - Returns: Local file path or nil
    @objc static func getAlbumCoverPath(_ albumId: String) -> String? {
        return getLocalImagePath(itemType: "album", itemId: albumId)
    }

    /// Get local image for a track using its album's cover
    /// - Parameter trackData: Dictionary containing track info with album data
    /// - Returns: Local file path or nil
    @objc static func getTrackCoverPath(from trackData: [String: Any]) -> String? {
        // Try to get album ID from track data
        if let albumDict = trackData["album"] as? [String: Any],
           let albumId = albumDict["id"] {
            let albumIdStr = String(describing: albumId)
            return getLocalImagePath(itemType: "album", itemId: albumIdStr)
        }

        // Fallback: try track's own ID as cover
        if let trackId = trackData["id"] {
            let trackIdStr = String(describing: trackId)
            return getLocalImagePath(itemType: "track", itemId: trackIdStr)
        }

        return nil
    }

    /// Get local image for a track using its album's cover from the original queue item
    /// This method handles the nested structure: { "data": { "album": { "id": ... } } }
    /// - Parameter queueItem: The original queue item with nested data structure
    /// - Returns: Local file path or nil
    @objc static func getTrackCoverPathFromQueueItem(_ queueItem: [String: Any]) -> String? {
        // The queue item has structure: { "data": { ..., "album": { "id": X, ... }, ... } }
        guard let data = queueItem["data"] as? [String: Any] else {
            print("\(TAG) getTrackCoverPathFromQueueItem: no 'data' field in queue item")
            return nil
        }

        // Try to get album ID from the nested album object
        if let albumDict = data["album"] as? [String: Any],
           let albumId = albumDict["id"] {
            let albumIdStr = String(describing: albumId)
            print("\(TAG) getTrackCoverPathFromQueueItem: looking for album cover with albumId=\(albumIdStr)")
            if let path = getLocalImagePath(itemType: "album", itemId: albumIdStr) {
                return path
            }
        }

        // Fallback: try track's own ID as cover
        if let trackId = data["id"] {
            let trackIdStr = String(describing: trackId)
            print("\(TAG) getTrackCoverPathFromQueueItem: fallback to track cover with trackId=\(trackIdStr)")
            return getLocalImagePath(itemType: "track", itemId: trackIdStr)
        }

        print("\(TAG) getTrackCoverPathFromQueueItem: no album or track ID found")
        return nil
    }
}
