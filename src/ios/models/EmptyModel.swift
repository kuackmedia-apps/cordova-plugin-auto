import Foundation

struct EmptyModel: MediaItem, Codable {
    let id: String
    let itemStyle: String
    let itemType: String

    private enum CodingKeys: String, CodingKey {
        case id, itemStyle, itemType
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
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? ""
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
    }
}
