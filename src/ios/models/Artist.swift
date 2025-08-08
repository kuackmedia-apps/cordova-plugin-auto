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
}
