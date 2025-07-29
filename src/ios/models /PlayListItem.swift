import Foundation

struct PlayListItem: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let followers: Int
    let active: Bool
    let curator: Curator?
    let user: AnyCodable?
    let updateDate: Int64
    let createDate: Int64
    let tags: [Tag]?
    let images: [CoverImage]
    let imageColorInfo: ImageColorInfo?
}
