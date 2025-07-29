import Foundation

struct Tag: MediaItem {
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
    let amount: AnyCodable?
    let imageColorInfo: ImageColorInfo?
}
