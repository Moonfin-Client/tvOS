import Foundation
import Combine

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

    init(
        player: VLCPlayerWrapper,
        client: MediaServerClient,
        preferences: UserPreferences
    ) {
        self.player = player
        self.client = client
        self.preferences = preferences
        self.streamResolver = ServerStreamResolver(client: client)
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
        subtitleStreamIndex: Int? = nil
    ) async {
        queue = items.enumerated().map { index, item in
            QueueEntry(
                id: item.id,
                item: item,
                mediaSourceId: item.mediaSources?.first?.id,
                startPositionTicks: index == startIndex ? Int64(startPosition * 10_000_000) : 0,
                audioStreamIndex: index == startIndex ? audioStreamIndex : nil,
                subtitleStreamIndex: index == startIndex ? subtitleStreamIndex : nil
            )
        }
        currentIndex = startIndex
        episodesPlayed = 0
        nextUpManager.resetForNewQueue()
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
    }

    func resume() {
        player.resume()
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
    }

    func setRate(_ rate: Float) {
        player.setRate(rate)
    }

    func setAudioTrack(_ index: Int32) {
        player.setAudioTrack(index)
        saveSelectedAudioLanguage(vlcTrackIndex: index)
    }

    func setSubtitleTrack(_ index: Int32) {
        player.setSubtitleTrack(index)
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

    private func playCurrentEntry() async {
        guard let entry = currentEntry else { return }

        playbackState = .resolving

        let audioIndex = entry.audioStreamIndex
        let subtitleIndex = entry.subtitleStreamIndex
            ?? (subtitleConfigurator.shouldDefaultToNone ? -1 : nil)

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

            let startSeconds: TimeInterval
            if entry.startPositionTicks > 0 && stream.playMethod != .transcode {
                startSeconds = TimeInterval(entry.startPositionTicks) / 10_000_000
            } else {
                startSeconds = 0
            }

            player.configureSubtitleAppearance(subtitleConfigurator.mediaOptions())
            await player.play(streamUrl: stream.url, startPosition: startSeconds)
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

        let subtitleIndex: Int? = subtitleConfigurator.shouldDefaultToNone ? -1 : nil
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
                    self.playbackState = .playing
                case .paused:
                    self.playbackState = .paused
                case .buffering(_):
                    self.playbackState = .buffering
                case .opening:
                    self.playbackState = .resolving
                case .ended:
                    self.playbackState = .idle
                    Task { await self.handlePlaybackEnded() }
                case .error:
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
        currentStreamInfo = nil
        player.stop()
    }

    private func reportPlaybackStart() async {
        guard let entry = currentEntry, let stream = currentStreamInfo else { return }
        let report = PlaybackStartReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: entry.startPositionTicks,
            audioStreamIndex: stream.defaultAudioStreamIndex,
            subtitleStreamIndex: stream.defaultSubtitleStreamIndex,
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
        let ticks = Int64(player.currentTime * 10_000_000)
        let report = PlaybackProgressReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: ticks,
            audioStreamIndex: stream.defaultAudioStreamIndex,
            subtitleStreamIndex: stream.defaultSubtitleStreamIndex,
            playMethod: stream.playMethod,
            isPaused: player.state == .paused,
            isMuted: false,
            volumeLevel: 100
        )
        try? await client.playbackApi.reportPlaybackProgress(info: report)
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
        let ticks = Int64(player.currentTime * 10_000_000)
        let report = PlaybackStopReport(
            itemId: entry.item.id,
            playSessionId: stream.playSessionId,
            mediaSourceId: stream.mediaSourceId,
            positionTicks: ticks,
            failed: failed
        )
        try? await client.playbackApi.reportPlaybackStopped(info: report)
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
