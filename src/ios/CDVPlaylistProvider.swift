import Foundation

@objc(CDVPlaylistProvider)
class CDVPlaylistProvider: NSObject {
    @objc static func hardcodedPlaylists() -> [[String: Any]] { return [] }
    @objc static func tracksForPlaylist(_ playlistId: String) -> [[String: Any]] { return [] }

    @objc static func loadPlaylistsFromJSON() -> [[String: Any]] {
        // Prefer app folder (supports extensionless files and Library/NoCloud)
        if let arr = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY", in: nil) as? [[String: Any]] {
            return extractPlaylistItems(arr)
        }
        if let arr = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY", in: "navigation") as? [[String: Any]] {
            return extractPlaylistItems(arr)
        }
        // Fallback to bundled resources
        guard let arr = loadJSON(from: "AUTO_NAVIGATION_LIBRARY", in: "navigation") as? [[String: Any]] else {
            return hardcodedPlaylists()
        }
        return extractPlaylistItems(arr)
    }

    private static func extractPlaylistItems(_ arr: [[String: Any]]) -> [[String: Any]] {
        let section = arr.first { ($0["text"] as? String) == "Playlists" }
        let items = section?["items"] as? [[String: Any]] ?? []
        return items.map { p in
            [
                "id": String(describing: p["id"] ?? ""),
                "title": (p["name"] as? String) ?? "Unknown Playlist",
                "description": (p["description"] as? String) ?? (((p["name"] as? String) ?? "") + " playlist")
            ]
        }
    }

    @objc static func loadTracks(forPlaylist playlistId: String) -> [[String: Any]] {
        return tracksForPlaylist(playlistId)
    }

    @objc static func loadNavigationFromJSON() -> [[String: Any]] {
        // 1) Prefer app filesystem root (filesDir-like), e.g., Library/Application Support/AUTO_NAVIGATION
        if let fsRoot = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION", in: nil) as? [[String: Any]] {
            return fsRoot
        }
        // 2) Then try within a navigation subfolder for backward compatibility
        if let fsNav = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION", in: "navigation") as? [[String: Any]] {
            return fsNav
        }
        // 3) Fallback to bundled resources
        return (loadJSON(from: "AUTO_NAVIGATION", in: "navigation") as? [[String: Any]]) ?? []
    }

    // Load full library sections (e.g., Playlists, Albums, Artists) from AUTO_NAVIGATION_LIBRARY
    // Mirrors Android behavior when AUTO_NAVIGATION is not provided.
    @objc static func loadLibrarySectionsFromJSON() -> [[String: Any]] {
        // Prefer app folder first (Library/NoCloud and common subfolders), extensionless supported
        if let arr = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY", in: nil) as? [[String: Any]] {
            return arr
        }
        if let arr = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY", in: "navigation") as? [[String: Any]] {
            return arr
        }
        if let arr = loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY", in: "data/navigation") as? [[String: Any]] {
            return arr
        }
        // Fallback to bundled
        if let arr = loadJSON(from: "AUTO_NAVIGATION_LIBRARY", in: "navigation") as? [[String: Any]] {
            return arr
        }
        return []
    }

    // MARK: - Navigation children loader (mirrors Android MediaItemTree.loadNavigationDataChildren)
    // Reads a child file referenced by AUTO_NAVIGATION.section.fileName and normalizes into
    // an array of dictionaries with best-effort keys: id, name/title, description, itemType/type
    @objc static func loadNavigationChildren(fileName: String) -> [[String: Any]] {
        // Try app folder first (Library/NoCloud and common subfolders), extensionless supported
        let appFolderJson = (
            loadJSONFromAppFolder(filename: fileName, in: nil)
            ?? loadJSONFromAppFolder(filename: fileName, in: "navigation")
            ?? loadJSONFromAppFolder(filename: fileName, in: "data/navigation")
        )

        if let json = appFolderJson {
            return normalizeChildrenPayload(fileName: fileName, json: json)
        }

        // Bundle fallbacks
        if let json = loadJSON(from: fileName, in: "navigation") {
            return normalizeChildrenPayload(fileName: fileName, json: json)
        }

        return []
    }

    // Best-effort normalization to a flat array of dicts consumable by CarPlay lists
    private static func normalizeChildrenPayload(fileName: String, json: Any) -> [[String: Any]] {
        // Direct array of dictionaries
        if let arr = json as? [[String: Any]] {
            // Special case: AUTO_NAVIGATION_LIBRARY contains sections; return as-is so caller can decide
            if fileName == "AUTO_NAVIGATION_LIBRARY" { return arr }
            // Special case: RECENT_LISTENED often wrapped as [{ data: {...} }]
            if let first = arr.first, first["data"] != nil {
                return arr.compactMap { $0["data"] as? [String: Any] }
            }
            return arr
        }
        // Some payloads can be a dictionary with key "items"
        if let dict = json as? [String: Any] {
            if let items = dict["items"] as? [[String: Any]] {
                return items
            }
        }
        return []
    }

    @objc static func loadJSON(from filename: String, in directory: String) -> Any? {
        let bundle = Bundle.main
        let candidates: [String?] = [
            bundle.path(forResource: filename, ofType: nil, inDirectory: "public/data/\(directory)"),
            bundle.path(forResource: filename, ofType: "json", inDirectory: "public/data/\(directory)"),
            bundle.path(forResource: filename, ofType: nil, inDirectory: "App/data/\(directory)"),
            bundle.path(forResource: filename, ofType: "json", inDirectory: "App/data/\(directory)"),
            bundle.path(forResource: filename, ofType: nil, inDirectory: "App/App/data/\(directory)"),
            bundle.path(forResource: filename, ofType: "json", inDirectory: "App/App/data/\(directory)"),
            bundle.path(forResource: filename, ofType: nil, inDirectory: "data/\(directory)"),
            bundle.path(forResource: filename, ofType: "json", inDirectory: "data/\(directory)"),
            bundle.path(forResource: filename, ofType: nil),
        ]
        for path in candidates.compactMap({ $0 }) {
            let url = URL(fileURLWithPath: path)
            do {
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
                return json
            } catch {
                // Enhanced diagnostics for bundled JSON failures
                let nsErr = error as NSError
                var diag = ""
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber {
                    diag += " size=\(size.intValue)"
                }
                if let data = try? Data(contentsOf: url),
                   let idx = nsErr.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                    let start = max(0, idx - 160)
                    let end = min(data.count, idx + 160)
                    let range = start..<end
                    let snippet = String(decoding: data[range], as: UTF8.self)
                    diag += " index=\(idx) snippet=\n\(snippet)\n"
                }
                print("[CDVPlaylistProvider] loadJSON(bundle): failed at path=\(path) error=\(nsErr).\(diag)")
            }
        }
        return nil
    }

    // MARK: - Filesystem helpers
    // Tries common app sandbox locations for dynamic content written by the host app
    @objc static func loadJSONFromAppFolder(filename: String, in directory: String?) -> Any? {
    let fm = FileManager.default
    var bases: [URL] = []
    // Prefer Application Support first to mirror Android's filesDir semantics
    if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { bases.append(appSup) }
    if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first { bases.append(docs) }
    if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { bases.append(caches) }
    // Also check Library and Library/NoCloud, which is where the host app stores dynamic assets
    if let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first {
        bases.append(lib)
        bases.append(lib.appendingPathComponent("NoCloud", isDirectory: true))
    }

        // Candidate relative paths inside each base
        var rels: [String] = []
        if let dir = directory, !dir.isEmpty {
            rels.append("data/\(dir)/\(filename)")
            rels.append("data/\(dir)/\(filename).json")
            rels.append("\(dir)/\(filename)")
            rels.append("\(dir)/\(filename).json")
        }
        rels.append(filename)
        rels.append("\(filename).json")

        for base in bases {
            for rel in rels {
                let url = base.appendingPathComponent(rel)
                if fm.fileExists(atPath: url.path) {
                    do {
                        let data = try Data(contentsOf: url)
                        let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
                        return json
                    } catch {
                        // Enhanced diagnostics: byte length and snippet around parse error index if available
                        let nsErr = error as NSError
                        var diag = ""
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let size = attrs[.size] as? NSNumber {
                            diag += " size=\(size.intValue)"
                        }
                        if let data = try? Data(contentsOf: url),
                           let idx = nsErr.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                            let start = max(0, idx - 160)
                            let end = min(data.count, idx + 160)
                            let range = start..<end
                            let snippet = String(decoding: data[range], as: UTF8.self)
                            diag += " index=\(idx) snippet=\n\(snippet)\n"
                        }
                        print("[CDVPlaylistProvider] Failed to load/parse JSON at \(url.path): \(nsErr).\(diag)")
                        // Attempt a non-destructive repair for common corruption (concatenated arrays/garbage at end)
                        if let data = try? Data(contentsOf: url), let repaired = attemptRepairJSON(data: data) {
                            print("[CDVPlaylistProvider][REPAIR] Successfully repaired JSON at \(url.lastPathComponent). Using repaired content.")
                            return repaired
                        } else {
                            print("[CDVPlaylistProvider][CORRUPT] Unable to repair JSON at \(url.lastPathComponent). Will continue searching/fallback.")
                        }
                    }
                }
            }
        }
        return nil
    }

    // Best-effort repair for common malformed JSON cases written by the host app.
    // Tries to trim garbage before the first '{' or '[' and after the last '}' or ']'.
    private static func attemptRepairJSON(data: Data) -> Any? {
        let text = String(decoding: data, as: UTF8.self)
        // Prefer array repair
        if let firstArr = text.firstIndex(of: "["), let lastArr = text.lastIndex(of: "]"), firstArr < lastArr {
            let slice = text[firstArr...lastArr]
            if let d = slice.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: d, options: [.allowFragments]) {
                return json
            }
        }
        // Fallback to object repair
        if let firstObj = text.firstIndex(of: "{"), let lastObj = text.lastIndex(of: "}"), firstObj < lastObj {
            let slice = text[firstObj...lastObj]
            if let d = slice.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: d, options: [.allowFragments]) {
                return json
            }
        }
        return nil
    }

    // MARK: - Offline Library Support

    /// Load offline library items (albums and playlists) from AUTO_NAVIGATION_LIBRARY_OFFLINE
    /// Mirrors Android MediaItemTree.loadNavigationDataChildren for "AUTO_NAVIGATION_LIBRARY_OFFLINE"
    /// - Returns: Array of offline items (albums and playlists)
    @objc static func loadOfflineLibrary() -> [[String: Any]] {
        // Try app folder first (Library/NoCloud), extensionless supported
        let appFolderJson = (
            loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY_OFFLINE", in: nil)
            ?? loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY_OFFLINE", in: "navigation")
            ?? loadJSONFromAppFolder(filename: "AUTO_NAVIGATION_LIBRARY_OFFLINE", in: "data/navigation")
        )

        if let json = appFolderJson {
            if let arr = json as? [[String: Any]] {
                return arr
            }
        }

        // Bundle fallback
        if let json = loadJSON(from: "AUTO_NAVIGATION_LIBRARY_OFFLINE", in: "navigation") {
            if let arr = json as? [[String: Any]] {
                return arr
            }
        }

        return []
    }

    /// Check if there are offline items available
    @objc static func hasOfflineItems() -> Bool {
        return !loadOfflineLibrary().isEmpty
    }

    /// Get the item type from an offline item dictionary
    /// - Parameter item: The item dictionary
    /// - Returns: "album" or "playlist" based on the item structure
    @objc static func getOfflineItemType(_ item: [String: Any]) -> String {
        // Check explicit itemType or type field
        if let itemType = item["itemType"] as? String {
            return itemType.lowercased()
        }
        if let type = item["type"] as? String {
            return type.lowercased()
        }

        // Heuristic: albums have releaseDate, playlists have trackCount or tracks
        if item["releaseDate"] != nil || item["release_date"] != nil {
            return "album"
        }
        if item["trackCount"] != nil || item["tracks"] != nil {
            return "playlist"
        }

        // Default to playlist
        return "playlist"
    }

    /// Extract the ID from an offline item
    @objc static func getOfflineItemId(_ item: [String: Any]) -> String {
        if let id = item["id"] {
            return String(describing: id)
        }
        if let id = item["idPlaylist"] {
            return String(describing: id)
        }
        if let id = item["idAlbum"] {
            return String(describing: id)
        }
        return ""
    }

    /// Extract the title from an offline item
    @objc static func getOfflineItemTitle(_ item: [String: Any]) -> String {
        if let title = item["title"] as? String, !title.isEmpty {
            return title
        }
        if let name = item["name"] as? String, !name.isEmpty {
            return name
        }
        return "Unknown"
    }

    /// Extract the subtitle/description from an offline item
    @objc static func getOfflineItemSubtitle(_ item: [String: Any]) -> String? {
        // For albums: artist name
        if let artists = item["artists"] as? [[String: Any]], let first = artists.first {
            if let name = first["name"] as? String {
                return name
            }
        }
        if let artist = item["artist"] as? String {
            return artist
        }
        // For playlists: description or track count
        if let desc = item["description"] as? String, !desc.isEmpty {
            return desc
        }
        if let trackCount = item["trackCount"] as? Int {
            return "\(trackCount) tracks"
        }
        return nil
    }

    /// Extract the image URL from an offline item (for albums uses album cover, for playlists uses playlist image)
    @objc static func getOfflineItemImageUrl(_ item: [String: Any]) -> String? {
        // Direct image URL
        if let image = item["image"] as? String, !image.isEmpty {
            return image
        }
        if let cover = item["cover"] as? String, !cover.isEmpty {
            return cover
        }
        if let artwork = item["artwork"] as? String, !artwork.isEmpty {
            return artwork
        }

        // Images array (common in API responses)
        if let images = item["images"] as? [[String: Any]], !images.isEmpty {
            // Prefer larger images
            let sorted = images.sorted { (lhs, rhs) -> Bool in
                let l = (lhs["size"] as? Int) ?? 0
                let r = (rhs["size"] as? Int) ?? 0
                return l > r
            }
            for img in sorted {
                if let url = img["url"] as? String, !url.isEmpty {
                    return url
                }
                // Handle create_svg type with list array
                if let list = img["list"] as? [String], let first = list.first {
                    return first
                }
            }
        }

        return nil
    }

    // MARK: - Offline Tracks Loading

    /// Load offline tracks for a specific album or playlist
    /// Reads OFFLINE_TRACKS file and filters tracks by ALBUMS_ITEMS_OFFLINE or PLAYLISTS_ITEMS_OFFLINE
    /// - Parameters:
    ///   - itemType: "album" or "playlist"
    ///   - itemId: The ID of the album or playlist
    /// - Returns: Array of track dictionaries
    @objc static func loadOfflineTracks(itemType: String, itemId: String) -> [[String: Any]] {
        // Load OFFLINE_TRACKS file
        guard let offlineTracksData = loadOfflineTracksFile() else {
            return []
        }

        guard let targetIdInt = Int(itemId) else {
            print("[CDVPlaylistProvider] loadOfflineTracks: invalid itemId '\(itemId)' - cannot convert to Int")
            return []
        }

        var result: [[String: Any]] = []
        let keyToCheck = itemType.lowercased() == "album" ? "ALBUMS_ITEMS_OFFLINE" : "PLAYLISTS_ITEMS_OFFLINE"

        // Iterate through all tracks and filter by album/playlist ID
        for (_, trackEntry) in offlineTracksData {
            guard let entryDict = trackEntry as? [String: Any] else {
                continue
            }

            // Check if this track belongs to the requested album/playlist
            if let itemIds = entryDict[keyToCheck] as? [Any] {
                let containsTarget = itemIds.contains { element in
                    if let intVal = element as? Int {
                        return intVal == targetIdInt
                    }
                    if let strVal = element as? String, let intVal = Int(strVal) {
                        return intVal == targetIdInt
                    }
                    return false
                }

                if containsTarget {
                    // Extract trackData
                    if let trackData = entryDict["trackData"] as? [String: Any] {
                        result.append(trackData)
                    }
                }
            }
        }

        return result
    }

    /// Load and parse the OFFLINE_TRACKS file
    /// - Returns: Dictionary where keys are track IDs and values are track entries
    private static func loadOfflineTracksFile() -> [String: Any]? {
        // Try app folder first (Library/NoCloud), extensionless supported
        let appFolderJson = (
            loadJSONFromAppFolder(filename: "OFFLINE_TRACKS", in: nil)
            ?? loadJSONFromAppFolder(filename: "OFFLINE_TRACKS", in: "navigation")
            ?? loadJSONFromAppFolder(filename: "OFFLINE_TRACKS", in: "data/navigation")
        )

        if let json = appFolderJson as? [String: Any] {
            return json
        }

        // Bundle fallback
        if let json = loadJSON(from: "OFFLINE_TRACKS", in: "navigation") as? [String: Any] {
            return json
        }

        return nil
    }
}
