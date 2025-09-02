import Foundation

struct AlbumTracks: Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let upc: String
    let title: String
    let subTitle: String?
    let releaseType: String?
    let lenght: String
    let tracksQty: Int
    let releaseDate: String
    let active: Bool
    let images: [CoverImage]
    let artists: [Artist]
    let tracks: TracksContainer
    let imageColorInfo: ImageColorInfo?

    enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, upc, title, subTitle, releaseType, lenght, tracksQty, releaseDate, active, images, artists, tracks, imageColorInfo
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
        self.itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "album"
        self.itemStyle = try c.decodeIfPresent(String.self, forKey: .itemStyle) ?? ""
        self.upc = try c.decodeIfPresent(String.self, forKey: .upc) ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.subTitle = try c.decodeIfPresent(String.self, forKey: .subTitle)
        self.releaseType = try c.decodeIfPresent(String.self, forKey: .releaseType)
        self.lenght = try c.decodeIfPresent(String.self, forKey: .lenght) ?? ""
        self.tracksQty = try c.decodeIfPresent(Int.self, forKey: .tracksQty) ?? 0
        self.releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
        self.active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        self.images = try c.decodeIfPresent([CoverImage].self, forKey: .images) ?? []
        self.artists = try c.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        self.tracks = try c.decode(TracksContainer.self, forKey: .tracks)
        self.imageColorInfo = try c.decodeIfPresent(ImageColorInfo.self, forKey: .imageColorInfo)
    }
}
