import Foundation

struct PlaylistTracks: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let curator: Curator?
    let tags: [Tag]
    let images: [CoverImage]
    let tracks: PlaylistTrackContainer
}

struct PlaylistTrackContainer: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let items: [PlaylistTrack]
}

struct PlaylistTrack: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let order: Int
    let createdAt: String
    let track: Track
}
