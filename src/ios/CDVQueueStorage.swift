import Foundation

class CDVQueueStorage {
    private static func libraryNoCloudPath() -> String {
        let lib = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (lib as NSString).appendingPathComponent("NoCloud")
    }

    private static func queueDirectory() -> String {
        return ((libraryNoCloudPath() as NSString)
            .appendingPathComponent("autoData") as NSString)
            .appendingPathComponent("navigation")
    }

    @objc static func queueFilePath() -> String {
        return (queueDirectory() as NSString).appendingPathComponent("QUEUE_ITEMS_KEY")
    }

    private static func ensureDirs() {
        let dir = queueDirectory()
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    // Read CURRENT_TRACK_KEY from UserDefaults (to mirror Android's SharedPreferences NativeStorage)
    @objc static func currentTrackId() -> String? {
        // If the app uses a different suite for NativeStorage, adjust here
        return UserDefaults.standard.string(forKey: "CURRENT_TRACK_KEY")
    }

    // Map the Android queue item JSON (each element has { data: { ...track... } })
    private static func mapQueueItem(_ data: [String: Any]) -> [String: Any] {
        var mapped: [String: Any] = [:]
        let title = (data["name"] as? String) ?? ""
        mapped["title"] = title
        // artist
        if let artists = data["artists"] as? [[String: Any]], let first = artists.first, let name = first["name"] as? String { mapped["artist"] = name } else { mapped["artist"] = "" }
        // album title
        if let album = data["album"] as? [String: Any], let atitle = album["title"] as? String { mapped["album"] = atitle } else { mapped["album"] = "" }
        // artwork: choose largest by size
        if let album = data["album"] as? [String: Any], let images = album["images"] as? [[String: Any]], !images.isEmpty {
            let best = images.max { (a, b) -> Bool in ((a["size"] as? Int) ?? 0) < ((b["size"] as? Int) ?? 0) }
            if let url = best?["url"] as? String, !url.isEmpty { mapped["artwork"] = url }
        }
        // identifiers used by iOS player to resolve signed URL when source is missing
        if let id = data["id"] { mapped["id"] = String(describing: id) }
        if let idAlbumTrack = data["idAlbumTrack"] { mapped["idAlbumTrack"] = String(describing: idAlbumTrack) }
        // length may be present (e.g., 00:03:54). Not strictly needed but kept for potential duration hints
        if let length = data["length"] as? String { mapped["length"] = length }
        return mapped
    }

    // Load queue from disk, returning mapped items and the current track id for index restoration
    static func loadQueueFromDisk() -> ([[String: Any]], String?) {
        ensureDirs()
        let path = queueFilePath()
        guard FileManager.default.fileExists(atPath: path) else {
            print("[QueueStorage] queue file not found at \(path)")
            return ([], currentTrackId())
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                print("[QueueStorage][ERROR] invalid JSON array at \(path)")
                return ([], currentTrackId())
            }
            // Each element is { "data": { ...track... } }
            let mapped: [[String: Any]] = jsonArray.compactMap { elem in
                guard let d = elem["data"] as? [String: Any] else { return nil }
                return mapQueueItem(d)
            }
            print("[QueueStorage] loaded items=\(mapped.count) from \(path)")
            return (mapped, currentTrackId())
        } catch {
            print("[QueueStorage][ERROR] failed reading queue file: \(error.localizedDescription)")
            return ([], currentTrackId())
        }
    }
}
