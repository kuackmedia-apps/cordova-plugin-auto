import Foundation

struct ArtistAlbumsResponse: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [AlbumItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, limit, list
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        self.offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        self.limit = (try? c.decode(Int.self, forKey: .limit)) ?? 0
        self.list = (try? c.decode([AlbumItem].self, forKey: .list)) ?? []
    }
}
