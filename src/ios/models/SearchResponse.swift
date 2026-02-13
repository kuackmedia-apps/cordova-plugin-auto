import Foundation

struct SearchResponse: Codable {
    /// The single "best" item - can be artist, album, playlist, tag or track
    let best: AnyMediaItem?
    let albums: AlbumResult?
    let artists: ArtistResult?
    let tracks: TrackResult?
    let playlists: PlaylistResult?
    let tags: TagResult?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.best = try container.decodeIfPresent(AnyMediaItem.self, forKey: .best)
        self.albums = try container.decodeIfPresent(AlbumResult.self, forKey: .albums)
        self.artists = try container.decodeIfPresent(ArtistResult.self, forKey: .artists)
        self.tracks = try container.decodeIfPresent(TrackResult.self, forKey: .tracks)
        self.playlists = try container.decodeIfPresent(PlaylistResult.self, forKey: .playlists)
        self.tags = try container.decodeIfPresent(TagResult.self, forKey: .tags)
    }
}

struct AlbumResult: Codable {
    let total: Int?
    let offset: Int?
    let limit: Int?
    let list: [AlbumItem]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        self.list = try container.decodeIfPresent([AlbumItem].self, forKey: .list)
    }
}

struct ArtistResult: Codable {
    let total: Int?
    let offset: Int?
    let limit: Int?
    let list: [Artist]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        self.list = try container.decodeIfPresent([Artist].self, forKey: .list)
    }
}

struct TrackResult: Codable {
    let total: Int?
    let offset: Int?
    let limit: Int?
    let list: [Track]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        self.list = try container.decodeIfPresent([Track].self, forKey: .list)
    }
}

struct PlaylistResult: Codable {
    let total: Int?
    let offset: Int?
    let limit: Int?
    let list: [PlayListItem]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        self.list = try container.decodeIfPresent([PlayListItem].self, forKey: .list)
    }
}

struct TagResult: Codable {
    let total: Int?
    let offset: Int?
    let limit: Int?
    let list: [Tag]?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        self.list = try container.decodeIfPresent([Tag].self, forKey: .list)
    }
}
