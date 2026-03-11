import Foundation
import Combine

@MainActor
final class SyncPlayManager: ObservableObject {
    @Published var state = SyncPlayState()
    @Published var availableGroups: [SyncPlayGroupListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let playbackCoordinator: PlaybackCoordinator
    private let userPreferences: UserPreferences

    private var timeSyncManager: TimeSyncManager?
    private var pingTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var lastCommandId: String?
    private var lastSyncPositionMs: Int64 = 0
    private var lastSyncTimeMs: Int64 = 0

    private let pingIntervalMs: UInt64 = 15_000
    private let defaultSpeedMultiplier: Float = 1.0

    var syncPlayEnabled: Bool {
        userPreferences[UserPreferences.syncPlayEnabled]
    }

    var syncCorrectionEnabled: Bool {
        userPreferences[UserPreferences.syncPlayEnableSyncCorrection]
    }

    var useSpeedToSync: Bool {
        userPreferences[UserPreferences.syncPlayUseSpeedToSync]
    }

    var useSkipToSync: Bool {
        userPreferences[UserPreferences.syncPlayUseSkipToSync]
    }

    var minDelaySpeedToSync: Int64 {
        Int64(userPreferences[UserPreferences.syncPlayMinDelaySpeedToSync])
    }

    var maxDelaySpeedToSync: Int64 {
        Int64(userPreferences[UserPreferences.syncPlayMaxDelaySpeedToSync])
    }

    var speedToSyncDuration: Int64 {
        Int64(userPreferences[UserPreferences.syncPlaySpeedToSyncDuration])
    }

    var minDelaySkipToSync: Int64 {
        Int64(userPreferences[UserPreferences.syncPlayMinDelaySkipToSync])
    }

    var extraTimeOffset: Int64 {
        Int64(userPreferences[UserPreferences.syncPlayExtraTimeOffset])
    }

    init(
        serverRepository: ServerRepositoryProtocol,
        serverClientFactory: MediaServerClientFactory,
        playbackCoordinator: PlaybackCoordinator,
        userPreferences: UserPreferences
    ) {
        self.serverRepository = serverRepository
        self.serverClientFactory = serverClientFactory
        self.playbackCoordinator = playbackCoordinator
        self.userPreferences = userPreferences
    }

    private var currentClient: MediaServerClient? {
        guard let server = serverRepository.currentServer.value else { return nil }
        return serverClientFactory.client(for: server)
    }

    private var syncPlayApi: ServerSyncPlayApi? {
        currentClient?.syncPlayApi
    }

    private var playbackManager: PlaybackManager? {
        playbackCoordinator.videoPlayerManager
    }

    // MARK: - Group Management

    func fetchGroups() async {
        guard let api = syncPlayApi else { return }
        isLoading = true
        errorMessage = nil
        do {
            availableGroups = try await api.getGroups()
        } catch {
            errorMessage = "Failed to load groups"
        }
        isLoading = false
    }

    func createGroup(name: String) async {
        guard let api = syncPlayApi else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await api.createGroup(groupName: name)
            state.enabled = true
            startTimeSync()
            startPingLoop()
        } catch {
            errorMessage = "Failed to create group"
        }
        isLoading = false
    }

