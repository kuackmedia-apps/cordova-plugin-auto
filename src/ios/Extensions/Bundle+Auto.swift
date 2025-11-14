import Foundation

extension Bundle {
    var appGroupIdentifier: String? {
        return infoDictionary?["AppGroupIdentifier"] as? String
    }
}
