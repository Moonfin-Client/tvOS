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

    let player: VLCPlayerWrapper

    private let client: MediaServerClient
    private let preferences: UserPreferences
    private let streamResolver: StreamResolver
    private let subtitleConfigurator: SubtitleConfigurator
    private var reportingTask: Task<Void, Never>?
    private var stateObserver: AnyCancellable?

    var currentEntry: QueueEntry? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    var hasNext: Bool { currentIndex < queue.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 }

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
        player.configureSubtitleAppearance(subtitleConfigurator.mediaOptions())
        observePlayerState()
    }

    func play(items: [ServerItem], startIndex: Int = 0, startPosition: TimeInterval = 0) async {
        queue = items.enumerated().map { index, item in
            QueueEntry(
                id: item.id,
                item: item,
                mediaSourceId: item.mediaSources?.first?.id,
                startPositionTicks: index == startIndex ? Int64(startPosition * 10_000_000) : 0
            )
        }
        currentIndex = startIndex
        episodesPlayed = 0
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
    }

    func setSubtitleTrack(_ index: Int32) {
        player.setSubtitleTrack(index)
    }

    func addSubtitle(url: URL) {
        player.addSubtitle(url: url)
    }

    private func playCurrentEntry() async {
        guard let entry = currentEntry else { return }

        playbackState = .resolving

        let pref = preferences[UserPreferences.maxBitrate]
        let maxBitrate: Int64? = pref > 0 ? Int64(pref) : nil
        let subtitleIndex: Int? = subtitleConfigurator.shouldDefaultToNone ? -1 : nil

        do {
            let stream = try await streamResolver.resolve(
                item: entry.item,
                mediaSourceId: entry.mediaSourceId,
                maxBitrate: maxBitrate,
                audioStreamIndex: nil,
                subtitleStreamIndex: subtitleIndex,
                startTimeTicks: entry.startPositionTicks > 0 ? entry.startPositionTicks : nil
            )
            currentStreamInfo = stream
            await player.play(streamUrl: stream.url)
            if subtitleConfigurator.shouldDefaultToNone {
                player.disableSubtitles()
            }
            await reportPlaybackStart()
            startProgressReporting()
        } catch {
            playbackState = .error(error.localizedDescription)
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
        await reportPlaybackStopped(failed: failed)
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
}
