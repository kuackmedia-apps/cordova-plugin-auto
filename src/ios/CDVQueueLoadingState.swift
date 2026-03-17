import Foundation

/// Tracks the pagination state for dynamic queue loading.
/// Mirrors Android's QueueLoadingState.kt
struct CDVQueueLoadingState {
    var contentType: String       // "ALBUM", "PLAYLIST", "ARTIST", "RADIO", "TRACK_RADIO"
    let contentId: String
    let contentName: String
    var currentOffset: Int = 0
    var lastIdAlbumTrack: String? // For RADIO (cursor-based pagination)
    var hasMore: Bool = true
    var isLoading: Bool = false
    var totalExpected: Int?       // Total tracks reported by API (for Now Playing UI)

    // For TRACK_RADIO (post-context continuation)
    var excludeAlbumTrackIds: [Int64] = []  // Avoid duplicates
    var seedAlbumTrackIds: [Int64] = []     // Initial seeds for recommendations
}
