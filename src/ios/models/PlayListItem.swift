import Foundation

struct PlayListItem: MediaItem, Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let followers: Int?
    let active: Bool?
    let curator: Curator?
    let user: User?
    let updateDate: Int64?
    let createDate: Int64?
    let tags: [Tag]?
    let images: [CoverImage]?
    let score: Double?
    let imageColorInfo: ImageColorInfo?

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, name, followers, active, curator, user, updateDate, createDate, tags, images, score, imageColorInfo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle id as either String or Int
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int64.self, forKey: .id) {
            id = String(intId)
        } else {
            id = ""
        }
        
        itemType = try container.decodeIfPresent(String.self, forKey: .itemType) ?? "playlist"
        itemStyle = try container.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        followers = try container.decodeIfPresent(Int.self, forKey: .followers)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        curator = try container.decodeIfPresent(Curator.self, forKey: .curator)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        // updateDate/createDate can arrive as Int64 or String
        if let v = try? container.decode(Int64.self, forKey: .updateDate) {
            updateDate = v
        } else if let s = try? container.decode(String.self, forKey: .updateDate), let v = Int64(s) {
            updateDate = v
        } else {
            updateDate = nil
        }
        if let v = try? container.decode(Int64.self, forKey: .createDate) {
            createDate = v
        } else if let s = try? container.decode(String.self, forKey: .createDate), let v = Int64(s) {
            createDate = v
        } else {
            createDate = nil
        }
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags)
        images = try container.decodeIfPresent([CoverImage].self, forKey: .images)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        imageColorInfo = try container.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }
}
