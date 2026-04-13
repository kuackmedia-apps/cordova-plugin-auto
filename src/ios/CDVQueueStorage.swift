import Foundation

class CDVQueueStorage {
    private static func queueDirectory() -> String {
        let dir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("NoCloud")
    }

    @objc static func queueFilePath() -> String {
        return (queueDirectory() as NSString).appendingPathComponent("QUEUE_ITEMS_KEY")
    }

    static func queueFileStatus() -> (path: String, exists: Bool, attributes: [FileAttributeKey: Any]?) {
        let path = queueFilePath()
        let exists = FileManager.default.fileExists(atPath: path)
        let attributes = exists ? (try? FileManager.default.attributesOfItem(atPath: path)) : nil
        return (path, exists, attributes)
    }

    // Read current track ID from UserDefaults
    // The mobile app stores idAlbumTrack in 'current_track' as a quoted string (e.g., "109882915")
    @objc static func currentTrackId() -> String? {
        // Check mobile app's key first
        if let currentTrackJson = UserDefaults.standard.string(forKey: "current_track") {
            // Try to parse as JSON first (mobile app uses JSON.stringify)
            if let data = currentTrackJson.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                // Handle both number and string after JSON parsing
                if let num = parsed as? NSNumber {
                    return num.stringValue
                }
                if let str = parsed as? String {
                    return str
                }
            }
            // If JSON parsing fails, the value has quotes around it (e.g., "109882915")
            // Strip the quotes and use the inner value
            var trimmed = currentTrackJson.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
            if !trimmed.isEmpty && trimmed != "null" {
                return trimmed
            }
        }
        
        // Fall back to CarPlay's key for backward compatibility
        return UserDefaults.standard.string(forKey: "CURRENT_TRACK_KEY")
    }
    
    // Store current track ID in UserDefaults using the same format as the mobile app
    @objc static func setCurrentTrackId(_ trackId: String?) {
        guard let trackId = trackId else {
            UserDefaults.standard.removeObject(forKey: "current_track")
            return
        }
        // Store as a quoted string to match mobile app format: "109882915"
        let quotedValue = "\"\(trackId)\""
        UserDefaults.standard.set(quotedValue, forKey: "current_track")
        UserDefaults.standard.synchronize()
    }

    // MARK: - Playlist Data (context: "playing from") persistence
    // Mirrors Android's MediaSessionCallback.storeLocalData() which writes PLAYLIST_DATA file

    private static func playlistDataFilePath() -> String {
        return (queueDirectory() as NSString).appendingPathComponent("playlist_data")
    }

    /// Persist the current playback context (id, type, name) to Library/NoCloud/playlist_data
    static func setPlaylistData(_ data: [String: Any]?) {
        let path = playlistDataFilePath()
        guard let data = data else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        do {
            var jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            // Fix escaped slashes to match mobile app format
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let unescaped = jsonString.replacingOccurrences(of: "\\/", with: "/")
                jsonData = unescaped.data(using: .utf8) ?? jsonData
            }
            try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            print("[QueueStorage][ERROR] Failed to write playlist_data: \(error.localizedDescription)")
        }
    }

    /// Read the persisted playback context from Library/NoCloud/playlist_data
    static func getPlaylistData() -> [String: Any]? {
        let path = playlistDataFilePath()
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json as? [String: Any]
        } catch {
            print("[QueueStorage][ERROR] Failed to read PLAYLIST_DATA: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Current Episode persistence (for podcast support)

    private static func currentEpisodeFilePath() -> String {
        return (queueDirectory() as NSString).appendingPathComponent("current_episode")
    }

    /// Persist the current podcast episode data
    static func setCurrentEpisode(_ data: [String: Any]?) {
        let path = currentEpisodeFilePath()
        guard let data = data else {
            try? FileManager.default.removeItem(atPath: path)
            return
        }
        do {
            let dir = queueDirectory()
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            var jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let unescaped = jsonString.replacingOccurrences(of: "\\/", with: "/")
                jsonData = unescaped.data(using: .utf8) ?? jsonData
            }
            try jsonData.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            print("[QueueStorage][ERROR] Failed to write current_episode: \(error.localizedDescription)")
        }
    }

    /// Read the persisted current podcast episode
    static func getCurrentEpisode() -> [String: Any]? {
        let path = currentEpisodeFilePath()
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json as? [String: Any]
        } catch {
            print("[QueueStorage][ERROR] Failed to read current_episode: \(error.localizedDescription)")
            return nil
        }
    }

    // Extract flattened data from a queue item for internal use (CarPlay UI, etc.)
    // The queue item has the mobile app structure: { data: { id, name, album: {...}, artists: [...], ... } }
    static func extractFlattenedData(_ item: [String: Any]) -> [String: Any] {
        guard let data = item["data"] as? [String: Any] else { return [:] }
        return mapQueueItem(data)
    }

    // Map the queue item JSON data (nested structure) to a flat structure for internal use
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

    // Load queue from disk in the original mobile app format, returning items and the current track id
    // Queue items maintain the mobile app structure: [{ "data": { id, name, album: {...}, artists: [...], ... } }, ...]
    static func loadQueueFromDisk(usingAttributes providedAttributes: [FileAttributeKey: Any]? = nil) -> ([[String: Any]], String?, Date?) {
        let path = queueFilePath()

        let exists = FileManager.default.fileExists(atPath: path)
        var attributes: [FileAttributeKey: Any]? = providedAttributes
        if attributes == nil, exists {
            attributes = try? FileManager.default.attributesOfItem(atPath: path)
        }

        guard exists else {
            return ([], currentTrackId(), nil)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                print("[QueueStorage][ERROR] invalid JSON array at \(path)")
                return ([], currentTrackId(), attributes?[.modificationDate] as? Date)
            }
            // Return items in their original format: [{ "data": { ...track... } }, ...]
            let currentId = currentTrackId()
            let modified = attributes?[.modificationDate] as? Date
            return (jsonArray, currentId, modified)
        } catch {
            print("[QueueStorage][ERROR] failed reading queue file: \(error.localizedDescription)")
            return ([], currentTrackId(), attributes?[.modificationDate] as? Date)
        }
    }
}
