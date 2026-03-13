import Foundation

struct PodcastShow: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let score: Double?
    let title: String?
    let name: String?
    let image: String?
    let ourImage: String?
    let imageUrl: String?
    let episodesCount: Int?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, score, title, name, image, ourImage, imageUrl, episodesCount, description
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
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "podcast"
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? "list"
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.ourImage = try c.decodeIfPresent(String.self, forKey: .ourImage)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.episodesCount = try c.decodeIfPresent(Int.self, forKey: .episodesCount)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
    }
}
