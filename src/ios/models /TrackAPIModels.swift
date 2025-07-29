import Foundation

struct TrackRequest: Codable {
    let idAlbumTrack: String
    let idTrack: String
    let forceDevice: Bool
    let useCloudFront: Bool
    let forcePreview: Bool
    let extraLife: Bool
}

struct TrackResponse: Codable {
    let idTrack: Double
    let idAlbumTrack: Double
    let idVideo: Double?
    let isPreview: Bool
    let signedUrl: String
    let rights: [Right]
}

struct Right: Codable {
    let idDist: Double
    let idLabel: Double
    let hadRight: Bool
}
