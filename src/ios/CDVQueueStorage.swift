import Foundation

class CDVQueueStorage {
    private static func queueDirectory() -> String {
        let dir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("NoCloud")
    }

    @objc static func queueFilePath() -> String {
        let path = (queueDirectory() as NSString).appendingPathComponent("QUEUE_ITEMS_KEY")
        return path
    }

    static func queueFileStatus() -> (path: String, exists: Bool, attributes: [FileAttributeKey: Any]?) {
        let path = queueFilePath()
        let exists = FileManager.default.fileExists(atPath: path)
        let attributes = exists ? (try? FileManager.default.attributesOfItem(atPath: path)) : nil
        return (path, exists, attributes)
    }

    // Read CURRENT_TRACK_KEY from UserDefaults (to mirror Android's SharedPreferences NativeStorage)
    @objc static func currentTrackId() -> String? {
        // If the app uses a different suite for NativeStorage, adjust here
        return UserDefaults.standard.string(forKey: "CURRENT_TRACK_KEY")
    }

    // Map the Android queue item JSON (each element has { data: { ...track... } })
    private static func mapQueueItem(_ data: [String: Any]) -> [String: Any] {
        var mapped: [String: Any] = [:]

        func stringValue(_ value: Any?) -> String? {
            if let s = value as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }

        func firstString(in dict: [String: Any], keys: [String]) -> String? {
            for key in keys {
                if let s = stringValue(dict[key]) { return s }
            }
            return nil
        }

        func bestImageURL(from images: [[String: Any]]) -> String? {
            guard !images.isEmpty else { return nil }
            let sorted = images.sorted { (lhs, rhs) -> Bool in
                let l = (lhs["size"] as? Int) ?? 0
                let r = (rhs["size"] as? Int) ?? 0
                if l == r { return (lhs["url"] as? String ?? "").count > (rhs["url"] as? String ?? "").count }
                return l > r
            }
            for candidate in sorted {
                if let direct = stringValue(candidate["url"]) { return direct }
                if let list = candidate["list"] as? [Any] {
                    for entry in list {
                        if let s = stringValue(entry) { return s }
                    }
                }
            }
            return nil
        }

        // Title (tracks sometimes use name/title/text keys)
        let title = firstString(in: data, keys: ["title", "name", "trackTitle", "trackName", "text"]) ?? (data["context"] as? [String: Any]).flatMap { firstString(in: $0, keys: ["title", "name"]) } ?? ""
        mapped["title"] = title

        // Artist
        var artist = firstString(in: data, keys: ["artist", "artistName", "creator", "author"])
        if artist == nil, let artists = data["artists"] as? [[String: Any]] {
            artist = artists.compactMap { firstString(in: $0, keys: ["name", "title", "text"]) }.first
        }
        if artist == nil, let album = data["album"] as? [String: Any], let artists = album["artists"] as? [[String: Any]] {
            artist = artists.compactMap { firstString(in: $0, keys: ["name", "title", "text"]) }.first
        }
        mapped["artist"] = artist ?? ""

        // Album title
        var albumTitle = (data["album"] as? [String: Any]).flatMap { firstString(in: $0, keys: ["title", "name"]) }
        if albumTitle == nil { albumTitle = firstString(in: data, keys: ["album", "albumName", "collectionName"]) }
        if albumTitle == nil, let context = data["context"] as? [String: Any] {
            albumTitle = firstString(in: context, keys: ["title", "name"]) }
        mapped["album"] = albumTitle ?? ""

        // Artwork
        var artwork = firstString(in: data, keys: ["artwork", "artworkUrl", "artUrl", "image", "imageUrl", "cover", "coverUrl"])
        if artwork == nil, let images = data["images"] as? [[String: Any]] { artwork = bestImageURL(from: images) }
        if artwork == nil, let album = data["album"] as? [String: Any] {
            artwork = firstString(in: album, keys: ["artwork", "artworkUrl", "image", "imageUrl", "cover", "coverUrl"])
                ?? (album["images"] as? [[String: Any]]).flatMap(bestImageURL)
        }
        if let art = artwork, !art.isEmpty { mapped["artwork"] = art }

        // Identifiers
        if let id = data["id"] { mapped["id"] = String(describing: id) }
        if let idTrack = data["idTrack"] { mapped["idTrack"] = String(describing: idTrack) }
        if let idAlbumTrack = data["idAlbumTrack"] { mapped["idAlbumTrack"] = String(describing: idAlbumTrack) }

        // Duration / ordering hints
        if let length = stringValue(data["length"]) { mapped["length"] = length }
        if let number = stringValue(data["number"]) { mapped["trackNumber"] = number }
        if let volume = stringValue(data["volume"]) { mapped["discNumber"] = volume }

        // Source URL (offline queues may expose filePath/source)
        if let source = stringValue(data["source"])?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            mapped["source"] = source
        } else if let filePath = stringValue(data["filePath"]) {
            mapped["source"] = filePath
        } else if let audioId = stringValue(data["audioId"]) {
            mapped["audioId"] = audioId
        }

        return mapped
    }

    // Load queue from disk, returning mapped items and the current track id for index restoration
    static func loadQueueFromDisk(usingAttributes providedAttributes: [FileAttributeKey: Any]? = nil) -> ([[String: Any]], String?, Date?) {
        let path = queueFilePath()

        let dir = queueDirectory()
        print("[QueueStorage][diag] loadQueueFromDisk(): dir=\(dir) file=\(path)")

        let exists = FileManager.default.fileExists(atPath: path)
        var attributes: [FileAttributeKey: Any]? = providedAttributes
        if attributes == nil, exists {
            attributes = try? FileManager.default.attributesOfItem(atPath: path)
        }

        guard exists else {
            print("[QueueStorage][diag] queue file not found at \(path) currentId=\(currentTrackId() ?? "<nil>")")
            return ([], currentTrackId(), nil)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let attrs = attributes {
                let size = attrs[.size] as? NSNumber
                let modified = attrs[.modificationDate] as? Date
                print("[QueueStorage][diag] queue file exists size=\(size?.intValue ?? -1) modified=\(modified?.description ?? "<nil>")")
            }
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                print("[QueueStorage][ERROR] invalid JSON array at \(path)")
                return ([], currentTrackId(), attributes?[.modificationDate] as? Date)
            }
            // Each element is { "data": { ...track... } }
            let mapped: [[String: Any]] = jsonArray.compactMap { elem in
                guard let d = elem["data"] as? [String: Any] else { return nil }
                return mapQueueItem(d)
            }
            let idsPreview = mapped.prefix(4).map { item -> String in
                let title = (item["title"] as? String) ?? "<untitled>"
                let idAlbum = (item["idAlbumTrack"] as? String) ?? (item["id"] as? String) ?? ""
                return idAlbum.isEmpty ? title : "\(title) [\(idAlbum)]"
            }.joined(separator: " | ")
            let currentId = currentTrackId()
            print("[QueueStorage][diag] loaded items=\(mapped.count) currentId=\(currentId ?? "<nil>") preview=\(idsPreview)")
            let modified = attributes?[.modificationDate] as? Date
            return (mapped, currentId, modified)
        } catch {
            print("[QueueStorage][ERROR] failed reading queue file: \(error.localizedDescription)")
            return ([], currentTrackId(), attributes?[.modificationDate] as? Date)
        }
    }
}
