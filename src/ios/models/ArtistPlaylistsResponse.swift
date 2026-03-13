import Foundation

struct ArtistPlaylistsResponse: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [PlayListItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, limit, list
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        self.offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        self.limit = (try? c.decode(Int.self, forKey: .limit)) ?? 0
        self.list = (try? c.decode([PlayListItem].self, forKey: .list)) ?? []
    }
}
