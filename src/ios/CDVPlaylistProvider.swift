import Foundation

@objc(CDVPlaylistProvider)
class CDVPlaylistProvider: NSObject {
    @objc static func hardcodedPlaylists() -> [[String: Any]] { return [] }
    @objc static func tracksForPlaylist(_ playlistId: String) -> [[String: Any]] { return [] }

    @objc static func loadPlaylistsFromJSON() -> [[String: Any]] {
        guard let arr = loadJSON(from: "AUTO_NAVIGATION_LIBRARY", in: "navigation") as? [[String: Any]] else { return hardcodedPlaylists() }
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
        if let tracks = loadJSON(from: "QUEUE_ITEMS_KEY", in: "navigation") as? [[String: Any]] { return tracks }
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
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                if let json = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]) {
                    return json
                }
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

        print("[CDVPlaylistProvider] Searching app folder for JSON filename=\(filename) directory=\(directory ?? "")")
        for base in bases {
            print("[CDVPlaylistProvider] Scanning base directory: \(base.path)")
            for rel in rels {
                let url = base.appendingPathComponent(rel)
                if fm.fileExists(atPath: url.path) {
                    print("[CDVPlaylistProvider] Found candidate file: \(url.path)")
                    do {
                        let data = try Data(contentsOf: url)
                        let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
                        print("[CDVPlaylistProvider] Loaded JSON from app folder: \(url.lastPathComponent) (\(data.count) bytes)")
                        return json
                    } catch {
                        print("[CDVPlaylistProvider] Failed to load/parse JSON at \(url.path): \(error)")
                    }
                }
            }
        }
        print("[CDVPlaylistProvider] No JSON found in app folder for filename=\(filename) directory=\(directory ?? "")")
        return nil
    }
}
