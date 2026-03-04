import Foundation

protocol AuthenticationRepositoryProtocol {
    func authenticate(server: Server, method: AuthenticateMethod) -> AsyncStream<LoginState>
    func logout(user: any User) -> Bool
    func getUserImageUrl(server: Server, user: any User) -> String?
}

final class AuthenticationRepository: AuthenticationRepositoryProtocol {
    private let authenticationStore: AuthenticationStore
    private let authPreferences: AuthenticationPreferences
    private let serverClientFactory: MediaServerClientFactory
    private let sessionRepository: SessionRepositoryProtocol

    init(
        authenticationStore: AuthenticationStore,
        authPreferences: AuthenticationPreferences,
        serverClientFactory: MediaServerClientFactory,
        sessionRepository: SessionRepositoryProtocol
    ) {
        self.authenticationStore = authenticationStore
        self.authPreferences = authPreferences
        self.serverClientFactory = serverClientFactory
        self.sessionRepository = sessionRepository
    }

    func authenticate(server: Server, method: AuthenticateMethod) -> AsyncStream<LoginState> {
        switch method {
        case .automatic(let user):
            return authenticateAutomatic(server: server, user: user)
        case .credentials(let username, let password):
            return authenticateCredential(server: server, username: username, password: password)
        case .quickConnect(let secret):
            return authenticateQuickConnect(server: server, secret: secret)
        }
    }

    private func authenticateAutomatic(server: Server, user: any User) -> AsyncStream<LoginState> {
        AsyncStream { continuation in
            Task {
                if authPreferences.alwaysAuthenticate {
                    continuation.yield(.requireSignIn)
                    continuation.finish()
                    return
                }

                let storeUser = authenticationStore.getUser(server.id, user.id)
                if let token = storeUser?.accessToken {
                    let privateUser: PrivateUser
                    if let pu = user as? PrivateUser {
                        privateUser = pu.withToken(token)
                    } else {
                        privateUser = PrivateUser(
                            id: user.id, serverId: server.id, name: user.name,
                            accessToken: token, imageTag: user.imageTag, lastUsed: nil
                        )
                    }
                    for await state in self.authenticateToken(server: server, user: privateUser) {
                        continuation.yield(state)
                    }
                } else {
                    continuation.yield(.requireSignIn)
                }
                continuation.finish()
            }
        }
    }

    private func authenticateToken(server: Server, user: PrivateUser) -> AsyncStream<LoginState> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.authenticating)

                let success = await sessionRepository.switchCurrentSession(serverId: server.id, userId: user.id)
                if !success {
                    continuation.yield(server.versionSupported ? .requireSignIn : .versionNotSupported(server))
                    continuation.finish()
                    return
                }

                let client = serverClientFactory.configuredClient(
                    for: server, accessToken: user.accessToken ?? "", userId: user.id.uuidString
                )

                do {
                    let currentUser = try await client.authApi.getCurrentUser()
                    authenticateFinish(server: server, userInfo: currentUser, accessToken: user.accessToken ?? "")
                    continuation.yield(.authenticated)
                } catch let error as NetworkError where error.isUnavailable {
                    continuation.yield(.serverUnavailable)
                } catch {
                    continuation.yield(.apiClientError(error.localizedDescription))
                }
                continuation.finish()
            }
        }
    }

    private func authenticateCredential(server: Server, username: String, password: String) -> AsyncStream<LoginState> {
        AsyncStream { continuation in
            Task {
                let client = serverClientFactory.client(for: server)

                let result: AuthResult
                do {
                    result = try await client.authApi.authenticateByName(username: username, password: password)
                } catch let error as NetworkError where error.isUnavailable {
                    continuation.yield(.serverUnavailable)
                    continuation.finish()
                    return
                } catch {
                    continuation.yield(.apiClientError(error.localizedDescription))
                    continuation.finish()
                    return
                }

                for await state in self.authenticateResult(server: server, result: result) {
                    continuation.yield(state)
                }
                continuation.finish()
            }
        }
    }

    private func authenticateQuickConnect(server: Server, secret: String) -> AsyncStream<LoginState> {
        AsyncStream { continuation in
            Task {
                let client = serverClientFactory.client(for: server)

                let result: AuthResult
                do {
                    result = try await client.authApi.authenticateWithQuickConnect(secret: secret)
                } catch let error as NetworkError where error.isUnavailable {
                    continuation.yield(.serverUnavailable)
                    continuation.finish()
                    return
                } catch {
                    continuation.yield(.apiClientError(error.localizedDescription))
                    continuation.finish()
                    return
                }

                for await state in self.authenticateResult(server: server, result: result) {
                    continuation.yield(state)
                }
                continuation.finish()
            }
        }
    }

    private func authenticateResult(server: Server, result: AuthResult) -> AsyncStream<LoginState> {
        AsyncStream { continuation in
            Task {
                let accessToken = result.accessToken
                let userInfo = result.user
                let userId = UUID(uuidString: userInfo.id) ?? UUID()

                authenticateFinish(server: server, userInfo: userInfo, accessToken: accessToken)

                let success = await sessionRepository.switchCurrentSession(serverId: server.id, userId: userId)
                if success {
                    continuation.yield(.authenticated)
                } else if !server.versionSupported {
                    continuation.yield(.versionNotSupported(server))
                } else {
                    continuation.yield(.requireSignIn)
                }
                continuation.finish()
            }
        }
    }

    private func authenticateFinish(server: Server, userInfo: ServerUser, accessToken: String) {
        let userId = UUID(uuidString: userInfo.id) ?? UUID()
        let existing = authenticationStore.getUser(server.id, userId)

        let updated = AuthenticationStore.AuthStoreUser(
            name: userInfo.name,
            lastUsed: Date(),
            imageTag: userInfo.primaryImageTag ?? existing?.imageTag,
            accessToken: accessToken
        )
        authenticationStore.putUser(server.id, userId, updated)

        if var storeServer = authenticationStore.getServer(server.id) {
            storeServer.lastUsed = Date()
            authenticationStore.putServer(server.id, storeServer)
        }
    }

    func logout(user: any User) -> Bool {
        guard var storeUser = authenticationStore.getUser(user.serverId, user.id) else { return false }
        storeUser.accessToken = nil
        return authenticationStore.putUser(user.serverId, user.id, storeUser)
    }

    func getUserImageUrl(server: Server, user: any User) -> String? {
        guard let tag = user.imageTag else { return nil }
        let client = serverClientFactory.client(for: server)
        return client.imageApi.getUserImageUrl(
            userId: user.id.uuidString,
            imageType: .primary,
            tag: tag
        )
    }
}

private extension NetworkError {
    var isUnavailable: Bool {
        if case .serverUnavailable = self { return true }
        return false
    }
}
