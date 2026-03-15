import Foundation

struct Tag: MediaItem, Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let description: String
    let isGenre: Bool
    let isStation: Bool
    let images: [CoverImage]
    let updateDate: Int64
    let imageUpdateDate: Int64
    let amount: Int64?
    let score: Double?
    let imageColorInfo: ImageColorInfo?

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, name, description, isGenre, isStation
        case images, updateDate, imageUpdateDate, amount, score, imageColorInfo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id can arrive as String or Int
        if let idStr = try? c.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idNum = try? c.decode(Int64.self, forKey: .id) {
            self.id = String(idNum)
        } else {
            self.id = ""
        }
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? ""
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.isGenre = try c.decodeIfPresent(Bool.self, forKey: .isGenre) ?? false
        self.isStation = try c.decodeIfPresent(Bool.self, forKey: .isStation) ?? false
        self.images = try c.decodeIfPresent([CoverImage].self, forKey: .images) ?? []
        self.updateDate = try c.decodeIfPresent(Int64.self, forKey: .updateDate) ?? 0
        self.imageUpdateDate = try c.decodeIfPresent(Int64.self, forKey: .imageUpdateDate) ?? 0
        self.amount = try c.decodeIfPresent(Int64.self, forKey: .amount)
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.imageColorInfo = try c.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }
}
