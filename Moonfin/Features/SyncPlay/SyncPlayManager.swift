import Foundation
import Combine
import OSLog

@MainActor
final class SyncPlayManager: ObservableObject {
    @Published var state = SyncPlayState()
    @Published var availableGroups: [SyncPlayGroupListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var ignoreWaitEnabled = false

    private let serverRepository: ServerRepositoryProtocol
    private let serverClientFactory: MediaServerClientFactory
    private let playbackCoordinator: PlaybackCoordinator
    private let userPreferences: UserPreferences

    private var timeSyncManager: TimeSyncManager?
    private var pingTask: Task<Void, Never>?
    private var scheduledTask: Task<Void, Never>?
    private var playbackStateObserver: AnyCancellable?
    private var observedPlaybackManagerId: ObjectIdentifier?
    private var bufferingTask: Task<Void, Never>?
    private var readyTask: Task<Void, Never>?
    private var lastObservedPlaybackState: PlaybackState = .idle
    private var lastCommandKey: String?
    private var lastSyncPositionMs: Int64 = 0
    private var lastSyncTimeMs: Int64 = 0
    private var commandJitterSamples: [Int64] = []
    private var isRefreshingAfterReconnect = false
    private let maxCommandJitterSamples = 24
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SyncPlay")

    private let pingIntervalMs: UInt64 = 15_000
    private let defaultSpeedMultiplier: Float = 1.0
    private let commandLeadToleranceMs: Int64 = 120
    private let commandLateToleranceMs: Int64 = 300
    private let maxLateCatchUpMs: Int64 = 15_000
    private let maxSeekDeltaMs: Int64 = 6 * 60 * 60 * 1000
    private let bufferingDebounceNs: UInt64 = 350_000_000
    private let readyDebounceNs: UInt64 = 900_000_000
    private let readyStabilityWindowNs: UInt64 = 400_000_000
    private let handshakeRetryDelayNs: UInt64 = 1_200_000_000
    private let maxHandshakeRetries = 3

    private var syncPlayServerSupported: Bool {
        serverRepository.currentServer.value?.serverType.supports(.syncPlay) == true
    }

    var syncPlayEnabled: Bool {
        userPreferences[UserPreferences.syncPlayEnabled]
            && syncPlayServerSupported
    }

    var syncPlayConfigured: Bool {
        userPreferences[UserPreferences.syncPlayEnabled]
    }

    var advancedCorrectionEnabled: Bool {
        userPreferences[UserPreferences.syncPlayAdvancedCorrectionEnabled]
    }

    var syncCorrectionEnabled: Bool {
        advancedCorrectionEnabled && userPreferences[UserPreferences.syncPlayEnableSyncCorrection]
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
        guard syncPlayEnabled else {
            availableGroups = []
            return
        }
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

    func createGroup(name: String, withCurrentQueueSnapshot: Bool = true) async {
        guard syncPlayEnabled else {
            errorMessage = "SyncPlay is currently unavailable"
            return
        }
        guard let api = syncPlayApi else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await api.createGroup(groupName: name)
            state.enabled = true
            startTimeSync()
            startPingLoop()
            attachPlaybackStateObserverIfNeeded()
            if withCurrentQueueSnapshot {
                await syncCurrentPlaybackQueueToGroup()
            }
        } catch {
            errorMessage = "Failed to create group"
        }
        isLoading = false
    }

    func joinGroup(_ groupId: String, withCurrentQueueSnapshot: Bool = false) async {
        guard syncPlayEnabled else {
            errorMessage = "SyncPlay is currently unavailable"
            return
        }
        guard let api = syncPlayApi else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await api.joinGroup(groupId: groupId)
            state.enabled = true
            startTimeSync()
            startPingLoop()
            attachPlaybackStateObserverIfNeeded()
            if withCurrentQueueSnapshot {
                await syncCurrentPlaybackQueueToGroup()
            }
        } catch {
            errorMessage = "Failed to join group"
        }
        isLoading = false
    }

