import Foundation

struct AlbumItem: MediaItem, Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let upc: String?
    let title: String
    let subTitle: String?
    let tracksQty: Int?
    let releaseDate: String?
    let active: Bool?
    let images: [CoverImage]?
    let artists: [Artist]?
    let score: Double?
    let imageColorInfo: ImageColorInfo?
    
    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, upc, title, subTitle, tracksQty, releaseDate, active, images, artists, score, imageColorInfo
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
        
        itemType = try container.decodeIfPresent(String.self, forKey: .itemType) ?? "album"
        itemStyle = try container.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        upc = try container.decodeIfPresent(String.self, forKey: .upc)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subTitle = try container.decodeIfPresent(String.self, forKey: .subTitle)
        tracksQty = try container.decodeIfPresent(Int.self, forKey: .tracksQty)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        images = try container.decodeIfPresent([CoverImage].self, forKey: .images)
        artists = try container.decodeIfPresent([Artist].self, forKey: .artists)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        imageColorInfo = try container.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }
}
