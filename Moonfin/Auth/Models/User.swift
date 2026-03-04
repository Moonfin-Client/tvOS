import Foundation

protocol User: Identifiable {
    var id: UUID { get }
    var serverId: UUID { get }
    var name: String { get }
    var accessToken: String? { get }
    var imageTag: String? { get }
}

struct PrivateUser: User, Equatable {
    let id: UUID
    let serverId: UUID
    var name: String
    var accessToken: String?
    var imageTag: String?
    var lastUsed: Date?

    func withToken(_ token: String) -> PrivateUser {
        var copy = self
        copy.accessToken = token
        return copy
    }

    static func == (lhs: PrivateUser, rhs: PrivateUser) -> Bool {
        lhs.serverId == rhs.serverId && lhs.id == rhs.id
    }
}

struct PublicUser: User, Equatable {
    let id: UUID
    let serverId: UUID
    var name: String
    var accessToken: String?
    var imageTag: String?
    var hasPassword: Bool

    func withToken(_ token: String) -> PublicUser {
        var copy = self
        copy.accessToken = token
        return copy
    }

    static func == (lhs: PublicUser, rhs: PublicUser) -> Bool {
        lhs.serverId == rhs.serverId && lhs.id == rhs.id
    }
}
