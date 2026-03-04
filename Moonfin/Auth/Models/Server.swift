import Foundation

enum ServerType: String, Codable {
    case jellyfin
    case emby

    static func detect(productName: String?, version: String?) -> ServerType {
        if let productName, productName.localizedCaseInsensitiveContains("Jellyfin") {
            return .jellyfin
        }
        if let productName, productName.localizedCaseInsensitiveContains("Emby") {
            return .emby
        }
        if let version {
            let parts = version.split(separator: ".")
            if parts.count >= 4, let major = Int(parts[0]), major < 10 {
                return .emby
            }
        }
        return .jellyfin
    }
}

struct Server: Codable, Identifiable {
    let id: UUID
    var name: String
    var address: String
    var version: String?
    var serverType: ServerType
    var loginDisclaimer: String?
    var dateLastAccessed: Date?
}
