import Foundation

final class AuthenticationStore {
    private let fileURL: URL
    private var data: AuthStoreData

    struct AuthStoreData: Codable {
        var version: Int = 2
        var servers: [String: AuthStoreServer] = [:]
    }

    struct AuthStoreServer: Codable {
        var name: String
        var address: String
        var version: String?
        var lastUsed: Date?
        var users: [String: AuthStoreUser] = [:]
    }

    struct AuthStoreUser: Codable {
        var name: String
        var lastUsed: Date?
        var imageTag: String?
        var accessToken: String?
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("authentication_store.json")
        self.data = Self.load(from: fileURL)
    }

    private static func load(from url: URL) -> AuthStoreData {
        guard let fileData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AuthStoreData.self, from: fileData) else {
            return AuthStoreData()
        }
        return decoded
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL)
    }

    func getServers() -> [String: AuthStoreServer] { data.servers }

    func putServer(id: String, server: AuthStoreServer) {
        data.servers[id] = server
        save()
    }

    func removeServer(id: String) {
        data.servers.removeValue(forKey: id)
        save()
    }

    func getUsers(serverId: String) -> [String: AuthStoreUser] {
        data.servers[serverId]?.users ?? [:]
    }

    func putUser(serverId: String, userId: String, user: AuthStoreUser) {
        data.servers[serverId]?.users[userId] = user
        save()
    }

    func removeUser(serverId: String, userId: String) {
        data.servers[serverId]?.users.removeValue(forKey: userId)
        save()
    }
}
