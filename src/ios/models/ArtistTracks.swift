import Foundation

struct ArtistTracks: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let list: [Track]
}
