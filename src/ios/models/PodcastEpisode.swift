import Foundation

struct PodcastEnclosure: Codable {
    let url: String?
    let type: String?
}

struct PodcastEpisode: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let score: Double?
    let title: String
    let showId: String?
    let showTitle: String?
    let description: String?
    let datePublished: String?
    let duration: String?
    let durationMs: Int64?
    let image: String?
    let ourImage: String?
    let isPodcast: Bool
    let enclosure: PodcastEnclosure?

    /// Convenience: audio URL from enclosure
    var enclosureUrl: String? {
        return enclosure?.url
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, score, title, showId, showTitle, description, datePublished, duration, durationMs, image, ourImage, isPodcast, enclosure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id: may come as String or Number
        if let idStr = try? c.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idNum = try? c.decode(Int64.self, forKey: .id) {
            self.id = String(idNum)
        } else {
            self.id = ""
        }
        self.itemType = (try? c.decode(String.self, forKey: .itemType)) ?? "podcast_episode"
        self.itemStyle = (try? c.decode(String.self, forKey: .itemStyle)) ?? "list"
        self.score = try? c.decode(Double.self, forKey: .score)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        // showId: may come as String or Number
        if let sid = try? c.decode(String.self, forKey: .showId) {
            self.showId = sid
        } else if let sidNum = try? c.decode(Int64.self, forKey: .showId) {
            self.showId = String(sidNum)
        } else {
            self.showId = nil
        }
        self.showTitle = try? c.decode(String.self, forKey: .showTitle)
        self.description = try? c.decode(String.self, forKey: .description)
        self.datePublished = try? c.decode(String.self, forKey: .datePublished)
        self.duration = try? c.decode(String.self, forKey: .duration)
        // durationMs: may come as Int64 or String
        if let ms = try? c.decode(Int64.self, forKey: .durationMs) {
            self.durationMs = ms
        } else if let msStr = try? c.decode(String.self, forKey: .durationMs), let ms = Int64(msStr) {
            self.durationMs = ms
        } else {
            self.durationMs = nil
        }
        self.image = try? c.decode(String.self, forKey: .image)
        self.ourImage = try? c.decode(String.self, forKey: .ourImage)
        self.isPodcast = (try? c.decode(Bool.self, forKey: .isPodcast)) ?? true
        self.enclosure = try? c.decode(PodcastEnclosure.self, forKey: .enclosure)
    }
}
