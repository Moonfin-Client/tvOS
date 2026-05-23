import Foundation
import Combine
import OSLog

@MainActor
final class SyncPlayRuntimeCoordinator {
    private weak var syncPlayManager: SyncPlayManager?
    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private var serverCancellable: AnyCancellable?
    private var syncPlayStateCancellable: AnyCancellable?
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

        if let syncPlayManager {
            syncPlayStateCancellable = syncPlayManager.$state
                .map(\.enabled)
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.refreshConnectionIfNeeded()
                    }
                }
        }
    }

    func stop() {
        serverCancellable?.cancel()
        serverCancellable = nil
        syncPlayStateCancellable?.cancel()
        syncPlayStateCancellable = nil
        currentServer = nil
        Task { @MainActor in
            await disconnectCurrentWebSocket()
        }
    }

    func appDidEnterBackground() {
        Task { @MainActor in
            await disconnectCurrentWebSocket()
        }
    }

    func appDidBecomeActive() {
        Task { @MainActor in
            await refreshConnectionIfNeeded()
        }
    }

    private func handleServerChange(_ server: Server?) async {
        let serverChanged = currentServer?.id != server?.id
        if serverChanged {
            await disconnectCurrentWebSocket()
        }

        currentServer = server
        await refreshConnectionIfNeeded()
    }

    private var shouldMaintainRealtimeConnection: Bool {
        guard let syncPlayManager else { return false }
        return syncPlayManager.syncPlayEnabled && syncPlayManager.state.enabled
    }

    private func refreshConnectionIfNeeded() async {
        guard let server = currentServer,
              server.serverType == .jellyfin,
              shouldMaintainRealtimeConnection else {
            await disconnectCurrentWebSocket()
            return
        }

        guard currentWebSocket == nil else { return }
        await connectWebSocket(for: server)
    }

    private func disconnectCurrentWebSocket() async {
        let ws = currentWebSocket
        currentWebSocket = nil
        await ws?.disconnect()
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
            currentWebSocket = nil
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
