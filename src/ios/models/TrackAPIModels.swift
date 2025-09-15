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
    let idTrack: String
    let idAlbumTrack: String
    let idVideo: String?
    let isPreview: Bool
    let signedUrl: String
    let rights: [Right]

    enum CodingKeys: String, CodingKey {
        case idTrack
        case idAlbumTrack
        case idVideo
        case isPreview
        case signedUrl
        case rights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.idTrack = try Self.decodeString(forKey: .idTrack, in: container)
        self.idAlbumTrack = try Self.decodeString(forKey: .idAlbumTrack, in: container)
        // idVideo can be null, string or number
        if container.contains(.idVideo) {
            // Try decoding as concrete types (null yields nil via try?)
            if let s = try? container.decode(String.self, forKey: .idVideo) {
                self.idVideo = s
            } else if let i = try? container.decode(Int.self, forKey: .idVideo) {
                self.idVideo = String(i)
            } else if let d = try? container.decode(Double.self, forKey: .idVideo) {
                self.idVideo = String(Int(d))
            } else {
                self.idVideo = nil
            }
        } else {
            self.idVideo = nil
        }
        self.isPreview = try container.decode(Bool.self, forKey: .isPreview)
        self.signedUrl = try container.decode(String.self, forKey: .signedUrl)
        self.rights = (try? container.decode([Right].self, forKey: .rights)) ?? []
    }

    private static func decodeString(forKey key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let s = try? container.decode(String.self, forKey: key) {
            return s
        }
        if let i = try? container.decode(Int.self, forKey: key) {
            return String(i)
        }
        if let d = try? container.decode(Double.self, forKey: key) {
            // Avoid scientific notation
            let intVal = Int(d)
            return String(intVal)
        }
        // Last resort: decode as any and stringify
        let debugValue = try? container.decode(EmptyDecodable.self, forKey: key)
        throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: container.codingPath + [key], debugDescription: "Expected string/number for \(key.rawValue), got: \(String(describing: debugValue))"))
    }
}

struct Right: Codable {
    let idDist: Double
    let idLabel: Double
    let hadRight: Bool
}

// Helper to allow a fallback decode attempt in error messages
private struct EmptyDecodable: Decodable {}
