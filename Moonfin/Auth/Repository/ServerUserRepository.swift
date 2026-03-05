import Foundation

protocol ServerUserRepositoryProtocol {
    func getStoredServerUsers(server: Server) -> [PrivateUser]
    func getPublicServerUsers(server: Server) async -> [PublicUser]
    func deleteStoredUser(_ user: PrivateUser)
}

final class ServerUserRepository: ServerUserRepositoryProtocol {
    private let authenticationStore: AuthenticationStore
    private let serverClientFactory: MediaServerClientFactory

    init(authenticationStore: AuthenticationStore, serverClientFactory: MediaServerClientFactory) {
        self.authenticationStore = authenticationStore
        self.serverClientFactory = serverClientFactory
    }

    func getStoredServerUsers(server: Server) -> [PrivateUser] {
        guard let users = authenticationStore.getUsers(server.id) else { return [] }

        return users.compactMap { (userIdString, userInfo) -> PrivateUser? in
            guard let userId = UUID.from(rawId: userIdString) else { return nil }
            return PrivateUser(
                id: userId,
                serverId: server.id,
                name: userInfo.name,
                accessToken: userInfo.accessToken,
                imageTag: userInfo.imageTag,
                lastUsed: userInfo.lastUsed
            )
        }
        .sorted {
            if let d1 = $0.lastUsed, let d2 = $1.lastUsed, d1 != d2 { return d1 > d2 }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func getPublicServerUsers(server: Server) async -> [PublicUser] {
        let client = serverClientFactory.client(for: server)
        do {
            let serverUsers = try await client.authApi.getPublicUsers()
            return serverUsers.map { dto in
                PublicUser(
                    id: UUID.from(rawId: dto.id) ?? UUID(),
                    serverId: server.id,
                    name: dto.name,
                    accessToken: nil,
                    imageTag: dto.primaryImageTag,
                    hasPassword: dto.hasConfiguredPassword ?? dto.hasPassword ?? false
                )
            }
        } catch {
            return []
        }
    }

    func deleteStoredUser(_ user: PrivateUser) {
        authenticationStore.removeUser(user.serverId, user.id)
    }
}
