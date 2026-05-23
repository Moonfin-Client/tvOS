import Foundation
import Combine

@MainActor
final class ServerViewModel: ObservableObject {
    @Published var server: Server?
    @Published var users: [any User] = []
    @Published var loginState: LoginState = .idle
    @Published var showPinEntry = false
    @Published var pinUser: (any User)? = nil
    @Published var authenticatingUser: (any User)? = nil
    @Published var notification: String? = nil
    private var didAttemptAutomaticLogin = false
    var suppressAutoLogin = false
    var preferredAutoLoginUserId: UUID?

    private let serverId: UUID
    private let serverRepository: ServerRepositoryProtocol
    private let serverUserRepository: ServerUserRepositoryProtocol
    private let authenticationRepository: AuthenticationRepositoryProtocol
    private let authPreferences: AuthenticationPreferences
    private let serverClientFactory: MediaServerClientFactory

    init(
        serverId: UUID,
        serverRepository: ServerRepositoryProtocol,
        serverUserRepository: ServerUserRepositoryProtocol,
        authenticationRepository: AuthenticationRepositoryProtocol,
        authPreferences: AuthenticationPreferences,
        serverClientFactory: MediaServerClientFactory
    ) {
        self.serverId = serverId
        self.serverRepository = serverRepository
        self.serverUserRepository = serverUserRepository
        self.authenticationRepository = authenticationRepository
        self.authPreferences = authPreferences
        self.serverClientFactory = serverClientFactory
    }

    func load() async {
        server = await serverRepository.getServer(id: serverId, eagerUpdate: true)
        guard let server else { return }

        updateNotification(for: server)
        await loadUsers(server: server)
    }

    private func updateNotification(for server: Server) {
        if !server.versionSupported {
            let minVersion = server.serverType == .jellyfin
                ? Server.minimumJellyfinVersion.description
                : Server.minimumEmbyVersion.description
            notification = Strings.serverUnsupportedVersionMinimum(server.version ?? Strings.unknown, minVersion)
        } else if !server.setupCompleted {
            notification = Strings.serverSetupIncomplete
        } else {
            notification = nil
        }
    }

    private func loadUsers(server: Server) async {
        let stored = serverUserRepository.getStoredServerUsers(server: server)
        let storedIds = Set(stored.map { $0.id })

        let allPublicUsers = await serverUserRepository.getPublicServerUsers(server: server)
        let publicUsers = allPublicUsers
            .filter { !storedIds.contains($0.id) }

        let sortBy = authPreferences.sortBy

        var merged: [any User] = stored + publicUsers
        merged.sort { a, b in
            if sortBy == .lastUsed {
                if let pa = a as? PrivateUser, let pb = b as? PrivateUser {
                    if let da = pa.lastUsed, let db = pb.lastUsed, da != db {
                        return da > db
                    }
                } else if a is PrivateUser {
                    return true
                } else if b is PrivateUser {
                    return false
                }
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        users = merged
        attemptAutomaticLoginIfNeeded(server: server, storedUsers: stored, publicUsers: allPublicUsers)
    }

    private func attemptAutomaticLoginIfNeeded(server: Server, storedUsers: [PrivateUser], publicUsers: [PublicUser]) {
        guard !didAttemptAutomaticLogin else { return }
        guard !suppressAutoLogin else { return }

        let publicUsersById = Dictionary(uniqueKeysWithValues: publicUsers.map { ($0.id, $0) })

        if let preferredUserId = preferredAutoLoginUserId {
            preferredAutoLoginUserId = nil
            if let preferredUser = storedUsers.first(where: { $0.id == preferredUserId && hasStoredToken($0) }) {
                didAttemptAutomaticLogin = true
                authenticate(user: preferredUser)
                return
            }
            if let preferredUser = publicUsersById[preferredUserId], !preferredUser.hasPassword {
                didAttemptAutomaticLogin = true
                loginWithoutPassword(user: preferredUser)
                return
            }
        }

        guard !authPreferences.alwaysAuthenticate else { return }

        let targetUserId: UUID?
        switch authPreferences.autoLoginBehavior {
        case .disabled:
            return
        case .lastUser:
            guard authPreferences.lastServerId == server.id.uuidString,
                  let userId = UUID(uuidString: authPreferences.lastUserId) else {
                targetUserId = nil
                break
            }
            targetUserId = userId
        case .specificUser:
            guard authPreferences.autoLoginServerId == server.id.uuidString,
                  let userId = UUID(uuidString: authPreferences.autoLoginUserId) else {
                return
            }
            targetUserId = userId
        }

        if let targetUserId {
            if let targetUser = storedUsers.first(where: { $0.id == targetUserId && hasStoredToken($0) }) {
                didAttemptAutomaticLogin = true
                authenticate(user: targetUser)
                return
            }

            if let targetUser = publicUsersById[targetUserId], !targetUser.hasPassword {
                didAttemptAutomaticLogin = true
                loginWithoutPassword(user: targetUser)
                return
            }

            return
        }

        // If no explicit last user exists yet, auto-login a single passwordless user.
        let passwordlessUsers = publicUsers.filter { !$0.hasPassword }
        if authPreferences.autoLoginBehavior == .lastUser,
           passwordlessUsers.count == 1,
           let passwordlessUser = passwordlessUsers.first {
            didAttemptAutomaticLogin = true
            loginWithoutPassword(user: passwordlessUser)
        }
    }

    private func hasStoredToken(_ user: PrivateUser) -> Bool {
        guard let token = user.accessToken else { return false }
        return !token.isEmpty
    }

    func authenticate(user: any User) {
        guard let server else { return }

        authenticatingUser = user
        loginState = .authenticating
        Task {
            for await state in authenticationRepository.authenticate(
                server: server,
                method: .automatic(user: user)
            ) {
                loginState = state
            }
        }
    }

    func loginWithoutPassword(user: any User) {
        guard let server else { return }

        authenticatingUser = user
        loginState = .authenticating
        Task {
            for await state in authenticationRepository.authenticate(
                server: server,
                method: .credentials(username: user.name, password: "")
            ) {
                loginState = state
            }
        }
    }

    func getUserImageUrl(_ user: any User) -> String? {
        guard let server else { return nil }
        return authenticationRepository.getUserImageUrl(server: server, user: user)
    }

    func logoutUser(_ user: any User) {
        _ = authenticationRepository.logout(user: user)
        guard let server else { return }
        Task { await loadUsers(server: server) }
    }

    func deleteUser(_ user: PrivateUser) {
        serverUserRepository.deleteStoredUser(user)
        guard let server else { return }
        Task { await loadUsers(server: server) }
    }
}
