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
        var serverType: ServerType
        var loginDisclaimer: String?
        var splashscreenEnabled: Bool
        var setupCompleted: Bool
        var lastUsed: Date?
        var lastRefreshed: Date?
        var users: [String: AuthStoreUser] = [:]

        init(
            name: String,
            address: String,
            version: String? = nil,
            serverType: ServerType = .jellyfin,
            loginDisclaimer: String? = nil,
            splashscreenEnabled: Bool = false,
            setupCompleted: Bool = true,
            lastUsed: Date? = nil,
            lastRefreshed: Date? = nil,
            users: [String: AuthStoreUser] = [:]
        ) {
            self.name = name
            self.address = address
            self.version = version
            self.serverType = serverType
            self.loginDisclaimer = loginDisclaimer
            self.splashscreenEnabled = splashscreenEnabled
            self.setupCompleted = setupCompleted
            self.lastUsed = lastUsed
            self.lastRefreshed = lastRefreshed
            self.users = users
        }
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

    func getServer(_ id: UUID) -> AuthStoreServer? { data.servers[id.uuidString] }

    @discardableResult
    func putServer(_ id: UUID, _ server: AuthStoreServer) -> Bool {
        data.servers[id.uuidString] = server
        save()
        return true
    }

    @discardableResult
    func removeServer(_ id: UUID) -> Bool {
        guard data.servers.removeValue(forKey: id.uuidString) != nil else { return false }
        save()
        return true
    }

    func getUsers(_ serverId: UUID) -> [String: AuthStoreUser]? {
        data.servers[serverId.uuidString]?.users
    }

    func getUser(_ serverId: UUID, _ userId: UUID) -> AuthStoreUser? {
        data.servers[serverId.uuidString]?.users[userId.uuidString]
    }

    @discardableResult
    func putUser(_ serverId: UUID, _ userId: UUID, _ user: AuthStoreUser) -> Bool {
        guard data.servers[serverId.uuidString] != nil else { return false }
        data.servers[serverId.uuidString]?.users[userId.uuidString] = user
        save()
        return true
    }

    @discardableResult
    func removeUser(_ serverId: UUID, _ userId: UUID) -> Bool {
        guard data.servers[serverId.uuidString]?.users.removeValue(forKey: userId.uuidString) != nil else { return false }
        save()
        return true
    }
}
