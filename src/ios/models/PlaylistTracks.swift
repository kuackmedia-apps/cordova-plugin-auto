import Foundation

struct PlaylistTracks: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let name: String
    let curator: Curator?
    let tags: [Tag]
    let images: [CoverImage]
    let tracks: PlaylistTrackContainer

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, name, curator, tags, images, tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id may be number or string
        if let idStr = try? c.decode(String.self, forKey: .id) {
            self.id = idStr
        } else if let idNum = try? c.decode(Int64.self, forKey: .id) {
            self.id = String(idNum)
        } else {
            self.id = ""
        }
        self.itemType = (try? c.decode(String.self, forKey: .itemType)) ?? ""
        self.itemStyle = (try? c.decode(String.self, forKey: .itemStyle)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.curator = try? c.decode(Curator.self, forKey: .curator)
        self.tags = (try? c.decode([Tag].self, forKey: .tags)) ?? []
        self.images = (try? c.decode([CoverImage].self, forKey: .images)) ?? []
        self.tracks = (try? c.decode(PlaylistTrackContainer.self, forKey: .tracks)) ?? PlaylistTrackContainer(total: 0, offset: 0, limit: 0, items: [])
    }
}

struct PlaylistTrackContainer: Codable {
    let total: Int
    let offset: Int
    let limit: Int
    let items: [PlaylistTrack]

    private enum CodingKeys: String, CodingKey {
        case total, offset, limit, items, list
    }

    init(total: Int, offset: Int, limit: Int, items: [PlaylistTrack]) {
        self.total = total
        self.offset = offset
        self.limit = limit
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        self.offset = (try? c.decode(Int.self, forKey: .offset)) ?? 0
        self.limit = (try? c.decode(Int.self, forKey: .limit)) ?? 0
        if let it = try? c.decode([PlaylistTrack].self, forKey: .items) {
            self.items = it
        } else if let list = try? c.decode([PlaylistTrack].self, forKey: .list) {
            self.items = list
        } else {
            self.items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total, forKey: .total)
        try c.encode(offset, forKey: .offset)
        try c.encode(limit, forKey: .limit)
        try c.encode(items, forKey: .items)
    }
}

struct PlaylistTrack: MediaItem {
    let id: String
    let itemType: String
    let itemStyle: String
    let order: Int
    let createdAt: String
    let track: Track

    private enum CodingKeys: String, CodingKey {
        case id, itemType, itemStyle, order, createdAt, track
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
        self.itemType = (try? c.decode(String.self, forKey: .itemType)) ?? ""
        self.itemStyle = (try? c.decode(String.self, forKey: .itemStyle)) ?? ""
        self.order = (try? c.decode(Int.self, forKey: .order)) ?? 0
        self.createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        // 'track' must be present and valid; no fallback constructor exists for Track
        self.track = try c.decode(Track.self, forKey: .track)
    }
}
