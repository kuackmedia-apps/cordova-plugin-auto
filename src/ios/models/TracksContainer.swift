import Foundation

struct TracksContainer: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let items: [Track]
}
