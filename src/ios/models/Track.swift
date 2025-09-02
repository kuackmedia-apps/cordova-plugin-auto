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

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, idAlbumTrack, isrc, name, version, length, explicit, active, album, artists, volume, number, hasRelatedTracks, score, imageColorInfo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? c.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idNum = try? c.decode(Int64.self, forKey: .id) {
            self.id = String(idNum)
        } else {
            self.id = ""
        }
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "track"
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        self.idAlbumTrack = try c.decodeIfPresent(Int64.self, forKey: .idAlbumTrack)
        self.isrc = try c.decodeIfPresent(String.self, forKey: .isrc)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.version = try c.decodeIfPresent(String.self, forKey: .version)
        self.length = try c.decodeIfPresent(String.self, forKey: .length) ?? ""
        self.explicit = try c.decodeIfPresent(Bool.self, forKey: .explicit) ?? false
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        self.album = try c.decodeIfPresent(AlbumSummary.self, forKey: .album)
        self.artists = try c.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        self.volume = try c.decodeIfPresent(Int.self, forKey: .volume)
        self.number = try c.decodeIfPresent(Int.self, forKey: .number)
        self.hasRelatedTracks = try c.decodeIfPresent(Bool.self, forKey: .hasRelatedTracks) ?? false
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.imageColorInfo = try c.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }
}
