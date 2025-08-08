import Foundation

struct AlbumItem: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let upc: String?
    let title: String
    let subTitle: String?
    let tracksQty: Int?
    let releaseDate: String
    let active: Bool
    let images: [CoverImage]
    let artists: [Artist]
    let score: Double?
    let imageColorInfo: ImageColorInfo?
}
