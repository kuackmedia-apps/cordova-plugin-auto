import Foundation

struct User: Codable {
    let id: Int64
    let name: String
    let country: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, country
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.country = try c.decodeIfPresent(String.self, forKey: .country)
    }
}
