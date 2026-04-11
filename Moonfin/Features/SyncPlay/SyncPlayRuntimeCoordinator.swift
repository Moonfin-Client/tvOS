import Foundation
import Combine
import OSLog

@MainActor
final class SyncPlayRuntimeCoordinator {
    private weak var syncPlayManager: SyncPlayManager?
    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private var serverCancellable: AnyCancellable?
    private var currentWebSocket: ServerWebSocketApi?
    private var currentServer: Server?
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SyncPlay")

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        syncPlayManager: SyncPlayManager
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.syncPlayManager = syncPlayManager
    }

    func start() {
        serverCancellable = serverRepository.currentServer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] server in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleServerChange(server)
                }
            }
    }

    func stop() {
        serverCancellable?.cancel()
        serverCancellable = nil
        let ws = currentWebSocket
        currentWebSocket = nil
        currentServer = nil
        Task { await ws?.disconnect() }
    }

    func appDidEnterBackground() {
        let ws = currentWebSocket
        currentWebSocket = nil
        Task { await ws?.disconnect() }
    }

    func appDidBecomeActive() {
        guard let server = currentServer, server.serverType == .jellyfin else { return }
        Task { @MainActor in
            await connectWebSocket(for: server)
        }
    }

    private func handleServerChange(_ server: Server?) async {
        let ws = currentWebSocket
        currentWebSocket = nil
        await ws?.disconnect()

        currentServer = server

        guard let server, server.serverType == .jellyfin else { return }

        await connectWebSocket(for: server)
    }

    private func connectWebSocket(for server: Server) async {
        let newWS = serverClientFactory.client(for: server).webSocketApi
        currentWebSocket = newWS
        currentWebSocket?.onMessage = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.route(message)
            }
        }
        do {
            try await currentWebSocket?.connect()
            syncPlayManager?.handleRealtimeConnected()
        } catch {
            logger.error("WebSocket connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func route(_ message: ServerWebSocketMessage) {
        switch message {
        case .syncPlayCommand(let command):
            syncPlayManager?.handlePlaybackCommand(command)
        case .syncPlayGroupUpdate(let update):
            syncPlayManager?.handleGroupUpdate(update)
        case .serverRestarting:
            syncPlayManager?.handleRealtimeSessionInterrupted(message: "Server is restarting")
        case .serverShuttingDown:
            syncPlayManager?.handleRealtimeSessionInterrupted(message: "Server is shutting down")
        case .sessionEnded:
            syncPlayManager?.handleRealtimeSessionInterrupted(message: "Session ended")
        default:
            break
        }
    }
}
