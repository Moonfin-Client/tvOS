import CryptoKit
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
                guard let id = UUID.from(rawId: idString) else { return nil }
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
                var candidateErrors: [String: String] = [:]

                let trustDelegate = SSLTrustDelegate()
                let session = URLSession(configuration: {
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 10
                    config.timeoutIntervalForResource = 15
                    return config
                }(), delegate: trustDelegate, delegateQueue: nil)

                for candidate in candidates {
                    let client = HttpClient(baseURL: URL(string: candidate), session: session)
                    do {
                        let info: PublicSystemInfo = try await client.request("/System/Info/Public")
                        let productName = info.productName ?? ""
                        let version = info.version ?? ""
                        let serverType = ServerType.detect(productName: productName, version: version)

                        if serverType == .jellyfin {
                            let ver = ServerVersion(version)
                            if ver < Server.minimumJellyfinVersion {
                                let msg = "Version \(version) below minimum"
                                candidateErrors[candidate] = msg
                                continue
                            }
                        }

                        guard let idString = info.id, let id = Self.serverStorageId(from: idString) else {
                            let msg = "Invalid or missing server id (raw: \(info.id ?? "nil"))"
                            candidateErrors[candidate] = msg
                            continue
                        }
                        connectedServer = (id, info, candidate)
                        break
                    } catch let urlError as URLError {
                        let msg = "Network: \(urlError.localizedDescription) (code \(urlError.code.rawValue))"
                        candidateErrors[candidate] = msg
                    } catch {
                        let msg = String(describing: error)
                        candidateErrors[candidate] = msg
                    }
                }

                session.invalidateAndCancel()

                if let result = connectedServer {
                    let defaultName = result.info.serverName ?? result.info.productName ?? "Server"
                    let detectedType = ServerType.detect(productName: result.info.productName ?? "", version: result.info.version ?? "")

                    var storeServer = self.authenticationStore.getServer(result.id) ?? AuthenticationStore.AuthStoreServer(
                        name: defaultName,
                        address: result.address,
                        serverType: detectedType
                    )
                    storeServer.name = defaultName
                    storeServer.address = result.address
                    storeServer.version = result.info.version ?? ""
                    storeServer.setupCompleted = result.info.startupWizardCompleted ?? true
                    storeServer.lastUsed = Date()
                    storeServer.serverType = detectedType

                    self.authenticationStore.putServer(result.id, storeServer)
                    self.loadStoredServers()
                    continuation.yield(.connected(id: result.id, name: defaultName))
                } else {
                    continuation.yield(.unableToConnect(candidates: candidates, errors: candidateErrors))
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
            updated.name = info.serverName ?? info.productName ?? server.name
            updated.version = info.version
            updated.setupCompleted = info.startupWizardCompleted ?? server.setupCompleted
            updated.serverType = ServerType.detect(productName: info.productName ?? "", version: info.version ?? "")
            updated.lastRefreshed = now
            authenticationStore.putServer(id, updated)
            return updated
        } catch {
            return nil
        }
    }

    static func addressCandidates(for input: String) -> [String] {
        var address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return [] }

        while address.hasSuffix("/") { address = String(address.dropLast()) }

        var seen = Set<String>()
        var candidates: [String] = []

        func add(_ url: String) {
            let normalized = url.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            candidates.append(url)
        }

        if address.contains("://") {
            add(address)
            if !address.contains("/jellyfin") {
                add("\(address)/jellyfin")
            }
            return candidates
        }

        let hasPort = address.contains(":")

        if hasPort {
            add("https://\(address)")
            add("https://\(address)/jellyfin")
            add("http://\(address)")
            add("http://\(address)/jellyfin")
        } else {
            add("https://\(address):8920")
            add("https://\(address)")
            add("http://\(address):8096")
            add("http://\(address)")
            add("https://\(address):8920/jellyfin")
            add("https://\(address)/jellyfin")
            add("http://\(address):8096/jellyfin")
            add("http://\(address)/jellyfin")
        }

        return candidates
    }

    private static func serverStorageId(from rawId: String) -> UUID? {
        guard !rawId.isEmpty else { return nil }
        if let parsed = UUID.from(rawId: rawId) {
            return parsed
        }

        let digest = SHA256.hash(data: Data(rawId.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return UUID(uuidString: Self.formatAsUUID(hex))
    }

    private static func formatAsUUID(_ hex32: String) -> String {
        let s = hex32
        let i = s.index(s.startIndex, offsetBy: 8)
        let j = s.index(i, offsetBy: 4)
        let k = s.index(j, offsetBy: 4)
        let l = s.index(k, offsetBy: 4)
        return "\(s[s.startIndex..<i])-\(s[i..<j])-\(s[j..<k])-\(s[k..<l])-\(s[l..<s.endIndex])"
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
