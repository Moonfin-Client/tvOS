import Foundation
import Combine
import OSLog

enum PlaybackState: Equatable {
    case idle
    case resolving
    case playing
    case paused
    case buffering
    case error(String)
}

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var currentStreamInfo: StreamInfo?
    @Published private(set) var episodesPlayed: Int = 0

    var autoAdvanceOnEnd = true

    let player: VLCPlayerWrapper
    let segmentHandler: MediaSegmentHandler
    let nextUpManager: NextUpManager

    private let client: MediaServerClient
    private let preferences: UserPreferences
    private let streamResolver: StreamResolver
    private let subtitleConfigurator: SubtitleConfigurator
    private var reportingTask: Task<Void, Never>?
    private var stateObserver: AnyCancellable?
    private var positionObserver: AnyCancellable?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedStreamInfo: StreamInfo?
    private var prefetchedItemId: String?
    private var lastEvaluatedSecond: Int = -1
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "PlaybackManager")
    private var startupBeganAt: Date?
    private var startupLatencyMs: Int?
    private var hasSeenFirstPlayingState = false
    private var stallCount = 0
    private var terminalOutcome = "stopped"
    private var lastBoundaryProgressReportAt: CFAbsoluteTime = 0

    var currentEntry: QueueEntry? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var hasNext: Bool { currentIndex < queue.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 }

    var nextEntry: QueueEntry? {
        guard hasNext else { return nil }
        return queue[currentIndex + 1]
    }

    func imageUrl(for item: ServerItem, type: ImageType = .primary, maxWidth: Int = 960, maxHeight: Int = 540) -> String? {
        if type == .backdrop, let tag = item.backdropImageTags?.first {
            return client.imageApi.getItemImageUrl(itemId: item.id, imageType: .backdrop, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
        }
        guard let tag = item.imageTags?["Primary"] else { return nil }
        return client.imageApi.getItemImageUrl(itemId: item.id, imageType: .primary, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
    }

    func chapterImageUrl(for item: ServerItem, tag: String, ticks: Int64) -> String? {
        guard let chapters = item.chapters else { return nil }
        guard let index = chapters.firstIndex(where: { $0.startPositionTicks == ticks }) else { return nil }
        return client.imageApi.getChapterImageUrl(itemId: item.id, chapterIndex: index, maxWidth: 480, tag: tag)
    }

    func personImageUrl(personId: String, tag: String, maxWidth: Int = 300, maxHeight: Int = 450) -> String {
        return client.imageApi.getItemImageUrl(itemId: personId, imageType: .primary, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
    }

    func fetchItem(itemId: String) async -> ServerItem? {
        try? await client.userLibraryApi.getItem(itemId: itemId)
    }

    var serverType: ServerType { client.serverType }

    func searchRemoteSubtitles(language: String) async throws -> [RemoteSubtitleResult] {
        guard let itemId = currentEntry?.item.id else { throw URLError(.cancelled) }
        return try await client.userLibraryApi.searchRemoteSubtitles(itemId: itemId, language: language)
    }

    func downloadRemoteSubtitle(subtitleId: String) async throws {
        guard let itemId = currentEntry?.item.id else { throw URLError(.cancelled) }
        try await client.userLibraryApi.downloadRemoteSubtitle(itemId: itemId, subtitleId: subtitleId)
    }

    init(
        player: VLCPlayerWrapper,
        client: MediaServerClient,
        preferences: UserPreferences
    ) {
        self.player = player
        self.client = client
        self.preferences = preferences
        let requestedBackend = PlaybackRolloutPolicy.effectiveRequestedDirective(
            requested: preferences[UserPreferences.playbackPlayerBackend],
            stage: preferences[UserPreferences.playbackMpvCanaryStage],
            localKillSwitch: preferences[UserPreferences.playbackMpvKillSwitchEnabled]
        )
        self.streamResolver = ServerStreamResolver(client: client, requestedBackend: requestedBackend)
        self.subtitleConfigurator = SubtitleConfigurator(preferences: preferences)

        let segmentRepo = MediaSegmentRepositoryImpl(preferences: preferences, client: client)
        self.segmentHandler = MediaSegmentHandler(repository: segmentRepo)
        self.nextUpManager = NextUpManager(preferences: preferences)

        player.configureSubtitleAppearance(subtitleConfigurator.mediaOptions())
        observePlayerState()
        observePosition()

        segmentHandler.skipTo = { [weak self] position in
            self?.seek(to: position)
        }

        nextUpManager.onPlayNext = { [weak self] in
            await self?.playNext()
        }

        nextUpManager.onDismiss = { [weak self] in
            self?.autoAdvanceOnEnd = false
        }
    }

    func play(
        items: [ServerItem],
        startIndex: Int = 0,
        startPosition: TimeInterval = 0,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        mediaSourceIndex: Int? = nil
    ) async {
        queue = items.enumerated().map { index, item in
            let sourceId: String?
            if index == startIndex, let msIndex = mediaSourceIndex,
               let sources = item.mediaSources, msIndex < sources.count {
                sourceId = sources[msIndex].id
            } else {
                sourceId = item.mediaSources?.first?.id
            }
            return QueueEntry(
                id: item.id,
                item: item,
                mediaSourceId: sourceId,
                startPositionTicks: index == startIndex ? Int64(startPosition * 10_000_000) : 0,
                audioStreamIndex: index == startIndex ? audioStreamIndex : nil,
                subtitleStreamIndex: index == startIndex ? subtitleStreamIndex : nil
            )
        }
        currentIndex = startIndex
        episodesPlayed = 0
        nextUpManager.resetForNewQueue()

        if preferences[UserPreferences.cinemaModeEnabled],
           let item = queue[safe: startIndex]?.item,
           item.type == .movie {
            await prependIntros(for: item)
        }

        await playCurrentEntry()
    }

    func playNext() async {
        guard hasNext else { return }
        await stopAndReport(failed: false)
        currentIndex += 1
        episodesPlayed += 1
        await playCurrentEntry()
    }

    func playPrevious() async {
        guard hasPrevious else { return }
        await stopAndReport(failed: false)
        currentIndex -= 1
        await playCurrentEntry()
    }

    func playEntry(at index: Int) async {
        guard index >= 0 && index < queue.count else { return }
        await stopAndReport(failed: false)
        currentIndex = index
        await playCurrentEntry()
    }

    func pause() {
        player.pause()
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func resume() {
        let rewind = TimeInterval(preferences[UserPreferences.unpauseRewindDuration])
        if rewind > 0 {
            let target = max(player.currentTime - rewind, 0)
            player.seek(to: target)
        }
        player.resume()
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func stop() async {
        await stopAndReport(failed: false)
        queue = []
        currentIndex = -1
        currentStreamInfo = nil
        playbackState = .idle
    }

    func seek(to position: TimeInterval) {
        player.seek(to: position)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func seek(by delta: TimeInterval) {
        player.seekBy(delta)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func setRate(_ rate: Float) {
        player.setRate(rate)
    }

    func setAudioTrack(_ index: Int32) {
        player.setAudioTrack(index)
        saveSelectedAudioLanguage(vlcTrackIndex: index)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func setSubtitleTrack(_ index: Int32) {
        player.setSubtitleTrack(index)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func addSubtitle(url: URL) {
        player.addSubtitle(url: url)
    }

    func replaceQueue(_ newQueue: [QueueEntry]) {
        queue = newQueue
        if currentIndex >= newQueue.count {
            currentIndex = max(newQueue.count - 1, 0)
        }
    }

    private var resolvedMaxBitrate: Int64? {
        let pref = preferences[UserPreferences.maxBitrate]
        return pref > 0 ? Int64(pref) : nil
    }

    private var resolvedMaxAudioChannels: Int? {
        preferences[UserPreferences.audioOutput] == .downmixToStereo ? 2 : nil
    }

    var skipForwardSeconds: TimeInterval {
        TimeInterval(preferences[UserPreferences.skipForwardLength])
    }

    private func prependIntros(for item: ServerItem) async {
        do {
            let intros = try await client.userLibraryApi.getIntros(itemId: item.id)
            guard !intros.isEmpty else { return }
            let introEntries = intros.map { intro in
                QueueEntry(
                    id: "intro_\(intro.id)",
                    item: intro,
                    mediaSourceId: intro.mediaSources?.first?.id,
                    startPositionTicks: 0
                )
            }
            queue.insert(contentsOf: introEntries, at: currentIndex)
        } catch { }
    }

    private func playCurrentEntry() async {
        guard let entry = currentEntry else { return }

        playbackState = .resolving

        let isAudioItem = entry.item.mediaType == .audio

        let audioIndex = entry.audioStreamIndex
        let subtitleIndex: Int?
        if isAudioItem {
            subtitleIndex = -1
        } else {
            subtitleIndex = entry.subtitleStreamIndex
                ?? (subtitleConfigurator.shouldDefaultToNone ? -1 : nil)
        }

        do {
            async let segmentsTask: () = loadSegmentsIfSupported(for: entry.item.id)

            let stream: StreamInfo
            if let prefetched = prefetchedStreamInfo, prefetchedItemId == entry.item.id {
                stream = prefetched
                prefetchedStreamInfo = nil
                prefetchedItemId = nil
            } else {
                stream = try await streamResolver.resolve(
                    item: entry.item,
                    mediaSourceId: entry.mediaSourceId,
                    maxBitrate: resolvedMaxBitrate,
                    maxAudioChannels: resolvedMaxAudioChannels,
                    audioStreamIndex: audioIndex,
                    subtitleStreamIndex: subtitleIndex,
                    startTimeTicks: entry.startPositionTicks > 0 ? entry.startPositionTicks : nil
                )
            }

            await segmentsTask

            currentStreamInfo = stream
            lastEvaluatedSecond = -1

            player.configurePreferredBackendForNextPlayback(stream.preferredBackend, fallbackReason: stream.fallbackReason)

            let startSeconds: TimeInterval
            if entry.startPositionTicks > 0 && stream.playMethod != .transcode {
                let raw = TimeInterval(entry.startPositionTicks) / 10_000_000
                let preRoll = TimeInterval(preferences[UserPreferences.resumeSubtractDuration])
                startSeconds = max(raw - preRoll, 0)
            } else {
                startSeconds = 0
            }

            if isAudioItem {
                player.configureSubtitleAppearance([:])
            } else {
                player.configureSubtitleAppearance(subtitleConfigurator.mediaOptions())
            }

            let delay = preferences[UserPreferences.videoStartDelay]
            if delay > 0 {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }

            startupBeganAt = Date()
            startupLatencyMs = nil
            hasSeenFirstPlayingState = false
            stallCount = 0
            terminalOutcome = "stopped"

            await player.play(streamUrl: stream.url, startPosition: startSeconds)

            let defaultZoom = preferences[UserPreferences.playerZoomMode]
            if defaultZoom != .fit {
                player.setZoomMode(defaultZoom)
            }

            applyPreferredAudioTrack(stream: stream)
            await reportPlaybackStart()
            startProgressReporting()
            prefetchNextStream()
        } catch {
            playbackState = .error(error.localizedDescription)
        }
    }

    private func prefetchNextStream() {
        prefetchTask?.cancel()
        guard let nextItem = nextEntry?.item else { return }
        if prefetchedItemId == nextItem.id { return }

        let subtitleIndex: Int?
        if nextItem.mediaType == .audio {
            subtitleIndex = -1
        } else {
            subtitleIndex = subtitleConfigurator.shouldDefaultToNone ? -1 : nil
        }
        let mediaSourceId = nextEntry?.mediaSourceId

        prefetchTask = Task { [weak self, streamResolver] in
            guard let self else { return }
            do {
                let stream = try await streamResolver.resolve(
                    item: nextItem,
                    mediaSourceId: mediaSourceId,
                    maxBitrate: resolvedMaxBitrate,
                    maxAudioChannels: resolvedMaxAudioChannels,
                    audioStreamIndex: nil,
                    subtitleStreamIndex: subtitleIndex,
                    startTimeTicks: nil
                )
                guard !Task.isCancelled else { return }
                self.prefetchedStreamInfo = stream
                self.prefetchedItemId = nextItem.id
            } catch {}
        }
    }

    private func loadSegmentsIfSupported(for itemId: String) async {
        if client.serverType.supports(.mediaSegments) {
            await segmentHandler.loadSegments(for: itemId)
        }
    }

    private func observePlayerState() {
        stateObserver = player.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] vlcState in
                guard let self else { return }
                switch vlcState {
                case .playing:
                    if !self.hasSeenFirstPlayingState {
                        self.hasSeenFirstPlayingState = true
                        if let started = self.startupBeganAt {
                            self.startupLatencyMs = Int(Date().timeIntervalSince(started) * 1000)
                        }
                    }
                    self.playbackState = .playing
                case .paused:
                    self.playbackState = .paused
                case .buffering(_):
                    if self.hasSeenFirstPlayingState {
                        self.stallCount += 1
                    }
                    self.playbackState = .buffering
                case .opening:
                    self.playbackState = .resolving
                case .ended:
                    self.terminalOutcome = "ended"
                    self.playbackState = .idle
                    Task { await self.handlePlaybackEnded() }
                case .error:
                    self.terminalOutcome = "error"
                    self.playbackState = .error("Playback error")
                    Task { await self.stopAndReport(failed: true) }
                case .stopped, .idle:
                    self.playbackState = .idle
                }
            }
    }

    private func handlePlaybackEnded() async {
        await stopAndReport(failed: false)
        guard autoAdvanceOnEnd else { return }
        if hasNext {
            currentIndex += 1
            episodesPlayed += 1
            await playCurrentEntry()
        } else {
            playbackState = .idle
        }
    }

    private func stopAndReport(failed: Bool) async {
        reportingTask?.cancel()
        reportingTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedStreamInfo = nil
        prefetchedItemId = nil
        segmentHandler.reset()
        nextUpManager.reset()
        lastEvaluatedSecond = -1
        await reportPlaybackStopped(failed: failed)
        emitPlaybackTelemetry(failed: failed)
        currentStreamInfo = nil
        player.stop()
    }

    private func emitPlaybackTelemetry(failed: Bool) {
        guard preferences[UserPreferences.telemetryEnabled] else { return }

        if failed {
            terminalOutcome = "failed"
        } else if terminalOutcome != "ended" {
            terminalOutcome = "stopped"
        }

        let backend = player.playbackBackendIdentifier
        let fallbackReason = player.playbackFallbackReason ?? "none"
        let startup = startupLatencyMs ?? -1

        logger.info(
            "playback_telemetry backend=\(backend, privacy: .public) fallback_reason=\(fallbackReason, privacy: .public) startup_latency_ms=\(startup) stall_count=\(self.stallCount) terminal_outcome=\(self.terminalOutcome, privacy: .public)"
        )
    }

    private func reportPlaybackStart() async {
        guard let entry = currentEntry, let stream = currentStreamInfo else { return }
        let reportedTracks = resolveReportedTrackIndexes(entry: entry, stream: stream)
        let report = PlaybackStartReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: entry.startPositionTicks,
            audioStreamIndex: reportedTracks.audioStreamIndex,
            subtitleStreamIndex: reportedTracks.subtitleStreamIndex,
            playMethod: stream.playMethod,
            isPaused: false,
            isMuted: false,
            volumeLevel: 100
        )
        try? await client.playbackApi.reportPlaybackStart(info: report)
    }

    private func startProgressReporting() {
        reportingTask?.cancel()
        reportingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.reportPlaybackProgress()
            }
        }
    }

    private func reportPlaybackProgress() async {
        guard let entry = currentEntry, let stream = currentStreamInfo else { return }
        let ticks = Int64(player.snapshotPlaybackPosition() * 10_000_000)
        let reportedTracks = resolveReportedTrackIndexes(entry: entry, stream: stream)
        let report = PlaybackProgressReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: ticks,
            audioStreamIndex: reportedTracks.audioStreamIndex,
            subtitleStreamIndex: reportedTracks.subtitleStreamIndex,
            playMethod: stream.playMethod,
            isPaused: player.state == .paused,
            isMuted: false,
            volumeLevel: 100
        )
        try? await client.playbackApi.reportPlaybackProgress(info: report)
    }

    private func reportPlaybackProgressBoundary() async {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastBoundaryProgressReportAt >= 0.5 else { return }
        lastBoundaryProgressReportAt = now
        await reportPlaybackProgress()
    }

    private func observePosition() {
        positionObserver = player.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                guard let self else { return }

                self.segmentHandler.onPositionUpdate(time)

                let second = Int(time)
                guard second != self.lastEvaluatedSecond else { return }
                self.lastEvaluatedSecond = second

                self.nextUpManager.evaluateEndOfPlayback(
                    currentTime: time,
                    duration: self.player.duration,
                    hasNext: self.hasNext,
                    episodesPlayed: self.episodesPlayed
                )
                if self.nextUpManager.promptState == .stillWatching {
                    self.pause()
                }
            }
    }

    private func reportPlaybackStopped(failed: Bool) async {
        guard let entry = currentEntry, let stream = currentStreamInfo else { return }
        let ticks = Int64(player.snapshotPlaybackPosition() * 10_000_000)
        let report = PlaybackStopReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: ticks,
            failed: failed
        )
        try? await client.playbackApi.reportPlaybackStopped(info: report)
    }

    private func resolveReportedTrackIndexes(entry: QueueEntry, stream: StreamInfo) -> (audioStreamIndex: Int?, subtitleStreamIndex: Int?) {
        let audio = mapPlayerTrackToServerStreamIndex(
            playerTrackId: player.currentAudioTrackIndex,
            playerTracks: player.audioTracks,
            serverStreams: stream.audioStreams,
            fallback: stream.defaultAudioStreamIndex
        )

        let subtitle: Int?
        if entry.item.mediaType == .audio {
            subtitle = nil
        } else {
            subtitle = mapPlayerTrackToServerStreamIndex(
                playerTrackId: player.currentSubtitleTrackIndex,
                playerTracks: player.subtitleTracks,
                serverStreams: stream.subtitleStreams,
                fallback: stream.defaultSubtitleStreamIndex
            )
        }

        return (audio, subtitle)
    }

    private func mapPlayerTrackToServerStreamIndex(
        playerTrackId: Int32,
        playerTracks: [VLCTrack],
        serverStreams: [ServerMediaStream],
        fallback: Int?
    ) -> Int? {
        guard playerTrackId != -1 else { return nil }
        guard let trackPosition = playerTracks.firstIndex(where: { $0.id == playerTrackId }) else {
            return fallback
        }
        guard trackPosition < serverStreams.count else { return fallback }
        return serverStreams[trackPosition].index
    }

    private func saveSelectedAudioLanguage(vlcTrackIndex: Int32) {
        guard let stream = currentStreamInfo else { return }
        let vlcTracks = player.audioTracks
        guard let trackPosition = vlcTracks.firstIndex(where: { $0.id == vlcTrackIndex }) else { return }
        let audioStreams = stream.audioStreams
        guard trackPosition < audioStreams.count else { return }
        if let language = audioStreams[trackPosition].language, !language.isEmpty {
            preferences[UserPreferences.lastAudioLanguage] = language
        }
    }

    private func applyPreferredAudioTrack(stream: StreamInfo) {
        let behavior = preferences[UserPreferences.audioBehavior]
        guard behavior == .previouslySelected else { return }
        let savedLanguage = preferences[UserPreferences.lastAudioLanguage]
        guard !savedLanguage.isEmpty else { return }

        if let matchIndex = stream.audioStreams.firstIndex(where: { $0.language == savedLanguage }) {
            let vlcTracks = player.audioTracks
            if matchIndex < vlcTracks.count {
                let vlcId = vlcTracks[matchIndex].id
                player.setAudioTrack(vlcId)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
