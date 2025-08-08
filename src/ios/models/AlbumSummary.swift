import Foundation

struct AlbumSummary: Codable {
    let id: Int64
    let upc: String?
    let score: Double?
    let title: String?
    let active: Bool?
    let images: [CoverImage]?
    let artists: [Artist]?
    let itemType: String?
    let subTitle: String?
    let tracksQty: Int?
    let releaseDate: String?
    let imageColorInfo: ImageColorInfo?
}
