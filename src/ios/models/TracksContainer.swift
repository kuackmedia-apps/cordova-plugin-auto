import Foundation

struct TracksContainer: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let items: [Track]

    private enum CodingKeys: String, CodingKey {
        case total, offset, limit, items, list
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        if let it = try c.decodeIfPresent([Track].self, forKey: .items) {
            self.items = it
        } else if let list = try c.decodeIfPresent([Track].self, forKey: .list) {
            self.items = list
        } else {
            self.items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total, forKey: .total)
        try c.encode(offset, forKey: .offset)
        try c.encode(limit, forKey: .limit)
        try c.encode(items, forKey: .items)
    }
}
