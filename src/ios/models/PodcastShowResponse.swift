import Foundation

struct PodcastShowResponse: Decodable {
    let id: String
    let title: String?
    let image: String?
    let ourImage: String?
    let imageUrl: String?
    let episodes: [PodcastEpisode]
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
        self.episodesCount = try c.decodeIfPresent(Int.self, forKey: .episodesCount)
        // Decode episodes defensively: skip individual episodes that fail to decode
        if var unkeyedContainer = try? c.nestedUnkeyedContainer(forKey: .episodes) {
            var eps: [PodcastEpisode] = []
            while !unkeyedContainer.isAtEnd {
                if let ep = try? unkeyedContainer.decode(PodcastEpisode.self) {
                    eps.append(ep)
                } else {
                    // Skip the malformed element by decoding it as a throwaway JSON value
                    _ = try? unkeyedContainer.decode(AnyCodable.self)
                }
            }
            self.episodes = eps
        } else {
            self.episodes = []
        }
    }
}

/// Helper to skip arbitrary JSON values during decoding
private struct AnyCodable: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let _ = try? container.decode(Bool.self) { return }
        if let _ = try? container.decode(Int.self) { return }
        if let _ = try? container.decode(Double.self) { return }
        if let _ = try? container.decode(String.self) { return }
        if let _ = try? container.decode([AnyCodable].self) { return }
        if let _ = try? container.decode([String: AnyCodable].self) { return }
    }
}
