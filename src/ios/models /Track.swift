import Foundation

struct Track: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let idAlbumTrack: Int64?
    let isrc: String?
    let name: String
    let version: String?
    let length: String
    let explicit: Bool
    let active: Bool
    let album: AlbumSummary?
    let artists: [Artist]
    let volume: Int?
    let number: Int?
    let hasRelatedTracks: Bool
    let score: Double?
    let imageColorInfo: ImageColorInfo?
    let context: ContextData?
}
