import Foundation

struct RelatedTracksByQueueRequest: Codable {
    let sources: [String]
    let albumTrackIds: [Int64]
    let excludeAlbumTrackIds: [Int64]
    let seedAlbumTrackIds: [Int64]

    private enum CodingKeys: String, CodingKey {
        case sources
        case albumTrackIds = "album_track_ids"
        case excludeAlbumTrackIds = "exclude_album_track_ids"
        case seedAlbumTrackIds = "seed_album_track_ids"
    }

    init(
        albumTrackIds: [Int64],
        excludeAlbumTrackIds: [Int64] = [],
        seedAlbumTrackIds: [Int64] = [],
        sources: [String] = ["cm", "stats", "playlists"]
    ) {
        self.sources = sources
        self.albumTrackIds = albumTrackIds
        self.excludeAlbumTrackIds = excludeAlbumTrackIds
        self.seedAlbumTrackIds = seedAlbumTrackIds
    }
}
