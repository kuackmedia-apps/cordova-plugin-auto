import Foundation

struct HistoryResponse: Codable {
    let id: String
    let data: HistoryData
    let type: String
    let listenedDates: [Int64]
    let lastDateListened: Int64
}

struct HistoryData: Codable {
    let id: String
    let itemType: String
    let itemStyle: String
    let ttl: Int64?
    let upc: String?
    let title: String?
    let lenght: String?
    let name: String?
    let active: Bool?
    let images: [CoverImage]?
    let artists: [Artist]?
    let album: AlbumSummary?
    let subTitle: String?
    let tracksQty: Int?
    let releaseDate: String?
    let releaseType: String?
    let user: User?
    let owner: Bool?
    let curator: Curator?
    let followers: Int?
    let createDate: Int64?
    let updateDate: Int64?
    let from: String?
    let isGenre: Bool?
    let isStation: Bool?
    let sortDate: Int64?
    let amount: Int?
    let description: String?
    let imageColorInfo: ImageColorInfo?
    let indice: Int?
    let number: Int?
    let volume: Int?
    let version: String?
    let explicit: Bool?
}
