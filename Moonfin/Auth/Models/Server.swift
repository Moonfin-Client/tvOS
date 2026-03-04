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

struct ServerVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init(_ string: String) {
        components = string.split(separator: ".").compactMap { Int($0) }
    }

    init(_ parts: Int...) {
        components = parts
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

struct Server: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var address: String
    var version: String?
    var serverType: ServerType
    var loginDisclaimer: String?
    var splashscreenEnabled: Bool
    var setupCompleted: Bool
    var dateLastAccessed: Date?

    static let minimumJellyfinVersion = ServerVersion(10, 10, 0)
    static let minimumEmbyVersion = ServerVersion(4, 8, 0, 0)

    var serverVersion: ServerVersion? {
        version.map { ServerVersion($0) }
    }

    var versionSupported: Bool {
        guard let sv = serverVersion else { return false }
        switch serverType {
        case .jellyfin: return sv >= Self.minimumJellyfinVersion
        case .emby: return sv >= Self.minimumEmbyVersion
        }
    }

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id && lhs.address == rhs.address
    }
}
