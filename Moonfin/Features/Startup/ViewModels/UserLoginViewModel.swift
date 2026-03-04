import Foundation
import Combine

@MainActor
final class UserLoginViewModel: ObservableObject {
    @Published var server: Server?
    @Published var loginState: LoginState = .idle
    @Published var quickConnectState: QuickConnectState = .unknown
    @Published var isQuickConnectSupported = true
    @Published var username = ""
    @Published var password = ""
    @Published var quickConnectCode = ""

    var forcedUsername: String?

    private let serverRepository: ServerRepositoryProtocol
    private let authenticationRepository: AuthenticationRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory

    private var quickConnectSecret: String?
    private var quickConnectTask: Task<Void, Never>?

    init(
        serverId: UUID,
        username: String?,
        serverRepository: ServerRepositoryProtocol,
        authenticationRepository: AuthenticationRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory
    ) {
        self.serverRepository = serverRepository
        self.authenticationRepository = authenticationRepository
        self.serverClientFactory = serverClientFactory
        self.forcedUsername = username

        if let username {
            self.username = username
        }

        Task {
            self.server = await serverRepository.getServer(id: serverId, eagerUpdate: false)
            if let server {
                isQuickConnectSupported = server.serverType.supports(.quickConnect)
            }
        }
    }

    func login() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, let server else { return }

        loginState = .authenticating
        Task {
            for await state in authenticationRepository.authenticate(
                server: server,
                method: .credentials(username: trimmedUsername, password: password)
            ) {
                loginState = state
            }
        }
    }

    func clearLoginState() {
        loginState = .idle
        quickConnectState = .unknown
    }

    func initiateQuickConnect() {
        guard quickConnectState == .unknown, let server else { return }

        let client = serverClientFactory.client(for: server)

        quickConnectTask = Task {
            do {
                guard let info = try await client.authApi.initiateQuickConnect() else {
                    quickConnectState = .unavailable
                    return
                }
                quickConnectSecret = info.secret
                quickConnectCode = formatCode(info.code)
                quickConnectState = .pending(code: info.code)

                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard let secret = quickConnectSecret else { break }

                    let authenticated = try await client.authApi.checkQuickConnectStatus(secret: secret)
                    if authenticated {
                        quickConnectState = .connected
                        await authenticateWithQuickConnect(secret: secret)
                        break
                    }
                }
            } catch {
                quickConnectState = .unavailable
            }
        }
    }

    private func authenticateWithQuickConnect(secret: String) async {
        guard let server else { return }

        for await state in authenticationRepository.authenticate(
            server: server,
            method: .quickConnect(secret: secret)
        ) {
            loginState = state
        }
    }

    func stopQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectSecret = nil
    }

    private func formatCode(_ code: String) -> String {
        var result = ""
        for (index, char) in code.enumerated() {
            if index != 0, index % 3 == 0 { result += " " }
            result.append(char)
        }
        return result
    }

    deinit {
        quickConnectTask?.cancel()
    }
}
