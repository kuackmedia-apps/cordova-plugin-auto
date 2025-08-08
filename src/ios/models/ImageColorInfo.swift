import Foundation

struct ImageColorInfo: Codable {
    let value: [Int]
    let rgb: String
    let rgba: String
    let hex: String
    let hexa: String
    let isDark: Bool
    let isLight: Bool
}
