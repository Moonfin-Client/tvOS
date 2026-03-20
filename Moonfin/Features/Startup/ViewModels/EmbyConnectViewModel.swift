import Foundation

@MainActor
final class EmbyConnectViewModel: ObservableObject {
    enum Phase: Equatable {
        case credentials
        case authenticating
        case loadingServers
        case serverList
        case connectingToServer
        case error(String)
    }

    @Published var phase: Phase = .credentials
    @Published var username = ""
    @Published var password = ""
    @Published var servers: [EmbyConnectServer] = []
    @Published var connectedServerId: UUID?

    private let connectService = EmbyConnectService()
    private let serverRepository: ServerRepositoryProtocol
    private let authenticationStore: AuthenticationStore

    private var connectAccessToken: String?
    private var connectUserId: String?

    init(serverRepository: ServerRepositoryProtocol, authenticationStore: AuthenticationStore) {
        self.serverRepository = serverRepository
        self.authenticationStore = authenticationStore
    }

    func login() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        phase = .authenticating
        Task {
            do {
                let result = try await connectService.authenticate(username: trimmed, password: password)
                connectAccessToken = result.accessToken
                connectUserId = result.user.id

                phase = .loadingServers
                let fetchedServers = try await connectService.getServers(
                    connectUserId: result.user.id,
                    connectAccessToken: result.accessToken
                )
                servers = fetchedServers

                if fetchedServers.count == 1 {
                    connectedServerId = await connectToServer(fetchedServers[0])
                } else {
                    phase = .serverList
                }
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    func selectServer(_ server: EmbyConnectServer) {
        Task {
            connectedServerId = await connectToServer(server)
        }
    }

    private func connectToServer(_ server: EmbyConnectServer) async -> UUID? {
        guard let connectUserId else {
            phase = .error("No server address available")
            return nil
        }

        let addresses = server.candidateAddresses
        guard !addresses.isEmpty else {
            phase = .error("No server address available")
            return nil
        }

        phase = .connectingToServer
        var lastError: Error?

        for address in addresses {
            do {
                let exchange = try await connectService.exchange(
                    serverAddress: address,
                    connectUserId: connectUserId,
                    accessKey: server.accessKey
                )

                var serverId: UUID?
                for await update in serverRepository.addServer(address: address) {
                    switch update {
                    case .connected(let id, _):
                        serverId = id
                    case .unableToConnect:
                        lastError = EmbyConnectError.networkError("Unable to connect to \(address)")
                    default:
                        break
                    }
                }

                guard let serverId else {
                    lastError = EmbyConnectError.networkError("Failed to add server at \(address)")
                    continue
                }

                guard let userId = UUID.from(rawId: exchange.localUserId) else {
                    phase = .error("Server returned an invalid local user id")
                    return nil
                }
                let user = AuthenticationStore.AuthStoreUser(
                    name: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastUsed: Date(),
                    accessToken: exchange.accessToken
                )
                authenticationStore.putUser(serverId, userId, user)

                return serverId
            } catch {
                lastError = error
            }
        }

        phase = .error(lastError?.localizedDescription ?? "Unable to connect to \(server.name)")
        return nil
    }

    func clearError() {
        if servers.isEmpty {
            phase = .credentials
        } else {
            phase = .serverList
        }
    }
}
