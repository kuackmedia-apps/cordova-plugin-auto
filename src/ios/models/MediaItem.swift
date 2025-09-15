import Foundation

protocol MediaItem: Codable {
    var id: String { get }
    var itemType: String { get }
    var itemStyle: String { get }
}
