import Foundation

struct PodcastShowResponse: Codable {
    let id: String
    let title: String?
    let image: String?
    let ourImage: String?
    let imageUrl: String?
    let episodes: [PodcastEpisode]?
    let episodesCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, image, ourImage, imageUrl, episodes, episodesCount
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
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.ourImage = try c.decodeIfPresent(String.self, forKey: .ourImage)
        self.imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        self.episodes = try c.decodeIfPresent([PodcastEpisode].self, forKey: .episodes)
        self.episodesCount = try c.decodeIfPresent(Int.self, forKey: .episodesCount)
    }
}
