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

    let player: MpvPlayerWrapper
    let segmentHandler: MediaSegmentHandler
    let nextUpManager: NextUpManager

    private let client: MediaServerClient
    private let preferences: UserPreferences
    private let streamResolver: StreamResolver
    private let subtitleConfigurator: SubtitleConfigurator
    private let dataRefreshService: DataRefreshService?
    private var reportingTask: Task<Void, Never>?
    private var stateObserver: AnyCancellable?
    private var positionObserver: AnyCancellable?
    private var prefetchTask: Task<Void, Never>?
    private var prefetchedStreamInfo: StreamInfo?
    private var prefetchedItemId: String?
    private var suppressNextUpEvaluation = false
    private var lastEvaluatedSecond: Int = -1
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "PlaybackManager")
    private var startupBeganAt: Date?
    private var startupLatencyMs: Int?
    private var hasSeenFirstPlayingState = false
    private var dynamicRangeTelemetryEmitted = false
    private var dynamicRangeTelemetryTask: Task<Void, Never>?
    private var steadyStateTelemetryTask: Task<Void, Never>?
    private var stallCount = 0
    private var terminalOutcome = "stopped"
    private var lastBoundaryProgressReportAt: CFAbsoluteTime = 0
    private var playbackSessionToken: Int = 0
    private var userSubtitleOverrideSessionToken: Int?
    private var startupSubtitleEnforcementTask: Task<Void, Never>?
    private var startupExternalSubtitleLoadingTask: Task<Void, Never>?
    private var externalSubtitleTrackIdsByStreamIndex: [Int: Int32] = [:]
    private var externalSubtitleUrlsByStreamIndex: [Int: URL] = [:]

    private func subtitleDebug(_ message: @autoclosure () -> String) {}

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

    var activeSubtitleStreamIndex: Int? {
        guard let stream = currentStreamInfo else { return nil }
        let activeTrackId = player.currentSubtitleTrackIndex
        guard activeTrackId != -1 else { return nil }

        if let mappedExternalStreamIndex = externalSubtitleTrackIdsByStreamIndex
            .first(where: { $0.value == activeTrackId })?.key {
            return mappedExternalStreamIndex
        }

        let embeddedStreams = stream.subtitleStreams.filter { !$0.isExternal }
        guard let trackPosition = player.subtitleTracks.firstIndex(where: { $0.id == activeTrackId }) else {
            return nil
        }

        if trackPosition < embeddedStreams.count {
            return embeddedStreams[trackPosition].index
        }

        let externalStreams = stream.subtitleStreams.filter { $0.isExternal }
        let externalPosition = trackPosition - embeddedStreams.count
        guard externalPosition >= 0, externalPosition < externalStreams.count else { return nil }
        return externalStreams[externalPosition].index
    }

    func imageUrl(for item: ServerItem, type: ImageType = .primary, maxWidth: Int = 960, maxHeight: Int = 540) -> String? {
        if type == .backdrop, let tag = item.backdropImageTags?.first {
            return client.imageApi.getItemImageUrl(itemId: item.id, imageType: .backdrop, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
        }
        guard let tag = item.imageTags?["Primary"] else { return nil }
        return client.imageApi.getItemImageUrl(itemId: item.id, imageType: .primary, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
    }

    func logoUrl(for item: ServerItem, maxWidth: Int = 500) -> String? {
        if let logoTag = item.imageTags?["Logo"] {
            return client.imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .logo,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: logoTag
            )
        }
        if let seriesId = item.seriesId {
            return client.imageApi.getItemImageUrl(
                itemId: seriesId,
                imageType: .logo,
                maxWidth: maxWidth,
                maxHeight: nil,
                tag: nil
            )
        }
        return nil
    }

    func chapterImageUrl(for item: ServerItem, tag: String, ticks: Int64) -> String? {
        guard let chapters = item.chapters else { return nil }
        guard let index = chapters.firstIndex(where: { $0.startPositionTicks == ticks }) else { return nil }
        return client.imageApi.getChapterImageUrl(itemId: item.id, chapterIndex: index, maxWidth: 480, tag: tag)
    }

    func personImageUrl(personId: String, tag: String, maxWidth: Int = 300, maxHeight: Int = 450) -> String {
        return client.imageApi.getItemImageUrl(itemId: personId, imageType: .primary, maxWidth: maxWidth, maxHeight: maxHeight, tag: tag)
    }

    func fetchLiveTvChannels() async -> [ServerItem]? {
        do {
            let result = try await client.liveTvApi.getChannels(
                userId: client.userId,
                startIndex: nil,
                limit: nil,
                sortBy: "SortName",
                sortOrder: "Ascending",
                isFavorite: nil,
                addCurrentProgram: true
            )
            return result.items
        } catch {
            return nil
        }
    }

    func fetchItem(itemId: String) async -> ServerItem? {
        try? await client.userLibraryApi.getItem(itemId: itemId)
    }

    var serverType: ServerType { client.serverType }
    var serverBaseUrl: String? { client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var serverAccessToken: String? { client.accessToken }
    var maxBitratePreference: Int { preferences[UserPreferences.maxBitrate] }

    var trickPlayEnabled: Bool {
        preferences[UserPreferences.trickPlayEnabled] && serverType.supports(.trickplay)
    }

    func searchRemoteSubtitles(language: String) async throws -> [RemoteSubtitleResult] {
        guard let itemId = currentEntry?.item.id else { throw URLError(.cancelled) }
        return try await client.userLibraryApi.searchRemoteSubtitles(itemId: itemId, language: language)
    }

    func downloadRemoteSubtitle(subtitleId: String) async throws {
        guard let itemId = currentEntry?.item.id else { throw URLError(.cancelled) }
        try await client.userLibraryApi.downloadRemoteSubtitle(itemId: itemId, subtitleId: subtitleId)
    }

    init(
        player: MpvPlayerWrapper,
        client: MediaServerClient,
        preferences: UserPreferences,
        dataRefreshService: DataRefreshService? = nil
    ) {
        self.player = player
        self.client = client
        self.preferences = preferences
        self.dataRefreshService = dataRefreshService
        self.streamResolver = ServerStreamResolver(
            client: client,
            requestedBackend: .mpv,
            nativeDvEnabled: preferences[UserPreferences.nativeDvDecodeEnabled]
        )
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
            guard let self else { return }
            self.suppressNextUpEvaluation = true
            self.autoAdvanceOnEnd = false
            await self.playNext(startFromBeginning: true)
            self.autoAdvanceOnEnd = true
            self.suppressNextUpEvaluation = false
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
              startPosition <= 0,
           let item = queue[safe: startIndex]?.item,
           item.type == .movie {
            await prependIntros(for: item)
        }

        await playCurrentEntry()
    }

    func playNext(startFromBeginning: Bool = false) async {
        guard hasNext else { return }
        if startFromBeginning {
            let nextIndex = currentIndex + 1
            if queue.indices.contains(nextIndex) {
                queue[nextIndex].startPositionTicks = 0
            }
        }
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

    func resume(applyRewind: Bool = true) {
        if applyRewind {
            let rewind = TimeInterval(preferences[UserPreferences.unpauseRewindDuration])
            if rewind > 0 {
                let target = max(player.currentTime - rewind, 0)
                player.seek(to: target)
            }
        }
        player.resume()
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func stop() async {
        recordPlaybackTrigger()
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

    func setMaxBitrate(_ bitrate: Int) {
        preferences[UserPreferences.maxBitrate] = bitrate
    }

    func setAudioTrack(_ index: Int32) {
        player.setAudioTrack(index)
        saveSelectedAudioLanguage(trackIndex: index)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func setSubtitleTrack(_ index: Int32) {
        markUserSubtitleOverrideForCurrentSession()
        subtitleDebug("subtitle_select_direct track_id=\(index) session=\(self.playbackSessionToken) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))")
        player.setSubtitleTrack(index)
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func disableSubtitles() {
        markUserSubtitleOverrideForCurrentSession()
        subtitleDebug("subtitle_disable session=\(self.playbackSessionToken) current_track=\(self.player.currentSubtitleTrackIndex)")
        player.disableSubtitles()
        Task { [weak self] in
            await self?.reportPlaybackProgressBoundary()
        }
    }

    func addSubtitle(url: URL) {
        subtitleDebug("subtitle_add request_url=\(self.redactedURLString(url)) session=\(self.playbackSessionToken)")
        player.addSubtitle(url: url)
    }

    func selectSubtitleStream(_ stream: ServerMediaStream) {
        markUserSubtitleOverrideForCurrentSession()
        let sessionToken = playbackSessionToken
        subtitleDebug(
            "subtitle_select_stream request session=\(sessionToken) stream=\(self.subtitleStreamDebugSummary(stream)) active_track=\(self.player.currentSubtitleTrackIndex) mapped_externals=\(self.externalSubtitleTrackIdsByStreamIndex.count) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
        )

        Task { [weak self] in
            guard let self else { return }
            guard self.playbackSessionToken == sessionToken else {
                self.subtitleDebug("subtitle_select_stream drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                return
            }

            if stream.isExternal {
                self.subtitleDebug("subtitle_select_stream path=external stream_index=\(stream.index) session=\(sessionToken)")
                await self.loadAndSelectExternalSubtitle(stream, sessionToken: sessionToken, entry: self.currentEntry)
                guard self.playbackSessionToken == sessionToken else {
                    self.subtitleDebug("subtitle_select_stream external_complete dropped session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                    return
                }
                self.subtitleDebug("subtitle_select_stream external_complete stream_index=\(stream.index) selected_track=\(self.player.currentSubtitleTrackIndex)")
                await self.reportPlaybackProgressBoundary()
                return
            }

            if let currentStream = self.currentStreamInfo,
               let embeddedTrackId = self.embeddedSubtitleTrackId(for: stream.index, in: currentStream) {
                self.subtitleDebug("subtitle_select_stream path=embedded_positional stream_index=\(stream.index) track_id=\(embeddedTrackId)")
                self.player.setSubtitleTrack(embeddedTrackId)
                await self.reportPlaybackProgressBoundary()
                return
            }

            let embeddedCandidateIds = self.embeddedSubtitleCandidateTrackIds(stream: self.currentStreamInfo)
            if let matchedTrackId = self.matchSubtitleTrackId(stream, candidateTrackIds: embeddedCandidateIds) {
                self.subtitleDebug("subtitle_select_stream path=embedded_match stream_index=\(stream.index) track_id=\(matchedTrackId) candidates=\(embeddedCandidateIds.count)")
                self.player.setSubtitleTrack(matchedTrackId)
                await self.reportPlaybackProgressBoundary()
                return
            }

            self.logger.warning(
                "subtitle_select_stream no_match stream=\(self.subtitleStreamDebugSummary(stream)) active_track=\(self.player.currentSubtitleTrackIndex) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
            )
        }
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

    private var resolvedAtmosPassthroughEnabled: Bool {
        preferences[UserPreferences.audioOutput] == .passthroughAtmos
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

        startupSubtitleEnforcementTask?.cancel()
        startupSubtitleEnforcementTask = nil
        startupExternalSubtitleLoadingTask?.cancel()
        startupExternalSubtitleLoadingTask = nil
        playbackSessionToken += 1
        let currentSessionToken = playbackSessionToken
        userSubtitleOverrideSessionToken = nil
        externalSubtitleTrackIdsByStreamIndex = [:]
        externalSubtitleUrlsByStreamIndex = [:]

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
        let shouldEnforceSubtitlesOffAtStartup = !isAudioItem && entry.subtitleStreamIndex == nil && subtitleConfigurator.shouldDefaultToNone

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
                    atmosPassthroughEnabled: resolvedAtmosPassthroughEnabled,
                    audioStreamIndex: audioIndex,
                    subtitleStreamIndex: subtitleIndex,
                    startTimeTicks: entry.startPositionTicks > 0 ? entry.startPositionTicks : nil
                )
            }

            await segmentsTask

            currentStreamInfo = stream
            lastEvaluatedSecond = -1

            let sinkCapabilities = await MainActor.run { VideoCapabilityDetector.current() }
            player.configurePlaybackQualityProfile(
                preferences[UserPreferences.playbackQualityProfile],
                generation: sinkCapabilities.generation
            )
            player.configureDolbyVisionMetadata(
                profile: stream.dvProfile,
                level: stream.dvLevel,
                blSignalCompatibilityId: stream.dvBlSignalCompatibilityId
            )
            player.configurePreferredBackendForNextPlayback(stream.preferredBackend, fallbackReason: stream.fallbackReason)
            if isAudioItem {
                player.configurePreferredRenderFramesPerSecond(nil)
            } else {
                let legacyRenderFpsHint = await MainActor.run { DisplayCriteriaManager.shared.apply(stream: stream) }
                player.configurePreferredRenderFramesPerSecond(legacyRenderFpsHint)
                await Task.yield()
            }
            player.configureDynamicRangeIntent(
                contentRange: stream.dynamicRange,
                sinkIsHdrCapable: sinkCapabilities.sinkProfile.isHdrCapable
            )

            let startSeconds: TimeInterval
            if entry.startPositionTicks > 0 {
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
            dynamicRangeTelemetryEmitted = false
            dynamicRangeTelemetryTask?.cancel()
            dynamicRangeTelemetryTask = nil
            steadyStateTelemetryTask?.cancel()
            steadyStateTelemetryTask = nil
            stallCount = 0
            terminalOutcome = "stopped"

            player.setForceSubtitlesDisabledOnStart(shouldEnforceSubtitlesOffAtStartup)
            await player.play(streamUrl: stream.url, startPosition: startSeconds, audioOnly: isAudioItem)

            let defaultZoom = preferences[UserPreferences.playerZoomMode]
            if defaultZoom != .fit {
                player.setZoomMode(defaultZoom)
            }

            enforceSubtitleOffAtStartupIfNeeded(sessionToken: currentSessionToken, enabled: shouldEnforceSubtitlesOffAtStartup)

            applyPreferredAudioTrack(stream: stream)
            let externalSubtitleStreams = stream.subtitleStreams.filter { $0.isExternal }
            let hasExternalSubtitles = !externalSubtitleStreams.isEmpty
            let hasSubtitleSelection = (entry.subtitleStreamIndex ?? -1) >= 0
            subtitleDebug(
                "subtitle_startup stream_subtitles=\(stream.subtitleStreams.count) external_subtitles=\(externalSubtitleStreams.count) selected_stream_index=\(entry.subtitleStreamIndex ?? -999) default_stream_index=\(stream.defaultSubtitleStreamIndex ?? -999) has_external=\(hasExternalSubtitles) has_selection=\(hasSubtitleSelection) session=\(currentSessionToken)"
            )
            if hasExternalSubtitles || hasSubtitleSelection {
                startupExternalSubtitleLoadingTask = Task { [weak self] in
                    guard let self else { return }
                    await self.loadExternalSubtitlesAndApplySelection(
                        stream: stream,
                        externalStreams: externalSubtitleStreams,
                        entry: entry,
                        sessionToken: currentSessionToken
                    )
                }
            }

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
                    atmosPassthroughEnabled: resolvedAtmosPassthroughEnabled,
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
                        if self.preferences[UserPreferences.telemetryEnabled] {
                            self.dynamicRangeTelemetryTask?.cancel()
                            self.dynamicRangeTelemetryTask = Task { [weak self] in
                                try? await Task.sleep(for: .seconds(2))
                                await MainActor.run {
                                    self?.emitDynamicRangeTelemetryIfNeeded()
                                }
                            }

                            self.steadyStateTelemetryTask?.cancel()
                            self.steadyStateTelemetryTask = Task { [weak self] in
                                try? await Task.sleep(for: .seconds(10))
                                await MainActor.run {
                                    guard let self else { return }
                                    if self.playbackState == .playing {
                                        self.emitDynamicRangeTelemetry(stage: "mid", steadyState: true)
                                    }
                                    self.steadyStateTelemetryTask = nil
                                }
                            }
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
        recordPlaybackTrigger()
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
        startupSubtitleEnforcementTask?.cancel()
        startupSubtitleEnforcementTask = nil
        startupExternalSubtitleLoadingTask?.cancel()
        startupExternalSubtitleLoadingTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        dynamicRangeTelemetryTask?.cancel()
        dynamicRangeTelemetryTask = nil
        steadyStateTelemetryTask?.cancel()
        steadyStateTelemetryTask = nil
        prefetchedStreamInfo = nil
        prefetchedItemId = nil
        externalSubtitleTrackIdsByStreamIndex = [:]
        externalSubtitleUrlsByStreamIndex = [:]
        segmentHandler.reset()
        nextUpManager.reset()
        lastEvaluatedSecond = -1
        await reportPlaybackStopped(failed: failed)
        emitPlaybackTelemetry(failed: failed)
        emitDynamicRangeTelemetry(stage: "end")
        currentStreamInfo = nil
        player.stop()
        await MainActor.run { DisplayCriteriaManager.shared.reset() }
    }

    private func recordPlaybackTrigger() {
        guard let item = currentEntry?.item else { return }
        switch item.type {
        case .movie, .video, .trailer:
            dataRefreshService?.recordMoviePlayback()
        case .audio:
            dataRefreshService?.recordPlayback()
        default:
            dataRefreshService?.recordTvPlayback()
        }
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
            "playback_telemetry backend=\(backend) fallback_reason=\(fallbackReason) startup_latency_ms=\(startup) stall_count=\(self.stallCount) terminal_outcome=\(self.terminalOutcome)"
        )
    }

    private func emitDynamicRangeTelemetryIfNeeded() {
        guard !dynamicRangeTelemetryEmitted else { return }
        guard preferences[UserPreferences.telemetryEnabled] else { return }
        guard currentStreamInfo != nil else { return }
        dynamicRangeTelemetryEmitted = true
        emitDynamicRangeTelemetry(stage: "start")
    }

    private func emitDynamicRangeTelemetry(stage: String, steadyState: Bool = false) {
        guard preferences[UserPreferences.telemetryEnabled] else { return }
        guard let stream = currentStreamInfo else { return }

        var streamTelemetry = [
            "stream_dynamic_range=\(stream.dynamicRange.rawValue)",
            "stream_play_method=\(stream.playMethod.rawValue)",
            "stream_backend=\(stream.preferredBackend.rawValue)",
            "stream_fallback_reason=\(stream.fallbackReason ?? "none")",
            "telemetry_stage=\(stage)"
        ]
        if steadyState {
            streamTelemetry.append("steady_state=true")
        }

        let outputTelemetry = player.dynamicRangeTelemetrySnapshot()
            .map { "\($0.key)=\($0.value)" }
            .sorted()

        logger.info(
            "playback_dynamic_range \((streamTelemetry + outputTelemetry).joined(separator: " "))"
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

                guard !self.suppressNextUpEvaluation else { return }

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
            subtitle = activeSubtitleStreamIndex ?? stream.defaultSubtitleStreamIndex
        }

        return (audio, subtitle)
    }

    private func markUserSubtitleOverrideForCurrentSession() {
        userSubtitleOverrideSessionToken = playbackSessionToken
    }

    private func enforceSubtitleOffAtStartupIfNeeded(sessionToken: Int, enabled: Bool) {
        guard enabled else { return }

        player.disableSubtitles()

        startupSubtitleEnforcementTask?.cancel()
        startupSubtitleEnforcementTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                guard self.playbackSessionToken == sessionToken else { return }
                guard self.userSubtitleOverrideSessionToken != sessionToken else { return }

                let subtitleIsOff = self.player.currentSubtitleTrackIndex == -1
                let tracksReady = !self.player.subtitleTracks.isEmpty
                let playerReady = self.player.state == .playing || self.player.state == .paused

                if subtitleIsOff && (tracksReady || playerReady) {
                    return
                }

                self.player.disableSubtitles()
            }
        }
    }

    private func buildExternalSubtitleURL(_ deliveryUrl: String) -> URL? {
        let trimmedUrl = deliveryUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return nil }

        let sourceUrl: String
        let lowercased = trimmedUrl.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            sourceUrl = trimmedUrl
        } else {
            guard let baseUrl = serverBaseUrl else { return nil }
            sourceUrl = trimmedUrl.hasPrefix("/") ? "\(baseUrl)\(trimmedUrl)" : "\(baseUrl)/\(trimmedUrl)"
        }

        guard var components = URLComponents(string: sourceUrl) else { return nil }

        if let token = serverAccessToken, !token.isEmpty {
            var queryItems = components.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "api_key" }) {
                queryItems.append(URLQueryItem(name: "api_key", value: token))
            }
            components.queryItems = queryItems
        }

        return components.url
    }

    private func loadAndSelectExternalSubtitle(_ stream: ServerMediaStream, sessionToken: Int, entry: QueueEntry? = nil) async {
        subtitleDebug(
            "subtitle_external_load begin session=\(sessionToken) stream=\(self.subtitleStreamDebugSummary(stream)) active_track=\(self.player.currentSubtitleTrackIndex) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks)) mapped=\(self.externalSubtitleTrackIdsByStreamIndex.count)"
        )
        guard playbackSessionToken == sessionToken else {
            subtitleDebug("subtitle_external_load drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
            return
        }

        if let mappedTrackId = externalSubtitleTrackIdsByStreamIndex[stream.index] {
            subtitleDebug("subtitle_external_load mapped_hit stream_index=\(stream.index) track_id=\(mappedTrackId)")
            player.setSubtitleTrack(mappedTrackId)
            return
        }

        if let currentStream = currentStreamInfo,
           let positionalTrackId = externalSubtitleTrackId(for: stream.index, in: currentStream) {
            externalSubtitleTrackIdsByStreamIndex[stream.index] = positionalTrackId
            subtitleDebug("subtitle_external_load positional_hit stream_index=\(stream.index) track_id=\(positionalTrackId)")
            player.setSubtitleTrack(positionalTrackId)
            return
        }

        let preAddCandidateTrackIds = externalSubtitleCandidateTrackIds(stream: currentStreamInfo)
        if let preAddMatch = matchSubtitleTrackId(stream, candidateTrackIds: preAddCandidateTrackIds) {
            externalSubtitleTrackIdsByStreamIndex[stream.index] = preAddMatch
            subtitleDebug("subtitle_external_load preadd_match stream_index=\(stream.index) track_id=\(preAddMatch) candidates=\(preAddCandidateTrackIds.count)")
            player.setSubtitleTrack(preAddMatch)
            return
        }

        guard let subtitleUrl = await resolveExternalSubtitleURL(for: stream, entry: entry, streamInfo: currentStreamInfo) else {
            logger.warning("subtitle_external_load unresolved_url stream=\(self.subtitleStreamDebugSummary(stream))")
            return
        }

        let existingTrackIds = Set(player.subtitleTracks.map(\.id))
        subtitleDebug("subtitle_external_load sub_add stream_index=\(stream.index) url=\(self.redactedURLString(subtitleUrl)) existing_tracks=\(existingTrackIds.count)")
        addSubtitle(url: subtitleUrl)

        for attempt in 0..<20 {
            guard playbackSessionToken == sessionToken else {
                subtitleDebug("subtitle_external_load poll_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                return
            }

            let addedTracks = player.subtitleTracks.filter { !existingTrackIds.contains($0.id) }

            if let firstAddedTrack = addedTracks.first {
                externalSubtitleTrackIdsByStreamIndex[stream.index] = firstAddedTrack.id
                subtitleDebug(
                    "subtitle_external_load poll_success attempt=\(attempt + 1) stream_index=\(stream.index) track_id=\(firstAddedTrack.id) added_count=\(addedTracks.count) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
                )
                player.setSubtitleTrack(firstAddedTrack.id)
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard playbackSessionToken == sessionToken else {
            subtitleDebug("subtitle_external_load post_poll_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
            return
        }

        logger.warning(
            "subtitle_external_load poll_timeout stream_index=\(stream.index) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
        )

        if let mappedTrackId = externalSubtitleTrackIdsByStreamIndex[stream.index] {
            subtitleDebug("subtitle_external_load mapped_fallback stream_index=\(stream.index) track_id=\(mappedTrackId)")
            player.setSubtitleTrack(mappedTrackId)
            return
        }

        let candidateTrackIds = externalSubtitleCandidateTrackIds(stream: currentStreamInfo)
        if let matchedTrackId = matchSubtitleTrackId(stream, candidateTrackIds: candidateTrackIds) {
            externalSubtitleTrackIdsByStreamIndex[stream.index] = matchedTrackId
            subtitleDebug("subtitle_external_load match_fallback stream_index=\(stream.index) track_id=\(matchedTrackId) candidates=\(candidateTrackIds.count)")
            player.setSubtitleTrack(matchedTrackId)
            return
        }

        logger.error(
            "subtitle_external_load failed stream=\(self.subtitleStreamDebugSummary(stream)) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
        )
    }

    private func loadExternalSubtitlesAndApplySelection(
        stream: StreamInfo,
        externalStreams: [ServerMediaStream],
        entry: QueueEntry,
        sessionToken: Int
    ) async {
        subtitleDebug(
            "subtitle_startup_load begin session=\(sessionToken) selected_stream_index=\(entry.subtitleStreamIndex ?? -999) default_stream_index=\(stream.defaultSubtitleStreamIndex ?? -999) stream_subtitles=\(stream.subtitleStreams.count) external_streams=\(externalStreams.count) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
        )
        let embeddedSubtitleCount = stream.subtitleStreams.filter { !$0.isExternal }.count
        var readinessSatisfied = false

        for attempt in 0..<20 {
            guard playbackSessionToken == sessionToken else {
                subtitleDebug("subtitle_startup_load drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                return
            }

            let tracksReady = player.subtitleTracks.count >= embeddedSubtitleCount
            let playerReady: Bool
            switch player.state {
            case .buffering, .playing, .paused:
                playerReady = true
            default:
                playerReady = false
            }

            if tracksReady && playerReady {
                readinessSatisfied = true
                subtitleDebug(
                    "subtitle_startup_load readiness attempt=\(attempt + 1) tracks_ready=\(tracksReady) player_ready=\(playerReady) track_count=\(self.player.subtitleTracks.count) embedded_expected=\(embeddedSubtitleCount) state=\(String(describing: self.player.state))"
                )
                break
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if !readinessSatisfied {
            logger.warning(
                "subtitle_startup_load readiness_timeout track_count=\(self.player.subtitleTracks.count) embedded_expected=\(embeddedSubtitleCount) state=\(String(describing: self.player.state))"
            )
        }

        guard playbackSessionToken == sessionToken else {
            subtitleDebug("subtitle_startup_load pre_select_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
            return
        }

        let preferredStreamIndex = preferredSubtitleStreamIndex(stream: stream, entry: entry)
        let preferredExternalStream = preferredStreamIndex.flatMap { selectedIndex in
            externalStreams.first(where: { $0.index == selectedIndex })
        }
        subtitleDebug(
            "subtitle_startup_load preferred stream_index=\(preferredStreamIndex ?? -999) preferred_external=\(preferredExternalStream != nil) backend=\(self.player.playbackBackendIdentifier)"
        )

        if player.playbackBackendIdentifier == PlaybackBackendDirective.native.rawValue {
            guard playbackSessionToken == sessionToken else {
                subtitleDebug("subtitle_startup_load native_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                return
            }
            guard userSubtitleOverrideSessionToken != sessionToken else {
                subtitleDebug("subtitle_startup_load native_drop user_override session=\(sessionToken)")
                return
            }

            if let preferredExternalStream {
                await loadAndSelectExternalSubtitle(preferredExternalStream, sessionToken: sessionToken, entry: entry)
            } else {
                applyPreferredSubtitleTrack(stream: stream, entry: entry)
            }
            return
        }

        let existingTrackIds = Set(player.subtitleTracks.map(\.id))
        var successfullyAddedExternalStreamIndexes: [Int] = []

        for subtitleStream in externalStreams {
            guard playbackSessionToken == sessionToken else {
                subtitleDebug("subtitle_startup_load sub_add_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                return
            }
            guard let subtitleUrl = await resolveExternalSubtitleURL(for: subtitleStream, entry: entry, streamInfo: stream) else {
                logger.warning("subtitle_startup_load skip_unresolved_url stream=\(self.subtitleStreamDebugSummary(subtitleStream))")
                continue
            }

            subtitleDebug("subtitle_startup_load sub_add stream_index=\(subtitleStream.index) url=\(self.redactedURLString(subtitleUrl))")
            addSubtitle(url: subtitleUrl)
            successfullyAddedExternalStreamIndexes.append(subtitleStream.index)
        }

        var externalTrackIdsByStreamIndex: [Int: Int32] = [:]

        if !successfullyAddedExternalStreamIndexes.isEmpty {
            for attempt in 0..<20 {
                guard playbackSessionToken == sessionToken else {
                    subtitleDebug("subtitle_startup_load map_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
                    return
                }
                let addedTracks = player.subtitleTracks.filter { !existingTrackIds.contains($0.id) }
                if addedTracks.count >= successfullyAddedExternalStreamIndexes.count {
                    for (offset, streamIndex) in successfullyAddedExternalStreamIndexes.enumerated()
                    where offset < addedTracks.count {
                        externalTrackIdsByStreamIndex[streamIndex] = addedTracks[offset].id
                    }
                    subtitleDebug(
                        "subtitle_startup_load map_success attempt=\(attempt + 1) mapped=\(externalTrackIdsByStreamIndex.count) expected=\(successfullyAddedExternalStreamIndexes.count)"
                    )
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if externalTrackIdsByStreamIndex.isEmpty {
                let addedTracks = player.subtitleTracks.filter { !existingTrackIds.contains($0.id) }
                for (offset, streamIndex) in successfullyAddedExternalStreamIndexes.enumerated()
                where offset < addedTracks.count {
                    externalTrackIdsByStreamIndex[streamIndex] = addedTracks[offset].id
                }
            }
        }

        if !externalTrackIdsByStreamIndex.isEmpty {
            externalSubtitleTrackIdsByStreamIndex.merge(externalTrackIdsByStreamIndex) { _, new in new }
            subtitleDebug("subtitle_startup_load map_merged mapped=\(externalTrackIdsByStreamIndex.count) global=\(self.externalSubtitleTrackIdsByStreamIndex.count)")
        } else if !successfullyAddedExternalStreamIndexes.isEmpty {
            logger.warning("subtitle_startup_load map_empty expected=\(successfullyAddedExternalStreamIndexes.count) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))")
        }

        guard playbackSessionToken == sessionToken else {
            subtitleDebug("subtitle_startup_load apply_drop session_mismatch request=\(sessionToken) active=\(self.playbackSessionToken)")
            return
        }
        guard userSubtitleOverrideSessionToken != sessionToken else {
            subtitleDebug("subtitle_startup_load apply_drop user_override session=\(sessionToken)")
            return
        }
        applyPreferredSubtitleTrack(
            stream: stream,
            entry: entry,
            externalTrackIdsByStreamIndex: externalTrackIdsByStreamIndex
        )
    }

    private func resolveExternalSubtitleURL(
        for stream: ServerMediaStream,
        entry: QueueEntry?,
        streamInfo: StreamInfo?
    ) async -> URL? {
        if let cachedUrl = externalSubtitleUrlsByStreamIndex[stream.index] {
            subtitleDebug("subtitle_url_resolve cache_hit stream_index=\(stream.index) url=\(self.redactedURLString(cachedUrl))")
            return cachedUrl
        }

        if let deliveryUrl = stream.deliveryUrl,
           let resolved = buildExternalSubtitleURL(deliveryUrl) {
            if await validateExternalSubtitleURLCandidate(resolved, source: "stream_delivery", streamIndex: stream.index) {
                externalSubtitleUrlsByStreamIndex[stream.index] = resolved
                subtitleDebug("subtitle_url_resolve stream_delivery stream_index=\(stream.index) url=\(self.redactedURLString(resolved))")
                return resolved
            }
        }

        let preferredMediaSourceId = streamInfo?.mediaSourceId ?? entry?.mediaSourceId

        if let entryDeliveryUrl = externalDeliveryUrlFromEntryItem(
            streamIndex: stream.index,
            entry: entry,
            preferredMediaSourceId: preferredMediaSourceId
        ),
           let resolved = buildExternalSubtitleURL(entryDeliveryUrl) {
            if await validateExternalSubtitleURLCandidate(resolved, source: "entry_delivery", streamIndex: stream.index) {
                externalSubtitleUrlsByStreamIndex[stream.index] = resolved
                subtitleDebug("subtitle_url_resolve entry_delivery stream_index=\(stream.index) url=\(self.redactedURLString(resolved))")
                return resolved
            }
        }

        if let refreshedDeliveryUrl = await fetchExternalDeliveryUrlFromPlaybackInfo(
            streamIndex: stream.index,
            entry: entry,
            preferredMediaSourceId: preferredMediaSourceId
        ),
           let resolved = buildExternalSubtitleURL(refreshedDeliveryUrl) {
            if await validateExternalSubtitleURLCandidate(resolved, source: "playback_info", streamIndex: stream.index) {
                externalSubtitleUrlsByStreamIndex[stream.index] = resolved
                subtitleDebug("subtitle_url_resolve playback_info stream_index=\(stream.index) url=\(self.redactedURLString(resolved))")
                return resolved
            }
        }

        if let synthesized = await buildSyntheticExternalSubtitleURL(
            streamIndex: stream.index,
            codec: stream.codec,
            entry: entry,
            preferredMediaSourceId: preferredMediaSourceId
        ) {
            externalSubtitleUrlsByStreamIndex[stream.index] = synthesized
            subtitleDebug("subtitle_url_resolve synthesized stream_index=\(stream.index) url=\(self.redactedURLString(synthesized))")
            return synthesized
        }

        logger.warning("subtitle_url_resolve failed stream=\(self.subtitleStreamDebugSummary(stream))")
        return nil
    }

    private func externalDeliveryUrlFromEntryItem(
        streamIndex: Int,
        entry: QueueEntry?,
        preferredMediaSourceId: String?
    ) -> String? {
        let queueEntry = entry ?? currentEntry
        guard let queueEntry else { return nil }

        let selectedSource = queueEntry.item.mediaSources?.first(where: { $0.id == preferredMediaSourceId })
            ?? queueEntry.item.mediaSources?.first(where: { $0.id == queueEntry.mediaSourceId })
            ?? queueEntry.item.mediaSources?.first

        let sourceStreams = selectedSource?.mediaStreams ?? []
        if let delivery = sourceStreams.first(where: { $0.type == .subtitle && $0.index == streamIndex })?.deliveryUrl {
            let trimmed = delivery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let itemStreams = queueEntry.item.mediaStreams ?? []
        if let delivery = itemStreams.first(where: { $0.type == .subtitle && $0.index == streamIndex })?.deliveryUrl {
            let trimmed = delivery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func fetchExternalDeliveryUrlFromPlaybackInfo(
        streamIndex: Int,
        entry: QueueEntry?,
        preferredMediaSourceId: String?
    ) async -> String? {
        let queueEntry = entry ?? currentEntry
        guard let queueEntry else { return nil }
        guard let userId = client.userId else {
            subtitleDebug("subtitle_url_resolve playback_info_skip missing_user_id")
            return nil
        }

        let request = PlaybackInfoRequest(
            userId: userId,
            mediaSourceId: preferredMediaSourceId,
            subtitleStreamIndex: streamIndex
        )

        do {
            let result = try await client.playbackApi.getPlaybackInfo(itemId: queueEntry.item.id, request: request)
            let source = result.mediaSources.first(where: { $0.id == preferredMediaSourceId }) ?? result.mediaSources.first
            guard let source else {
                subtitleDebug("subtitle_url_resolve playback_info_no_source stream_index=\(streamIndex)")
                return nil
            }

            if let delivery = source.mediaStreams
                .first(where: { $0.type == .subtitle && $0.index == streamIndex })?
                .deliveryUrl {
                let trimmed = delivery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    subtitleDebug("subtitle_url_resolve playback_info_delivery_found stream_index=\(streamIndex)")
                    return trimmed
                }
            }

            subtitleDebug("subtitle_url_resolve playback_info_delivery_missing stream_index=\(streamIndex)")
            return nil
        } catch {
            logger.warning("subtitle_url_resolve playback_info_error stream_index=\(streamIndex) error=\(error.localizedDescription)")
            return nil
        }
    }

    private func buildSyntheticExternalSubtitleURL(
        streamIndex: Int,
        codec: String?,
        entry: QueueEntry?,
        preferredMediaSourceId: String?
    ) async -> URL? {
        let queueEntry = entry ?? currentEntry
        guard let queueEntry else { return nil }

        let itemId = queueEntry.item.id
        let mediaSourceId = preferredMediaSourceId ?? queueEntry.mediaSourceId
        let fileExtension = subtitleFileExtension(for: codec)

        var candidates: [String] = []
        if let mediaSourceId, !mediaSourceId.isEmpty {
            candidates.append("/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/Stream.\(fileExtension)")
            candidates.append("/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/Stream")
        }
        candidates.append("/Videos/\(itemId)/Subtitles/\(streamIndex)/Stream.\(fileExtension)")
        candidates.append("/Videos/\(itemId)/Subtitles/\(streamIndex)/Stream")

        for candidate in candidates {
            guard let resolved = buildExternalSubtitleURL(candidate) else { continue }
            if await validateExternalSubtitleURLCandidate(resolved, source: "synthesized", streamIndex: streamIndex) {
                return resolved
            }
        }

        return nil
    }

    private func validateExternalSubtitleURLCandidate(_ url: URL, source: String, streamIndex: Int) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.httpMethod = "GET"
        request.setValue("bytes=0-1024", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.warning("subtitle_url_validate no_http_response source=\(source) stream_index=\(streamIndex) url=\(self.redactedURLString(url))")
                return false
            }

            let statusCode = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""

            guard statusCode == 200 || statusCode == 206 else {
                logger.warning("subtitle_url_validate bad_status source=\(source) stream_index=\(streamIndex) status=\(statusCode) content_type=\(contentType) url=\(self.redactedURLString(url))")
                return false
            }

            guard !data.isEmpty else {
                logger.warning("subtitle_url_validate empty_body source=\(source) stream_index=\(streamIndex) status=\(statusCode) url=\(self.redactedURLString(url))")
                return false
            }

            let payloadLooksValid = isLikelySubtitlePayload(data: data, contentType: contentType)
            if !payloadLooksValid {
                let preview = String(data: data.prefix(120), encoding: .utf8)?.replacingOccurrences(of: "\n", with: " ") ?? "<binary>"
                logger.warning(
                    "subtitle_url_validate payload_rejected source=\(source) stream_index=\(streamIndex) status=\(statusCode) content_type=\(contentType) preview=\(preview) url=\(self.redactedURLString(url))"
                )
                return false
            }

            subtitleDebug("subtitle_url_validate success source=\(source) stream_index=\(streamIndex) status=\(statusCode) content_type=\(contentType) bytes=\(data.count) url=\(self.redactedURLString(url))")
            return true
        } catch {
            logger.warning("subtitle_url_validate request_error source=\(source) stream_index=\(streamIndex) error=\(error.localizedDescription) url=\(self.redactedURLString(url))")
            return false
        }
    }

    private func isLikelySubtitlePayload(data: Data, contentType: String) -> Bool {
        if contentType.contains("text/html") || contentType.contains("application/json") {
            return false
        }

        if contentType.contains("text/plain") ||
            contentType.contains("application/x-subrip") ||
            contentType.contains("text/vtt") ||
            contentType.contains("application/octet-stream") {
            return true
        }

        guard let text = String(data: data.prefix(2048), encoding: .utf8)?.lowercased() else {
            return data.count > 32
        }

        if text.contains("<html") || text.contains("<!doctype") || text.contains("\"error\"") {
            return false
        }

        if text.contains("-->") || text.contains("webvtt") || text.contains("{\\an") {
            return true
        }

        return data.count > 64
    }

    private func subtitleFileExtension(for codec: String?) -> String {
        switch codec?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "subrip", "srt":
            return "srt"
        case "ass", "ssa":
            return "ass"
        case "webvtt", "vtt":
            return "vtt"
        case "ttml", "dfxp":
            return "ttml"
        default:
            return "srt"
        }
    }

    private func applyPreferredSubtitleTrack(
        stream: StreamInfo,
        entry: QueueEntry,
        externalTrackIdsByStreamIndex: [Int: Int32] = [:]
    ) {
        guard let selectedSubtitleStreamIndex = preferredSubtitleStreamIndex(stream: stream, entry: entry) else { return }
        let targetStream = stream.subtitleStreams.first(where: { $0.index == selectedSubtitleStreamIndex })
        subtitleDebug(
            "subtitle_apply_preferred selected_stream_index=\(selectedSubtitleStreamIndex) target=\(self.subtitleStreamDebugSummary(targetStream)) local_map=\(externalTrackIdsByStreamIndex.count) global_map=\(self.externalSubtitleTrackIdsByStreamIndex.count) tracks=\(self.subtitleTrackDebugSummary(self.player.subtitleTracks))"
        )

        if let externalTrackId = externalTrackIdsByStreamIndex[selectedSubtitleStreamIndex]
            ?? self.externalSubtitleTrackIdsByStreamIndex[selectedSubtitleStreamIndex] {
            subtitleDebug("subtitle_apply_preferred path=external_map track_id=\(externalTrackId)")
            player.setSubtitleTrack(externalTrackId)
            return
        }

        if let targetStream, targetStream.isExternal {
            if let positionalExternalTrackId = externalSubtitleTrackId(for: selectedSubtitleStreamIndex, in: stream) {
                externalSubtitleTrackIdsByStreamIndex[selectedSubtitleStreamIndex] = positionalExternalTrackId
                subtitleDebug("subtitle_apply_preferred path=external_positional track_id=\(positionalExternalTrackId)")
                player.setSubtitleTrack(positionalExternalTrackId)
                return
            }

            let externalCandidateIds = externalSubtitleCandidateTrackIds(stream: stream)
            if let matchedExternalTrackId = matchSubtitleTrackId(targetStream, candidateTrackIds: externalCandidateIds) {
                externalSubtitleTrackIdsByStreamIndex[selectedSubtitleStreamIndex] = matchedExternalTrackId
                subtitleDebug("subtitle_apply_preferred path=external_match track_id=\(matchedExternalTrackId) candidates=\(externalCandidateIds.count)")
                player.setSubtitleTrack(matchedExternalTrackId)
                return
            }

            logger.warning("subtitle_apply_preferred path=external_async_reload stream_index=\(selectedSubtitleStreamIndex)")
            let sessionToken = playbackSessionToken
            Task { [weak self] in
                guard let self else { return }
                guard self.playbackSessionToken == sessionToken else { return }
                guard self.userSubtitleOverrideSessionToken != sessionToken else { return }
                await self.loadAndSelectExternalSubtitle(targetStream, sessionToken: sessionToken, entry: entry)
            }
            return
        }

        if let embeddedTrackId = embeddedSubtitleTrackId(for: selectedSubtitleStreamIndex, in: stream) {
            subtitleDebug("subtitle_apply_preferred path=embedded_positional track_id=\(embeddedTrackId)")
            player.setSubtitleTrack(embeddedTrackId)
            return
        }

        guard let targetStream,
                            let matchedTrackId = matchSubtitleTrackId(
                                targetStream,
                                candidateTrackIds: embeddedSubtitleCandidateTrackIds(stream: stream)
                            )
        else {
            logger.warning("subtitle_apply_preferred no_match selected_stream_index=\(selectedSubtitleStreamIndex)")
            return
        }

        subtitleDebug("subtitle_apply_preferred path=embedded_match track_id=\(matchedTrackId)")
        player.setSubtitleTrack(matchedTrackId)
    }

    private func preferredSubtitleStreamIndex(stream: StreamInfo, entry: QueueEntry) -> Int? {
        if let selected = entry.subtitleStreamIndex {
            return selected >= 0 ? selected : nil
        }
        return stream.defaultSubtitleStreamIndex
    }

    private func matchSubtitleTrackId(_ stream: ServerMediaStream, candidateTrackIds: Set<Int32>? = nil) -> Int32? {
        let expectedLanguage = normalizedSubtitleToken(stream.language)
        let expectedDisplayTitle = normalizedSubtitleToken(stream.displayTitle)
        let expectedCodec = normalizedSubtitleToken(stream.codec)
        let expectedPathComponent = normalizedSubtitlePathComponent(stream.path ?? stream.deliveryUrl)

        var bestMatch: (trackId: Int32, score: Int)?

        for track in player.subtitleTracks {
            if let candidateTrackIds, !candidateTrackIds.contains(track.id) {
                continue
            }

            let normalizedTrackLanguage = normalizedSubtitleToken(track.language)
            let normalizedTrackTitle = normalizedSubtitleToken(track.title)
            let normalizedTrackName = normalizedSubtitleToken(track.name)
            let normalizedTrackCodec = normalizedSubtitleToken(track.codec)

            var score = 0

            if let expectedLanguage,
               let normalizedTrackLanguage,
               normalizedTrackLanguage == expectedLanguage {
                score += 6
            }

            if let expectedCodec,
               let normalizedTrackCodec,
               normalizedTrackCodec == expectedCodec {
                score += 3
            }

            if let expectedDisplayTitle {
                if normalizedTrackTitle == expectedDisplayTitle {
                    score += 8
                } else if normalizedTrackName == expectedDisplayTitle {
                    score += 6
                } else if normalizedTrackTitle?.contains(expectedDisplayTitle) == true || expectedDisplayTitle.contains(normalizedTrackTitle ?? "") {
                    score += 4
                } else if normalizedTrackName?.contains(expectedDisplayTitle) == true || expectedDisplayTitle.contains(normalizedTrackName ?? "") {
                    score += 3
                }
            }

            if let expectedPathComponent {
                if normalizedTrackTitle == expectedPathComponent {
                    score += 9
                } else if normalizedTrackName == expectedPathComponent {
                    score += 7
                } else if normalizedTrackTitle?.contains(expectedPathComponent) == true || expectedPathComponent.contains(normalizedTrackTitle ?? "") {
                    score += 5
                } else if normalizedTrackName?.contains(expectedPathComponent) == true || expectedPathComponent.contains(normalizedTrackName ?? "") {
                    score += 4
                }
            }

            if stream.isForced && track.isForced {
                score += 2
            }
            if stream.isDefault && track.isDefault {
                score += 1
            }

            guard score > 0 else { continue }

            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (track.id, score)
            }
        }

        subtitleDebug(
            "subtitle_match stream=\(self.subtitleStreamDebugSummary(stream)) candidates=\(candidateTrackIds?.count ?? -1) tracks=\(self.player.subtitleTracks.count) best_track=\(bestMatch?.trackId ?? -1) best_score=\(bestMatch?.score ?? 0)"
        )

        return bestMatch?.trackId
    }

    private func embeddedSubtitleTrackId(for streamIndex: Int, in stream: StreamInfo) -> Int32? {
        let embeddedStreams = stream.subtitleStreams.filter { !$0.isExternal }
        guard let embeddedPosition = embeddedStreams.firstIndex(where: { $0.index == streamIndex }) else {
            return nil
        }
        return player.subtitleTracks[safe: embeddedPosition]?.id
    }

    private func externalSubtitleTrackId(for streamIndex: Int, in stream: StreamInfo) -> Int32? {
        let embeddedStreams = stream.subtitleStreams.filter { !$0.isExternal }
        let externalStreams = stream.subtitleStreams.filter { $0.isExternal }
        guard let externalPosition = externalStreams.firstIndex(where: { $0.index == streamIndex }) else {
            return nil
        }
        let trackPosition = embeddedStreams.count + externalPosition
        return player.subtitleTracks[safe: trackPosition]?.id
    }

    private func externalSubtitleCandidateTrackIds(stream: StreamInfo?) -> Set<Int32> {
        guard let stream else { return [] }
        let embeddedCount = stream.subtitleStreams.filter { !$0.isExternal }.count
        guard embeddedCount < player.subtitleTracks.count else { return [] }
        return Set(player.subtitleTracks.dropFirst(embeddedCount).map(\.id))
    }

    private func embeddedSubtitleCandidateTrackIds(stream: StreamInfo?) -> Set<Int32> {
        guard let stream else { return [] }
        let embeddedCount = stream.subtitleStreams.filter { !$0.isExternal }.count
        guard embeddedCount > 0 else { return [] }
        return Set(player.subtitleTracks.prefix(embeddedCount).map(\.id))
    }

    private func normalizedSubtitleToken(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let normalized = lowercased
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedSubtitlePathComponent(_ pathOrUrl: String?) -> String? {
        guard let pathOrUrl else { return nil }
        let trimmed = pathOrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           let decodedPath = components.percentEncodedPath.removingPercentEncoding,
           !decodedPath.isEmpty {
            let fileName = URL(fileURLWithPath: decodedPath).deletingPathExtension().lastPathComponent
            if !fileName.isEmpty {
                return normalizedSubtitleToken(fileName)
            }
        }

        let pathOnly = String(trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let rawFileName = pathOnly.split(separator: "/").last.map(String.init) ?? pathOnly
        let fileName = URL(fileURLWithPath: rawFileName).deletingPathExtension().lastPathComponent
        if !fileName.isEmpty {
            return normalizedSubtitleToken(fileName)
        }

        return normalizedSubtitleToken(trimmed)
    }

    private func subtitleStreamDebugSummary(_ stream: ServerMediaStream?) -> String {
        guard let stream else { return "nil" }
        let language = stream.language ?? "-"
        let title = stream.displayTitle ?? "-"
        let codec = stream.codec ?? "-"
        let hasDelivery = !(stream.deliveryUrl?.isEmpty ?? true)
        return "idx=\(stream.index),external=\(stream.isExternal),forced=\(stream.isForced),default=\(stream.isDefault),lang=\(language),title=\(title),codec=\(codec),hasDelivery=\(hasDelivery)"
    }

    private func subtitleTrackDebugSummary(_ tracks: [PlayerTrack]) -> String {
        guard !tracks.isEmpty else { return "[]" }
        return "[" + tracks.map { track in
            let language = track.language ?? "-"
            let title = redactedTrackText(track.title ?? "-")
            let name = redactedTrackText(track.name)
            return "\(track.id){name=\(name),lang=\(language),title=\(title),default=\(track.isDefault),forced=\(track.isForced)}"
        }.joined(separator: ";") + "]"
    }

    private func redactedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func redactedTrackText(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "api_key=[^&\\s]+", with: "api_key=<redacted>", options: .regularExpression)
        value = value.replacingOccurrences(of: "x-emby-token=[^&\\s]+", with: "x-emby-token=<redacted>", options: [.regularExpression, .caseInsensitive])
        return value
    }

    private func mapPlayerTrackToServerStreamIndex(
        playerTrackId: Int32,
        playerTracks: [PlayerTrack],
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

    private func saveSelectedAudioLanguage(trackIndex: Int32) {
        guard let stream = currentStreamInfo else { return }
        let tracks = player.audioTracks
        guard let trackPosition = tracks.firstIndex(where: { $0.id == trackIndex }) else { return }
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
            let tracks = player.audioTracks
            if matchIndex < tracks.count {
                let trackId = tracks[matchIndex].id
                player.setAudioTrack(trackId)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