    func joinGroup(_ groupId: String) async {
        guard let api = syncPlayApi else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await api.joinGroup(groupId: groupId)
            state.enabled = true
            startTimeSync()
            startPingLoop()
        } catch {
            errorMessage = "Failed to join group"
        }
        isLoading = false
    }

    func leaveGroup() async {
        guard let api = syncPlayApi else { return }
        do {
            try await api.leaveGroup()
        } catch { }
        resetState()
    }

    private func resetState() {
        state = SyncPlayState()
        stopTimeSync()
        stopPingLoop()
        scheduledTask?.cancel()
        scheduledTask = nil
        lastCommandId = nil
        lastSyncPositionMs = 0
        lastSyncTimeMs = 0
        restorePlaybackRate()
    }

    // MARK: - Time Sync

    private func startTimeSync() {
        guard let client = currentClient else { return }
        let manager = TimeSyncManager(client: client.httpClient)
        timeSyncManager = manager
        manager.startSync()
    }

    private func stopTimeSync() {
        timeSyncManager?.stopSync()
        timeSyncManager = nil
    }

    // MARK: - Ping Loop

    private func startPingLoop() {
        stopPingLoop()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = (self?.pingIntervalMs ?? 15_000) * 1_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard let self, self.state.enabled, !Task.isCancelled else { break }
                let rtt = self.timeSyncManager?.roundTripTime ?? 0
                try? await self.syncPlayApi?.sendPing(ping: rtt)
            }
        }
    }

    private func stopPingLoop() {
        pingTask?.cancel()
        pingTask = nil
    }

    // MARK: - WebSocket Command Handling

    func handlePlaybackCommand(_ command: SyncPlayCommand) {
        guard state.enabled else { return }

        let commandId = "\(command.command.rawValue)_\(command.whenUtcMs)"
        guard commandId != lastCommandId else { return }
        lastCommandId = commandId

        switch command.command {
        case .unpause:
            handleUnpause(command)
        case .pause:
            handlePause(command)
        case .seek:
            handleSeek(command)
        case .stop:
            handleStop()
        }
    }

    func handleGroupUpdate(_ update: SyncPlayGroupUpdate) {
        switch update.type {
        case .groupJoined:
            state.enabled = true
            if let groupId = update.data["GroupId"] as? String {
                state.groupInfo = SyncPlayGroupInfo(
                    groupId: groupId,
                    groupName: update.data["GroupName"] as? String,
                    participants: [],
                    lastUpdatedAt: nil
                )
            }
        case .groupLeft, .notInGroup:
            resetState()
        case .stateUpdate:
            if let rawState = update.data["State"] as? String,
               let newState = SyncPlayGroupState(rawValue: rawState) {
                state.groupState = newState
            }
        case .playQueue:
            break
        case .userJoined, .userLeft:
            break
        }
    }

    // MARK: - Playback Commands

    private func handleUnpause(_ command: SyncPlayCommand) {
        guard let tsm = timeSyncManager else { return }
        let serverTimeNow = tsm.getServerTimeNow()
        let targetTimeMs = command.whenUtcMs
        let delayMs = targetTimeMs - serverTimeNow

        let positionMs = SyncPlayUtils.ticksToMs(command.positionTicks)
        lastSyncPositionMs = positionMs
        lastSyncTimeMs = targetTimeMs

        if delayMs > 0 {
            scheduleAction(delayMs: delayMs) { [weak self] in
                self?.performResume(atMs: positionMs)
            }
        } else {
            let elapsedMs = -delayMs
            performResume(atMs: positionMs + elapsedMs)
        }

        state.groupState = .playing
    }

    private func handlePause(_ command: SyncPlayCommand) {
        let positionMs = SyncPlayUtils.ticksToMs(command.positionTicks)
        performPause(atMs: positionMs)
        state.groupState = .paused
    }

    private func handleSeek(_ command: SyncPlayCommand) {
        let positionMs = SyncPlayUtils.ticksToMs(command.positionTicks)
        lastSyncPositionMs = positionMs
        lastSyncTimeMs = timeSyncManager?.getServerTimeNow() ?? 0
        performSeek(toMs: positionMs)
    }

    private func handleStop() {
        Task { [weak self] in
            await self?.playbackManager?.stop()
        }
        resetState()
    }

    // MARK: - Playback Actions

    private func performResume(atMs positionMs: Int64) {
        guard let pm = playbackManager else { return }
        let positionSec = TimeInterval(positionMs) / 1000.0
        pm.seek(to: positionSec)
        pm.resume()
        restorePlaybackRate()

        if syncCorrectionEnabled {
            scheduleDriftCorrection()
        }
    }

    private func performPause(atMs positionMs: Int64) {
        guard let pm = playbackManager else { return }
        restorePlaybackRate()
        pm.pause()
        let positionSec = TimeInterval(positionMs) / 1000.0
        pm.seek(to: positionSec)
    }

    private func performSeek(toMs positionMs: Int64) {
        guard let pm = playbackManager else { return }
        let positionSec = TimeInterval(positionMs) / 1000.0
        pm.seek(to: positionSec)
    }

    private func restorePlaybackRate() {
        playbackManager?.setRate(defaultSpeedMultiplier)
    }

    // MARK: - Drift Correction

    private func scheduleDriftCorrection() {
        guard syncCorrectionEnabled, state.groupState == .playing else { return }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.state.groupState == .playing else { return }
            self.performDriftCorrection()
        }
    }

    private func performDriftCorrection() {
        guard let pm = playbackManager, let tsm = timeSyncManager else { return }
        guard state.groupState == .playing, lastSyncTimeMs > 0 else { return }

        let currentPositionMs = Int64(pm.player.currentTime * 1000)
        let serverTimeNow = tsm.getServerTimeNow()
        let expectedPositionMs = lastSyncPositionMs + (serverTimeNow - lastSyncTimeMs) + extraTimeOffset

        let delayMs = currentPositionMs - expectedPositionMs
        let absDelay = abs(delayMs)

        if useSkipToSync && absDelay > minDelaySkipToSync {
            performSeek(toMs: expectedPositionMs)
            return
        }

        if useSpeedToSync && absDelay > minDelaySpeedToSync && absDelay < maxDelaySpeedToSync {
            let speedAdjustment: Float = delayMs > 0 ? 0.95 : 1.05
            pm.setRate(speedAdjustment)

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.speedToSyncDuration ?? 1000) * 1_000_000)
                guard let self else { return }
                self.restorePlaybackRate()
                self.scheduleDriftCorrection()
            }
            return
        }

        scheduleDriftCorrection()
    }

    // MARK: - Buffering

    func reportBuffering() async {
        guard state.enabled, let pm = playbackManager else { return }
        let positionTicks = SyncPlayUtils.msToTicks(Int64(pm.player.currentTime * 1000))
        let itemId = pm.currentEntry?.item.id ?? ""
        let isPlaying = pm.playbackState == .playing
        try? await syncPlayApi?.sendBuffering(isPlaying: isPlaying, itemId: itemId, positionTicks: positionTicks)
    }

    func reportReady() async {
        guard state.enabled, let pm = playbackManager else { return }
        let positionTicks = SyncPlayUtils.msToTicks(Int64(pm.player.currentTime * 1000))
        let itemId = pm.currentEntry?.item.id ?? ""
        let isPlaying = pm.playbackState == .playing
        try? await syncPlayApi?.sendReady(isPlaying: isPlaying, itemId: itemId, positionTicks: positionTicks)
    }

    // MARK: - Scheduling

    private func scheduleAction(delayMs: Int64, action: @escaping () -> Void) {
        scheduledTask?.cancel()
        scheduledTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, delayMs)) * 1_000_000)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
