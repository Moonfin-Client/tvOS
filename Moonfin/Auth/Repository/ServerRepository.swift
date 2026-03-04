import Foundation
import Combine

protocol ServerRepositoryProtocol {
    var storedServers: CurrentValueSubject<[Server], Never> { get }
    var currentServer: CurrentValueSubject<Server?, Never> { get }

    func loadStoredServers()
    func addServer(address: String) -> AsyncStream<ServerAdditionState>
    func getServer(id: UUID, eagerUpdate: Bool) async -> Server?
    func updateServer(_ server: Server, force: Bool) async -> Bool
    func deleteServer(id: UUID) -> Bool
}

final class ServerRepository: ServerRepositoryProtocol {
    let storedServers = CurrentValueSubject<[Server], Never>([])
    let currentServer = CurrentValueSubject<Server?, Never>(nil)

    private let authenticationStore: AuthenticationStore
    private let serverClientFactory: MediaServerClientFactory

    private static let refreshInterval: TimeInterval = 600

    init(authenticationStore: AuthenticationStore, serverClientFactory: MediaServerClientFactory) {
        self.authenticationStore = authenticationStore
        self.serverClientFactory = serverClientFactory
    }

    func loadStoredServers() {
        let servers = authenticationStore.getServers()
            .compactMap { (idString, entry) -> Server? in
                guard let id = UUID(uuidString: idString) else { return nil }
                return entry.asServer(id: id)
            }
            .sorted {
                if let d1 = $0.dateLastAccessed, let d2 = $1.dateLastAccessed, d1 != d2 {
                    return d1 > d2
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        storedServers.send(servers)
    }

    func addServer(address: String) -> AsyncStream<ServerAdditionState> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.connecting(address: address))

                let candidates = Self.addressCandidates(for: address)
                var connectedServer: (id: UUID, info: PublicSystemInfo, address: String)?

                for candidate in candidates {
                    let client = HttpClient(baseURL: URL(string: candidate))
                    do {
                        let info: PublicSystemInfo = try await client.request("/System/Info/Public")
                        let serverType = ServerType.detect(productName: info.productName, version: info.version)

                        // Skip if Jellyfin SDK would've scored this as BAD for non-Emby
                        if serverType == .jellyfin {
                            let version = ServerVersion(info.version)
                            if version < Server.minimumJellyfinVersion {
                                continue
                            }
                        }

                        guard let id = UUID(uuidString: info.id) else { continue }
                        connectedServer = (id, info, candidate)
                        break
                    } catch {
                        continue
                    }
                }

                if let result = connectedServer {
                    let defaultName = result.info.serverName
                    let detectedType = ServerType.detect(productName: result.info.productName, version: result.info.version)

                    var storeServer = self.authenticationStore.getServer(result.id) ?? AuthenticationStore.AuthStoreServer(
                        name: defaultName,
                        address: result.address,
                        serverType: detectedType
                    )
                    storeServer.name = defaultName
                    storeServer.address = result.address
                    storeServer.version = result.info.version
                    storeServer.setupCompleted = result.info.startupWizardCompleted ?? true
                    storeServer.lastUsed = Date()
                    storeServer.serverType = detectedType

                    self.authenticationStore.putServer(result.id, storeServer)
                    self.loadStoredServers()
                    continuation.yield(.connected(id: result.id, name: defaultName))
                } else {
                    continuation.yield(.unableToConnect(candidates: candidates))
                }

                continuation.finish()
            }
        }
    }

    func getServer(id: UUID, eagerUpdate: Bool = false) async -> Server? {
        guard let storeServer = authenticationStore.getServer(id) else { return nil }

        if let updated = await updateServerInternal(id: id, server: storeServer, force: eagerUpdate) {
            return updated.asServer(id: id)
        }

        return storeServer.asServer(id: id)
    }

    func updateServer(_ server: Server, force: Bool = false) async -> Bool {
        guard let storeServer = authenticationStore.getServer(server.id) else { return false }
        return await updateServerInternal(id: server.id, server: storeServer, force: force) != nil
    }

    @discardableResult
    func deleteServer(id: UUID) -> Bool {
        let success = authenticationStore.removeServer(id)
        if success {
            serverClientFactory.removeClient(for: id)
            loadStoredServers()
        }
        return success
    }

    private func updateServerInternal(
        id: UUID,
        server: AuthenticationStore.AuthStoreServer,
        force: Bool
    ) async -> AuthenticationStore.AuthStoreServer? {
        let now = Date()
        if let lastRefreshed = server.lastRefreshed,
           now.timeIntervalSince(lastRefreshed) < Self.refreshInterval,
           server.version != nil,
           !force {
            return nil
        }

        let client = HttpClient(baseURL: URL(string: server.address))
        do {
            let info: PublicSystemInfo = try await client.request("/System/Info/Public")
            var updated = server
            updated.name = info.serverName
            updated.version = info.version
            updated.setupCompleted = info.startupWizardCompleted ?? server.setupCompleted
            updated.serverType = ServerType.detect(productName: info.productName, version: info.version)
            updated.lastRefreshed = now
            authenticationStore.putServer(id, updated)
            return updated
        } catch {
            return nil
        }
    }

    private static func addressCandidates(for input: String) -> [String] {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return [] }

        var candidates: [String] = []

        if !address.contains("://") {
            candidates.append("https://\(address)")
            candidates.append("http://\(address)")
        } else {
            candidates.append(address)
        }

        return candidates.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }
}

private extension AuthenticationStore.AuthStoreServer {
    func asServer(id: UUID) -> Server {
        Server(
            id: id,
            name: name,
            address: address,
            version: version,
            serverType: serverType,
            loginDisclaimer: loginDisclaimer,
            splashscreenEnabled: splashscreenEnabled,
            setupCompleted: setupCompleted,
            dateLastAccessed: lastUsed
        )
    }
}
