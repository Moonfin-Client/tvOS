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
        if currentSession.value?.userId == userId,
           currentSession.value?.serverId == serverId {
            return true
        }

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
            if currentSession.value?.userId == session.userId,
               currentSession.value?.serverId == session.serverId {
                return true
            }

            let previousUser = userRepository.currentUser.value
            let previousServer = serverRepository.currentServer.value

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
                authPreferences.lastServerId = session.serverId.uuidString
                authPreferences.lastUserId = session.userId.uuidString
            } catch {
                userRepository.setCurrentUser(previousUser)
                serverRepository.currentServer.send(previousServer)
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
        if let serverId = UUID(uuidString: authPreferences.lastServerId),
           let userId = UUID(uuidString: authPreferences.lastUserId),
           let session = createUserSession(serverId: serverId, userId: userId) {
            return session
        }

        return createMostRecentStoredSession()
    }

    private func createMostRecentStoredSession() -> Session? {
        let servers = authenticationStore.getServers()
        var bestMatch: (session: Session, date: Date)?

        for (serverIdRaw, serverEntry) in servers {
            guard let serverId = UUID(uuidString: serverIdRaw) else { continue }

            for (userIdRaw, userEntry) in serverEntry.users {
                guard let userId = UUID(uuidString: userIdRaw),
                      let token = userEntry.accessToken,
                      !token.isEmpty else {
                    continue
                }

                let candidate = Session(userId: userId, serverId: serverId, accessToken: token)
                let candidateDate = userEntry.lastUsed ?? serverEntry.lastUsed ?? .distantPast

                if let currentBest = bestMatch {
                    if candidateDate > currentBest.date {
                        bestMatch = (candidate, candidateDate)
                    }
                } else {
                    bestMatch = (candidate, candidateDate)
                }
            }
        }

        return bestMatch?.session
    }

    private func createUserSession(serverId: UUID, userId: UUID) -> Session? {
        guard let user = authenticationStore.getUser(serverId, userId),
              let token = user.accessToken else {
            return nil
        }
        return Session(userId: userId, serverId: serverId, accessToken: token)
    }
}
