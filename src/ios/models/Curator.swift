import Foundation

struct Curator: Codable {
    let id: Int64
    let name: String

    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}
