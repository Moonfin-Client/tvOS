import SwiftUI

enum ServerConnectionState: Equatable {
    case connected
    case checking
    case unreachable(String)
    case versionUnsupported(String)

    var isAvailable: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class ServerConnectionMonitor: ObservableObject {
    @Published private(set) var state: ServerConnectionState = .connected
    @Published private(set) var lastSuccessfulContact: Date?

    private let serverClientFactory: MediaServerClientFactory
    private let serverRepository: ServerRepositoryProtocol
    private var checkTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    init(serverClientFactory: MediaServerClientFactory, serverRepository: ServerRepositoryProtocol) {
        self.serverClientFactory = serverClientFactory
        self.serverRepository = serverRepository
    }

    func startMonitoring(interval: TimeInterval = 60) {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkConnection()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        periodicTask?.cancel()
        periodicTask = nil
        checkTask?.cancel()
        checkTask = nil
    }

    func checkConnection() async {
        guard let server = serverRepository.currentServer.value else {
            state = .unreachable("No server configured")
            return
        }

        state = .checking
        let client = serverClientFactory.client(for: server)

        do {
            let info = try await client.systemApi.getPublicSystemInfo()
            if let version = info.version, !server.versionSupported {
                state = .versionUnsupported(version)
            } else {
                state = .connected
                lastSuccessfulContact = Date()
            }
        } catch {
            state = .unreachable(error.localizedDescription)
        }
    }

    func retryConnection() {
        checkTask?.cancel()
        checkTask = Task { await checkConnection() }
    }

    deinit {
        periodicTask?.cancel()
        checkTask?.cancel()
    }
}
