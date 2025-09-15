import Foundation

// A type-erased MediaItem that can decode/encode concrete types based on the `itemType` discriminator
struct AnyMediaItem: MediaItem, Codable {
    private let base: MediaItem

    // Forward protocol requirements
    var id: String { base.id }
    var itemType: String { base.itemType }
    var itemStyle: String { base.itemStyle }

    init(_ base: MediaItem) {
        self.base = base
    }

    private enum ProbeKeys: String, CodingKey { case itemType }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ProbeKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .itemType)
        switch type {
        case "track":
            self.base = try Track(from: decoder)
        case "playlist":
            self.base = try PlayListItem(from: decoder)
        case "tag":
            self.base = try Tag(from: decoder)
        case "album":
            self.base = try AlbumItem(from: decoder)
        case "artist":
            self.base = try Artist(from: decoder)
        default:
            // Fallback to minimal model if unknown
            self.base = try EmptyModel(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        // Encode using the underlying concrete type when possible
        switch base {
        case let v as Track: try v.encode(to: encoder)
        case let v as PlayListItem: try v.encode(to: encoder)
        case let v as Tag: try v.encode(to: encoder)
        case let v as AlbumItem: try v.encode(to: encoder)
        case let v as Artist: try v.encode(to: encoder)
        case let v as EmptyModel: try v.encode(to: encoder)
        default:
            // Unknown type: encode the minimal fields
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(base.id, forKey: .id)
            try container.encode(base.itemType, forKey: .itemType)
            try container.encode(base.itemStyle, forKey: .itemStyle)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle
    }
}
