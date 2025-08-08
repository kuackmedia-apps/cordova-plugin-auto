import Foundation

struct SearchResponse: Codable {
    let albums: AlbumResult
    let artists: ArtistResult
    let tracks: TrackResult
    let playlists: PlaylistResult
    let tags: TagResult
}

struct AlbumResult: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [AlbumItem]?
}

struct ArtistResult: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [Artist]?
}

struct TrackResult: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [Track]?
}

struct PlaylistResult: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [PlayListItem]?
}

struct TagResult: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [Tag]?
}