    func leaveGroup() async {
        guard syncPlayEnabled else {
            resetState()
            return
        }
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
        stopPlaybackHandshakeObservers()
        scheduledTask?.cancel()
        scheduledTask = nil
        lastCommandKey = nil
        commandJitterSamples.removeAll()
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

    func appDidEnterBackground() {
        stopTimeSync()
        stopPingLoop()
    }

    func appDidBecomeActive() {
        guard state.enabled, syncPlayEnabled else { return }
        startTimeSync()
        startPingLoop()
        attachPlaybackStateObserverIfNeeded()
    }

    func handleRealtimeConnected() {
        guard state.enabled, syncPlayEnabled else { return }
        logger.debug("Realtime connected, recovering group state")
        Task { [weak self] in
            await self?.refreshCurrentGroupStateAfterReconnect()
        }
    }

    func handleRealtimeSessionInterrupted(message: String) {
        logger.warning("Realtime interrupted: \(message, privacy: .public)")
        errorMessage = message
        resetState()
    }

    private func refreshCurrentGroupStateAfterReconnect() async {
        guard !isRefreshingAfterReconnect else { return }
        guard state.enabled, let groupId = state.groupId, !groupId.isEmpty else { return }
        guard let api = syncPlayApi else { return }

        isRefreshingAfterReconnect = true
        defer { isRefreshingAfterReconnect = false }

        do {
            let group = try await api.getGroup(groupId: groupId)
            state.groupId = group.groupId
            state.groupName = group.groupName
            state.participants = group.participants
            state.lastUpdateAt = group.lastUpdatedAt
            if let mapped = SyncPlayGroupState(rawValue: group.state) {
                state.groupState = mapped
            }
            reconcileLocalPlaybackWithServerState()
            return
        } catch { }

        do {
            let groups = try await api.getGroups()
            if let group = groups.first(where: { $0.groupId == groupId }) {
                state.groupName = group.groupName
                state.participants = group.participants
                state.lastUpdateAt = group.lastUpdatedAt
                if let mapped = SyncPlayGroupState(rawValue: group.state) {
                    state.groupState = mapped
                }
                reconcileLocalPlaybackWithServerState()
                return
            }
            resetState()
            logger.warning("Group not found after reconnect, state reset")
        } catch {
            errorMessage = "Failed to recover SyncPlay state after reconnect"
            logger.error("Reconnect recovery failed")
        }
    }

    private func reconcileLocalPlaybackWithServerState() {
        guard let pm = playbackManager else { return }
        switch state.groupState {
        case .paused, .waiting:
            if pm.player.isPlaying {
                pm.pause()
            }
        case .playing:
            if !pm.player.isPlaying {
                pm.resume(applyRewind: false)
            }
        case .idle:
            break
        }
    }

    // MARK: - WebSocket Command Handling

    func handlePlaybackCommand(_ command: SyncPlayCommand) {
        guard state.enabled, syncPlayEnabled else { return }

        if let currentGroupId = state.groupId,
           !currentGroupId.isEmpty,
           command.groupId != currentGroupId {
            return
        }

        let key = SyncPlayCommandIdentity.dedupeKey(for: command)
        guard key != lastCommandKey else { return }
        lastCommandKey = key

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
        guard syncPlayEnabled else { return }
        switch update.type {
        case .groupJoined:
            if case .groupJoined(let info) = update.payload {
                state.enabled = true
                state.groupId = info.groupId
                state.groupName = info.groupName
                state.participants = info.participants
                state.lastUpdateAt = info.lastUpdatedAt
                if let joinedState = info.state {
                    state.groupState = joinedState
                }
                attachPlaybackStateObserverIfNeeded()
            }
        case .groupLeft, .notInGroup, .groupDoesNotExist, .libraryAccessDenied:
            resetState()
        case .stateUpdate:
            if case .stateUpdate(let stateUpdate) = update.payload {
                state.groupState = stateUpdate.state
            }
        case .playQueue:
            if case .playQueue(let queueUpdate) = update.payload {
                applyQueueUpdate(queueUpdate)
            }
        case .userJoined:
            if case .userJoined(let username) = update.payload,
               !state.participants.contains(username) {
                state.participants.append(username)
            }
        case .userLeft:
            if case .userLeft(let username) = update.payload {
                state.participants.removeAll { $0 == username }
            }
        }
    }

    private func applyQueueUpdate(_ update: SyncPlayPlayQueueUpdate) {
        state.queue = update.playlist
        state.currentItemIndex = update.playingItemIndex
        let idx = update.playingItemIndex
        state.currentPlaylistItemId = (idx >= 0 && idx < update.playlist.count)
            ? update.playlist[idx].playlistItemId
            : nil
        state.repeatMode = update.repeatMode
        state.shuffleMode = update.shuffleMode
        state.lastUpdateAt = update.lastUpdate
    }

    // MARK: - Playback Commands

    private func handleUnpause(_ command: SyncPlayCommand) {
        guard let tsm = timeSyncManager else { return }
        let serverTimeNow = tsm.getServerTimeNow()
        let targetTimeMs = command.whenUtcMs
        let delayMs = targetTimeMs - serverTimeNow

        recordCommandJitter(abs(delayMs))

        let positionMs = clampedPositionMs(SyncPlayUtils.ticksToMs(command.positionTicks))
        lastSyncPositionMs = positionMs
        lastSyncTimeMs = targetTimeMs

        if !advancedCorrectionEnabled {
            if delayMs > 0 {
                scheduleAction(delayMs: delayMs) { [weak self] in
                    self?.performResume(atMs: positionMs, applyRewind: false)
                }
            } else {
                performResume(atMs: positionMs, applyRewind: false)
            }
        } else if delayMs > commandLeadToleranceMs {
            scheduleAction(delayMs: delayMs) { [weak self] in
                self?.performResume(atMs: positionMs, applyRewind: false)
            }
        } else if delayMs >= -commandLateToleranceMs {
            performResume(atMs: positionMs, applyRewind: false)
        } else {
            let elapsedMs = min(-delayMs, maxLateCatchUpMs)
            performResume(atMs: clampedPositionMs(positionMs + elapsedMs), applyRewind: false)
        }

        state.groupState = .playing
    }

    private func handlePause(_ command: SyncPlayCommand) {
        let positionMs = clampedPositionMs(SyncPlayUtils.ticksToMs(command.positionTicks))
        performPause(atMs: positionMs)
        state.groupState = .paused
    }

    private func handleSeek(_ command: SyncPlayCommand) {
        let serverNow = timeSyncManager?.getServerTimeNow() ?? 0
        let latenessMs = max(0, serverNow - command.whenUtcMs)
        recordCommandJitter(latenessMs)

        let rawPositionMs = SyncPlayUtils.ticksToMs(command.positionTicks)
        let adjustedPositionMs: Int64 = {
            guard advancedCorrectionEnabled else { return rawPositionMs }
            if latenessMs > commandLateToleranceMs, state.groupState == .playing {
                return rawPositionMs + min(latenessMs, maxLateCatchUpMs)
            }
            return rawPositionMs
        }()

        let positionMs = clampedPositionMs(adjustedPositionMs)
        lastSyncPositionMs = positionMs
        lastSyncTimeMs = serverNow
        performSeek(toMs: positionMs)
    }

    private func handleStop() {
        Task { [weak self] in
            await self?.playbackManager?.stop()
        }
        resetState()
    }

    // MARK: - Playback Actions

    private func performResume(atMs positionMs: Int64, applyRewind: Bool) {
        guard let pm = playbackManager else { return }
        let positionSec = TimeInterval(positionMs) / 1000.0
        pm.seek(to: positionSec)
        pm.resume(applyRewind: applyRewind)
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

    private func clampedPositionMs(_ value: Int64) -> Int64 {
        guard let pm = playbackManager else { return max(0, value) }
        let durationSec = pm.player.duration
        guard durationSec.isFinite, durationSec > 0 else {
            return max(0, min(value, maxSeekDeltaMs))
        }
        let durationMs = Int64(durationSec * 1000)
        return max(0, min(value, max(0, durationMs)))
    }

    private func recordCommandJitter(_ jitterMs: Int64) {
        guard advancedCorrectionEnabled else { return }
        commandJitterSamples.append(max(0, jitterMs))
        while commandJitterSamples.count > maxCommandJitterSamples {
            commandJitterSamples.removeFirst()
        }

        if commandJitterSamples.count >= 6 {
            let avg = commandJitterSamples.reduce(0, +) / Int64(commandJitterSamples.count)
            let clockJitter = timeSyncManager?.offsetJitterMs ?? 0
            logger.debug("Timing jitter avg=\(avg, privacy: .public)ms clock=\(clockJitter, privacy: .public)ms")
        }
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

    func attachPlaybackStateObserverIfNeeded() {
        guard state.enabled, let pm = playbackManager else { return }
        let id = ObjectIdentifier(pm)
        if observedPlaybackManagerId == id, playbackStateObserver != nil { return }

        stopPlaybackHandshakeObservers()
        observedPlaybackManagerId = id
        lastObservedPlaybackState = pm.playbackState

        playbackStateObserver = pm.$playbackState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handlePlaybackStateTransition(to: newState)
            }
    }

    private func stopPlaybackHandshakeObservers() {
        playbackStateObserver?.cancel()
        playbackStateObserver = nil
        observedPlaybackManagerId = nil
        bufferingTask?.cancel()
        bufferingTask = nil
        readyTask?.cancel()
        readyTask = nil
        lastObservedPlaybackState = .idle
    }

    private func handlePlaybackStateTransition(to newState: PlaybackState) {
        let oldState = lastObservedPlaybackState
        lastObservedPlaybackState = newState

        guard state.enabled else { return }

        if case .buffering = newState {
            if case .buffering = oldState {
                return
            }
            queueBufferingReport()
            return
        }

        if case .buffering = oldState {
            switch newState {
            case .playing, .paused:
                queueReadyReport()
            default:
                break
            }
        }
    }

    private func queueBufferingReport() {
        bufferingTask?.cancel()
        bufferingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.bufferingDebounceNs ?? 0)
            guard let self, !Task.isCancelled else { return }
            await self.sendBufferingWithRetry()
        }
    }

