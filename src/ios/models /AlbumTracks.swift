import Foundation

struct AlbumTracks: Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let upc: String
    let title: String
    let subTitle: String?
    let releaseType: String?
    let lenght: String
    let tracksQty: Int
    let releaseDate: String
    let active: Bool
    let images: [CoverImage]
    let artists: [Artist]
    let tracks: TracksContainer
    let imageColorInfo: AnyCodable?
}
