import Foundation

struct PodcastEpisode: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let score: Double?
    let title: String?
    let showId: String?
    let showTitle: String?
    let description: String?
    let datePublished: String?
    let duration: String?
    let durationMs: Int64?
    let image: String?
    let ourImage: String?
    let isPodcast: Bool

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, score, title, showId, showTitle, description, datePublished, duration, durationMs, image, ourImage, isPodcast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? c.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idNum = try? c.decode(Int64.self, forKey: .id) {
            self.id = String(idNum)
        } else {
            self.id = ""
        }
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "podcast_episode"
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? "list"
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.showId = try c.decodeIfPresent(String.self, forKey: .showId)
        self.showTitle = try c.decodeIfPresent(String.self, forKey: .showTitle)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.datePublished = try c.decodeIfPresent(String.self, forKey: .datePublished)
        self.duration = try c.decodeIfPresent(String.self, forKey: .duration)
        self.durationMs = try c.decodeIfPresent(Int64.self, forKey: .durationMs)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.ourImage = try c.decodeIfPresent(String.self, forKey: .ourImage)
        self.isPodcast = try c.decodeIfPresent(Bool.self, forKey: .isPodcast) ?? true
    }
}
