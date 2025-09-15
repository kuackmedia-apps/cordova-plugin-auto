import Foundation

struct Artist: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let images: [CoverImage]?
    let active: Bool?
    let role: String?
    let score: Double?
    let imageColorInfo: ImageColorInfo?

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, name, images, active, role, score, imageColorInfo
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
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "artist"
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.images = try c.decodeIfPresent([CoverImage].self, forKey: .images)
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active)
        self.role = try c.decodeIfPresent(String.self, forKey: .role)
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.imageColorInfo = try c.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(itemType, forKey: .itemType)
        try c.encode(itemStyle, forKey: .itemStyle)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(images, forKey: .images)
        try c.encodeIfPresent(active, forKey: .active)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(imageColorInfo, forKey: .imageColorInfo)
    }
}
