import Foundation
import Combine

struct Session: Equatable {
    let userId: UUID
    let serverId: UUID
    let accessToken: String
}

enum SessionState {
    case ready
    case restoringSession
    case switchingSession
}

protocol SessionRepositoryProtocol: AnyObject {
    var currentSession: CurrentValueSubject<Session?, Never> { get }
    var state: CurrentValueSubject<SessionState, Never> { get }
    var isAuthenticated: Bool { get }

    func restoreSession(destroyOnly: Bool) async
    func switchCurrentSession(serverId: UUID, userId: UUID) async -> Bool
    func destroyCurrentSession()
}

final class SessionRepository: SessionRepositoryProtocol {
    let currentSession = CurrentValueSubject<Session?, Never>(nil)
    let state = CurrentValueSubject<SessionState, Never>(.ready)

    var isAuthenticated: Bool { currentSession.value != nil }

    private let authPreferences: AuthenticationPreferences
    private let authenticationStore: AuthenticationStore
    private let serverClientFactory: MediaServerClientFactory
    private let userRepository: UserRepositoryProtocol
    private let serverRepository: ServerRepositoryProtocol

    init(
        authPreferences: AuthenticationPreferences,
        authenticationStore: AuthenticationStore,
        serverClientFactory: MediaServerClientFactory,
        userRepository: UserRepositoryProtocol,
        serverRepository: ServerRepositoryProtocol
    ) {
        self.authPreferences = authPreferences
        self.authenticationStore = authenticationStore
        self.serverClientFactory = serverClientFactory
        self.userRepository = userRepository
        self.serverRepository = serverRepository
    }

    func restoreSession(destroyOnly: Bool = false) async {
        state.send(.restoringSession)

        if authPreferences.alwaysAuthenticate || authPreferences.autoLoginBehavior == .disabled {
            destroyCurrentSession()
        } else if !destroyOnly {
            switch authPreferences.autoLoginBehavior {
            case .lastUser:
                await setCurrentSession(createLastUserSession())
            case .specificUser:
                if let sid = UUID(uuidString: authPreferences.autoLoginServerId),
                   let uid = UUID(uuidString: authPreferences.autoLoginUserId) {
                    await setCurrentSession(createUserSession(serverId: sid, userId: uid))
                }
            case .disabled:
                break
            }
        }

        state.send(.ready)
    }

    func switchCurrentSession(serverId: UUID, userId: UUID) async -> Bool {
        if currentSession.value?.userId == userId { return false }

        state.send(.switchingSession)

        guard let session = createUserSession(serverId: serverId, userId: userId) else {
            state.send(.ready)
            return false
        }

        let success = await setCurrentSession(session)
        state.send(.ready)
        return success
    }

    func destroyCurrentSession() {
        userRepository.setCurrentUser(nil)
        serverRepository.currentServer.send(nil)
        currentSession.send(nil)
        state.send(.ready)
    }

    @discardableResult
    private func setCurrentSession(_ session: Session?) async -> Bool {
        if let session {
            if currentSession.value?.userId == session.userId { return true }

            authPreferences.lastServerId = session.serverId.uuidString
            authPreferences.lastUserId = session.userId.uuidString

            guard let server = await serverRepository.getServer(id: session.serverId, eagerUpdate: true),
                  server.versionSupported else {
                return false
            }

            let client = serverClientFactory.configuredClient(
                for: server, accessToken: session.accessToken, userId: session.userId.uuidString
            )

            do {
                let user = try await client.authApi.getCurrentUser()
                userRepository.setCurrentUser(user)
                serverRepository.currentServer.send(server)
            } catch {
                userRepository.setCurrentUser(nil)
                serverRepository.currentServer.send(nil)
                return false
            }
        } else {
            userRepository.setCurrentUser(nil)
            serverRepository.currentServer.send(nil)
        }

        currentSession.send(session)
        return true
    }

    private func createLastUserSession() -> Session? {
        guard let serverId = UUID(uuidString: authPreferences.lastServerId),
              let userId = UUID(uuidString: authPreferences.lastUserId) else {
            return nil
        }
        return createUserSession(serverId: serverId, userId: userId)
    }

    private func createUserSession(serverId: UUID, userId: UUID) -> Session? {
        guard let user = authenticationStore.getUser(serverId, userId),
              let token = user.accessToken else {
            return nil
        }
        return Session(userId: userId, serverId: serverId, accessToken: token)
    }
}