    private func queueReadyReport() {
        readyTask?.cancel()
        readyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.readyDebounceNs ?? 0)
            guard let self, !Task.isCancelled else { return }
            if await !self.isPlaybackPositionStable() { return }
            await self.sendReadyWithRetry()
        }
    }

    private func currentPlaylistItemId() -> String? {
        if let playlistItemId = state.currentPlaylistItemId, !playlistItemId.isEmpty {
            return playlistItemId
        }
        guard let currentItemId = playbackManager?.currentEntry?.item.id else { return nil }
        return state.queue.first(where: { $0.itemId == currentItemId })?.playlistItemId
    }

    private func isPlaybackPositionStable() async -> Bool {
        guard let pm = playbackManager else { return false }
        let beforeState = pm.playbackState
        guard beforeState != .buffering, beforeState != .resolving else { return false }
        let before = pm.player.currentTime
        try? await Task.sleep(nanoseconds: readyStabilityWindowNs)
        guard let pmAfter = playbackManager else { return false }
        let afterState = pmAfter.playbackState
        guard afterState != .buffering, afterState != .resolving else { return false }
        let after = pmAfter.player.currentTime
        let delta = after - before

        if beforeState == .playing || afterState == .playing {
            return delta >= 0.08 && delta <= 1.2
        }

        return abs(delta) <= 0.12
    }

    private func sendBufferingWithRetry() async {
        for attempt in 0..<maxHandshakeRetries {
            guard state.enabled, syncPlayEnabled,
                  let pm = playbackManager,
                  let playlistItemId = currentPlaylistItemId() else { return }
            let positionTicks = SyncPlayUtils.msToTicks(Int64(pm.player.currentTime * 1000))
            let isPlaying = pm.playbackState == .playing
            do {
                try await syncPlayApi?.sendBuffering(isPlaying: isPlaying, playlistItemId: playlistItemId, positionTicks: positionTicks)
                return
            } catch {
                if attempt == maxHandshakeRetries - 1 { return }
                try? await Task.sleep(nanoseconds: handshakeRetryDelayNs)
            }
        }
    }

    private func sendReadyWithRetry() async {
        for attempt in 0..<maxHandshakeRetries {
            guard state.enabled, syncPlayEnabled,
                  let pm = playbackManager,
                  let playlistItemId = currentPlaylistItemId() else { return }
            let positionTicks = SyncPlayUtils.msToTicks(Int64(pm.player.currentTime * 1000))
            let isPlaying = pm.playbackState == .playing
            do {
                try await syncPlayApi?.sendReady(isPlaying: isPlaying, playlistItemId: playlistItemId, positionTicks: positionTicks)
                return
            } catch {
                if attempt == maxHandshakeRetries - 1 { return }
                try? await Task.sleep(nanoseconds: handshakeRetryDelayNs)
            }
        }
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

    // MARK: - Outbound Transport Requests

    func requestPause() {
        guard state.enabled, syncPlayEnabled else { return }
        Task { [weak self] in try? await self?.syncPlayApi?.sendPause() }
    }

    func requestUnpause() {
        guard state.enabled, syncPlayEnabled else { return }
        Task { [weak self] in try? await self?.syncPlayApi?.sendUnpause() }
    }

    func requestSeek(to position: TimeInterval) {
        guard state.enabled, syncPlayEnabled else { return }
        let ticks = SyncPlayUtils.msToTicks(Int64(position * 1000))
        Task { [weak self] in try? await self?.syncPlayApi?.sendSeek(positionTicks: ticks) }
    }

    func requestStop() {
        guard state.enabled, syncPlayEnabled else { return }
        Task { [weak self] in try? await self?.syncPlayApi?.sendStop() }
    }

    func requestNext() {
        guard state.enabled, syncPlayEnabled, let playlistItemId = state.currentPlaylistItemId else { return }
        let req = SyncPlayPlaylistItemRequest(playlistItemId: playlistItemId)
        Task { [weak self] in try? await self?.syncPlayApi?.nextItem(request: req) }
    }

    func requestPrevious() {
        guard state.enabled, syncPlayEnabled, let playlistItemId = state.currentPlaylistItemId else { return }
        let req = SyncPlayPlaylistItemRequest(playlistItemId: playlistItemId)
        Task { [weak self] in try? await self?.syncPlayApi?.previousItem(request: req) }
    }

    func requestSetCurrentItem(playlistItemId: String) {
        guard state.enabled, syncPlayEnabled else { return }
        let req = SyncPlaySetPlaylistItemRequest(playlistItemId: playlistItemId)
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.setPlaylistItem(request: req)
            } catch {
                self?.errorMessage = "Failed to set current item"
            }
        }
    }

    func requestRemoveFromQueue(playlistItemId: String) {
        guard state.enabled, syncPlayEnabled else { return }
        let req = SyncPlayRemoveFromPlaylistRequest(
            playlistItemIds: [playlistItemId],
            clearPlaylist: false,
            clearPlayingItem: false
        )
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.removeFromPlaylist(request: req)
            } catch {
                self?.errorMessage = "Failed to remove from queue"
            }
        }
    }

    func requestMoveQueueItem(playlistItemId: String, to newIndex: Int) {
        guard state.enabled, syncPlayEnabled else { return }
        let req = SyncPlayMovePlaylistItemRequest(playlistItemId: playlistItemId, newIndex: max(0, newIndex))
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.movePlaylistItem(request: req)
            } catch {
                self?.errorMessage = "Failed to move queue item"
            }
        }
    }

    func requestQueueItemIds(_ itemIds: [String], mode: SyncPlayQueueRequestMode = .queue) {
        guard state.enabled, syncPlayEnabled, !itemIds.isEmpty else { return }
        let req = SyncPlayQueueRequest(itemIds: itemIds, mode: mode)
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.queue(request: req)
            } catch {
                self?.errorMessage = "Failed to queue items"
            }
        }
    }

    func requestQueueCurrentPlaybackItem(mode: SyncPlayQueueRequestMode = .queue) {
        guard let itemId = playbackManager?.currentEntry?.item.id else { return }
        requestQueueItemIds([itemId], mode: mode)
    }

    func requestSetRepeatMode(_ mode: SyncPlayRepeatMode) {
        guard state.enabled, syncPlayEnabled else { return }
        state.repeatMode = mode
        let requestMode: SyncPlayRepeatRequestMode
        switch mode {
        case .repeatNone: requestMode = .repeatNone
        case .repeatOne: requestMode = .repeatOne
        case .repeatAll: requestMode = .repeatAll
        }
        let req = SyncPlaySetRepeatModeRequest(mode: requestMode)
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.setRepeatMode(request: req)
            } catch {
                self?.errorMessage = "Failed to set repeat mode"
            }
        }
    }

    func requestSetShuffleMode(_ mode: SyncPlayShuffleMode) {
        guard state.enabled, syncPlayEnabled else { return }
        state.shuffleMode = mode
        let requestMode: SyncPlayShuffleRequestMode = (mode == .shuffle) ? .shuffle : .sorted
        let req = SyncPlaySetShuffleModeRequest(mode: requestMode)
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.setShuffleMode(request: req)
            } catch {
                self?.errorMessage = "Failed to set shuffle mode"
            }
        }
    }

    func requestSetIgnoreWait(_ enabled: Bool) {
        guard state.enabled, syncPlayEnabled else { return }
        ignoreWaitEnabled = enabled
        let req = SyncPlaySetIgnoreWaitRequest(ignoreWait: enabled)
        Task { [weak self] in
            do {
                try await self?.syncPlayApi?.setIgnoreWait(request: req)
            } catch {
                self?.errorMessage = "Failed to update ignore-wait"
            }
        }
    }

    func cycleRepeatMode() {
        let next: SyncPlayRepeatMode
        switch state.repeatMode {
        case .repeatNone: next = .repeatAll
        case .repeatAll: next = .repeatOne
        case .repeatOne: next = .repeatNone
        }
        requestSetRepeatMode(next)
    }

    func toggleShuffleMode() {
        requestSetShuffleMode(state.shuffleMode == .shuffle ? .sorted : .shuffle)
    }

    func syncCurrentPlaybackQueueToGroup() async {
        guard state.enabled, syncPlayEnabled, let pm = playbackManager else { return }
        let itemIds = pm.queue.map { $0.item.id }
        guard !itemIds.isEmpty else { return }

        let currentIdx = max(0, pm.currentIndex)
        let clampedIndex = min(currentIdx, max(0, itemIds.count - 1))
        let positionTicks = SyncPlayUtils.msToTicks(Int64(pm.player.currentTime * 1000))
        do {
            try await syncPlayApi?.setNewQueue(itemIds: itemIds, startIndex: clampedIndex, startPositionTicks: positionTicks)
        } catch {
            errorMessage = "Failed to sync current playback queue"
        }
    }
}
