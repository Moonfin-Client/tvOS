import Foundation

enum User: Identifiable {
    case privateUser(id: UUID, name: String, accessToken: String?, lastUsed: Date?, imageTag: String?)
    case publicUser(id: UUID, name: String, hasPassword: Bool, imageTag: String?)

    var id: UUID {
        switch self {
        case .privateUser(let id, _, _, _, _): return id
        case .publicUser(let id, _, _, _): return id
        }
    }

    var name: String {
        switch self {
        case .privateUser(_, let name, _, _, _): return name
        case .publicUser(_, let name, _, _): return name
        }
    }

    var imageTag: String? {
        switch self {
        case .privateUser(_, _, _, _, let tag): return tag
        case .publicUser(_, _, _, let tag): return tag
        }
    }
}
