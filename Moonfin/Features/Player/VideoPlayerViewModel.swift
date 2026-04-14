import SwiftUI
import Combine

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var overlayVisible = false
    @Published var audioSelectionVisible = false
    @Published var subtitleSelectionVisible = false
    @Published var speedSelectionVisible = false
    @Published var chapterSelectionVisible = false
    @Published var castListVisible = false
    @Published var channelListVisible = false
    @Published var playbackInfoVisible = false
    @Published var subtitleDownloadVisible = false
    @Published var subtitleDelay: TimeInterval = 0
    @Published var isScrubbing = false
    @Published var scrubPosition: Float = 0
    @Published private(set) var liveTvChannels: [ServerItem] = []
    @Published private(set) var isLoadingLiveTvChannels = false
    @Published private(set) var canJumpToLive = false

    let playbackManager: PlaybackManager
    let isLiveTV: Bool
    weak var syncPlayManager: SyncPlayManager?

    private var hideTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var castPrefetchTask: Task<Void, Never>?
    private var livePauseThresholdTask: Task<Void, Never>?
    private var livePauseStartedAt: Date?
    private var lastExitCommandHandledAt: CFAbsoluteTime = 0
    private var cancellables = Set<AnyCancellable>()
    private let overlayTimeout: TimeInterval = 5
    private let endTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    let skipBackSeconds: TimeInterval = 10

    var skipForwardSeconds: TimeInterval {
        playbackManager.skipForwardSeconds
    }

    private var _cachedTitle: String = ""
    private var _cachedSubtitle: String = ""
    private var _cachedChapters: [ServerChapter] = []
    private var _cachedCast: [ServerPerson] = []
    private var _cachedEntryId: String?
    private var _castResolvedItemId: String?

    var canDownloadSubtitles: Bool {
        guard let item = playbackManager.currentEntry?.item else { return false }
        return playbackManager.serverType == .jellyfin
            && !(item.mediaSources ?? []).isEmpty
    }

    var player: MpvPlayerWrapper { playbackManager.player }

    var title: String { ensureItemCache(); return _cachedTitle }
    var subtitle: String { ensureItemCache(); return _cachedSubtitle }
    var chapters: [ServerChapter] { ensureItemCache(); return _cachedChapters }
    var castMembers: [ServerPerson] { ensureItemCache(); return _cachedCast }
    var hasChapters: Bool { chapters.count > 1 }
    var hasCast: Bool { playbackManager.currentEntry?.item != nil }

    var nextQueueItem: ServerItem? {
        playbackManager.nextEntry?.item
    }

    var syncPlayActive: Bool {
        syncPlayManager?.state.enabled == true
    }

    var nextItemImageUrl: String? {
        guard let item = nextQueueItem else { return nil }
        return playbackManager.imageUrl(for: item, type: .backdrop)
    }

    var positionText: String {
        let current = isScrubbing ? TimeInterval(scrubPosition) * player.duration : player.currentTime
        return "\(formatTime(current)) / \(formatTime(player.duration))"
    }

    var endTimeText: String {
        let remaining = player.duration - player.currentTime
        guard remaining.isFinite && remaining > 0 else { return "" }
        let endDate = Date().addingTimeInterval(remaining)
        return "Ends at \(endTimeFormatter.string(from: endDate))"
    }

    init(
        playbackManager: PlaybackManager,
        isLiveTV: Bool = false,
        syncPlayManager: SyncPlayManager? = nil
    ) {
        self.syncPlayManager = syncPlayManager
        self.playbackManager = playbackManager
        self.isLiveTV = isLiveTV
        syncPlayManager?.attachPlaybackStateObserverIfNeeded()

        bindObjectWillChange(playbackManager.player.$audioTracks.removeDuplicates())
        bindObjectWillChange(playbackManager.player.$subtitleTracks.removeDuplicates())
        bindObjectWillChange(playbackManager.player.$currentAudioTrackIndex.removeDuplicates())
        bindObjectWillChange(playbackManager.player.$currentSubtitleTrackIndex.removeDuplicates())
        bindObjectWillChange(playbackManager.player.$rate.removeDuplicates())

        playbackManager.player.$currentTime
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self, self.overlayVisible || self.isScrubbing else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        playbackManager.$currentIndex
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?._cachedEntryId = nil
                self?.objectWillChange.send()
                self?.prefetchCastForCurrentItem()
            }
            .store(in: &cancellables)

        bindObjectWillChange(playbackManager.player.$zoomMode.removeDuplicates())

        playbackManager.player.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.objectWillChange.send()
                self.handleLiveTvStateChange(state)
            }
            .store(in: &cancellables)

        prefetchCastForCurrentItem()
    }

    private func bindObjectWillChange<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func ensureItemCache() {
        let entryId = playbackManager.currentEntry?.id
        guard entryId != _cachedEntryId else { return }
        _cachedEntryId = entryId
        _castResolvedItemId = nil

        guard let item = playbackManager.currentEntry?.item else {
            _cachedTitle = ""
            _cachedSubtitle = ""
            _cachedChapters = []
            _cachedCast = []
            return
        }

        if let series = item.seriesName {
            var episodeLabel = series
            if let s = item.parentIndexNumber { episodeLabel += " — S\(s)" }
            if let e = item.indexNumber { episodeLabel += "E\(e)" }
            _cachedTitle = episodeLabel
        } else {
            _cachedTitle = item.name
        }

        _cachedSubtitle = item.seriesName != nil ? item.name : ""
        _cachedChapters = item.chapters ?? []

        _cachedCast = item.people ?? []
    }

    func showOverlay() {
        overlayVisible = true
        resetHideTimer()
    }

    func hideOverlay() {
        overlayVisible = false
        hideTask?.cancel()
        hideTask = nil
    }

    func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(overlayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if !trackSelectionVisible && !chapterSelectionVisible && !castListVisible
                && !channelListVisible && !playbackInfoVisible && !isScrubbing {
                overlayVisible = false
            }
        }
    }

    func togglePlayPause() {
        if let spm = syncPlayManager, spm.state.enabled {
            if player.isPlaying {
                spm.requestPause()
            } else {
                spm.requestUnpause()
            }
        } else {
            if player.isPlaying {
                playbackManager.pause()
            } else {
                playbackManager.resume()
            }
        }
        resetHideTimer()
    }

    func seekForward() {
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestSeek(to: player.currentTime + skipForwardSeconds)
        } else {
            playbackManager.seek(by: skipForwardSeconds)
        }
        showOverlay()
    }

    func seekBackward() {
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestSeek(to: max(0, player.currentTime - skipBackSeconds))
        } else {
            playbackManager.seek(by: -skipBackSeconds)
        }
        showOverlay()
    }

    func beginScrub() {
        isScrubbing = true
        scrubPosition = player.position
        hideTask?.cancel()
    }

    func updateScrub(by delta: Float) {
        scrubPosition = max(0, min(1, scrubPosition + delta))
        debouncedSeek()
    }

    func updateScrub(bySeconds deltaSeconds: TimeInterval) {
        let duration = max(player.duration, 1)
        let delta = Float(deltaSeconds / duration)
        updateScrub(by: delta)
    }

    private func debouncedSeek() {
        if syncPlayManager?.state.enabled == true { return }
        scrubSeekTask?.cancel()
        scrubSeekTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, isScrubbing else { return }
            let target = TimeInterval(scrubPosition) * player.duration
            playbackManager.seek(to: target)
        }
    }

    func commitScrub() {
        guard isScrubbing else { return }
        scrubSeekTask?.cancel()
        let target = TimeInterval(scrubPosition) * player.duration
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestSeek(to: target)
        } else {
            playbackManager.seek(to: target)
        }
        isScrubbing = false
        resetHideTimer()
    }

    func cancelScrub() {
        scrubSeekTask?.cancel()
        isScrubbing = false
        resetHideTimer()
    }

    func markExitCommandHandled() {
        lastExitCommandHandledAt = CFAbsoluteTimeGetCurrent()
    }

    func wasExitCommandHandledRecently(within interval: CFTimeInterval = 0.25) -> Bool {
        CFAbsoluteTimeGetCurrent() - lastExitCommandHandledAt < interval
    }

    func showTrackSelection(tab: TrackSelectionTab = .audio) {
        overlayVisible = false
        hideTask?.cancel()
        switch tab {
        case .audio:
            audioSelectionVisible = true
        case .subtitles:
            subtitleSelectionVisible = true
        case .speed:
            speedSelectionVisible = true
        }
    }

    func hideTrackSelection() {
        audioSelectionVisible = false
        subtitleSelectionVisible = false
        speedSelectionVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    var trackSelectionVisible: Bool {
        audioSelectionVisible || subtitleSelectionVisible || speedSelectionVisible
    }

    func showChapterSelection() {
        overlayVisible = false
        chapterSelectionVisible = true
        hideTask?.cancel()
    }

    func hideChapterSelection() {
        chapterSelectionVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    func seekToChapter(_ chapter: ServerChapter) {
        let position = TimeInterval(chapter.startPositionTicks) / 10_000_000
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestSeek(to: position)
        } else {
            playbackManager.seek(to: position)
        }
        hideChapterSelection()
    }

    func playNext() async {
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestNext()
        } else {
            await playbackManager.playNext()
        }
    }

    func playPrevious() async {
        if let spm = syncPlayManager, spm.state.enabled {
            spm.requestPrevious()
        } else {
            await playbackManager.playPrevious()
        }
    }

    func queueNextItemForSyncPlay() {
        guard let spm = syncPlayManager, spm.state.enabled,
              let itemId = nextQueueItem?.id else { return }
        spm.requestQueueItemIds([itemId], mode: .queueNext)
    }

    func currentChapterIndex() -> Int {
        let currentTicks = Int64(player.currentTime * 10_000_000)
        let chaps = chapters
        for i in stride(from: chaps.count - 1, through: 0, by: -1) {
            if currentTicks >= chaps[i].startPositionTicks {
                return i
            }
        }
        return 0
    }

    func showCastList() {
        hideTask?.cancel()
        castPrefetchTask?.cancel()
        Task {
            let hasCast = await ensureCastForCurrentItem()
            if hasCast {
                overlayVisible = false
                castListVisible = true
            } else {
                castListVisible = false
                overlayVisible = true
                resetHideTimer()
            }
        }
    }

    private func prefetchCastForCurrentItem() {
        castPrefetchTask?.cancel()
        guard playbackManager.currentEntry?.item != nil else { return }
        castPrefetchTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.ensureCastForCurrentItem()
        }
    }

    func hideCastList() {
        castListVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    var currentLiveTvChannelId: String? {
        guard isLiveTV else { return nil }
        return playbackManager.currentEntry?.item.id
    }

    func channelLogoUrl(for channel: ServerItem) -> String? {
        playbackManager.imageUrl(for: channel, type: .primary, maxWidth: 120, maxHeight: 120)
    }

    func currentProgramName(for channel: ServerItem) -> String {
        if let name = channel.currentProgram?.value.name, !name.isEmpty {
            return name
        }
        return Strings.liveTvNoProgramInformation
    }

    func showChannelList() {
        guard isLiveTV else { return }
        hideTask?.cancel()
        Task {
            await loadLiveTvChannelsIfNeeded()
            overlayVisible = false
            channelListVisible = true
        }
    }

    func hideChannelList() {
        channelListVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    func selectLiveTvChannel(_ channel: ServerItem) async {
        channelListVisible = false
        await restartLiveTvStream(with: channel)
    }

    private func loadLiveTvChannelsIfNeeded() async {
        guard isLiveTV else { return }
        guard !isLoadingLiveTvChannels else { return }
        if !liveTvChannels.isEmpty { return }
        isLoadingLiveTvChannels = true
        defer { isLoadingLiveTvChannels = false }
        if let channels = await playbackManager.fetchLiveTvChannels() {
            liveTvChannels = channels
        }
    }

    func jumpToLive() async {
        guard isLiveTV, let channel = playbackManager.currentEntry?.item else { return }
        await restartLiveTvStream(with: channel)
    }

    private func restartLiveTvStream(with channel: ServerItem) async {
        overlayVisible = true
        resetHideTimer()
        resetLivePauseTracking()
        // Stop the current stream cleanly before loading the new channel.
        // Calling play() without stopping first causes mpv to call loadFile()
        // on a still-active engine, which triggers a Vulkan context teardown
        // on the VO thread with an open CATransaction, freezing the stream.
        player.stopPlaybackOnly()
        await playbackManager.play(items: [channel])
    }

    private func handleLiveTvStateChange(_ state: PlayerState) {
        guard isLiveTV else { return }

        switch state {
        case .paused:
            if livePauseStartedAt == nil {
                livePauseStartedAt = Date()
            }

            if canJumpToLive {
                return
            }

            livePauseThresholdTask?.cancel()
            livePauseThresholdTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.isLiveTV, case .paused = self.player.state else { return }
                if let startedAt = self.livePauseStartedAt,
                   Date().timeIntervalSince(startedAt) >= 60 {
                    self.canJumpToLive = true
                }
            }
        case .playing, .buffering, .opening, .idle, .stopped, .ended, .error:
            resetLivePauseTracking()
        }
    }

    private func resetLivePauseTracking() {
        livePauseThresholdTask?.cancel()
        livePauseThresholdTask = nil
        livePauseStartedAt = nil
        canJumpToLive = false
    }

    private func ensureCastForCurrentItem() async -> Bool {
        ensureItemCache()
        guard let item = playbackManager.currentEntry?.item else {
            return false
        }

        if _castResolvedItemId == item.id {
            return !_cachedCast.isEmpty
        }

        if !_cachedCast.isEmpty {
            _castResolvedItemId = item.id
            return true
        }

        if let refreshed = await playbackManager.fetchItem(itemId: item.id),
           let people = refreshed.people,
           !people.isEmpty {
            _cachedCast = people
            _castResolvedItemId = item.id
            objectWillChange.send()
            return true
        }

        if item.type == .episode,
           let seriesId = item.seriesId,
           let series = await playbackManager.fetchItem(itemId: seriesId),
           let seriesPeople = series.people,
           !seriesPeople.isEmpty {
            _cachedCast = seriesPeople
            _castResolvedItemId = item.id
            objectWillChange.send()
            return true
        }

        _castResolvedItemId = item.id
        return false
    }

    func showPlaybackInfo() {
        overlayVisible = false
        playbackInfoVisible = true
        hideTask?.cancel()
    }

    func hidePlaybackInfo() {
        playbackInfoVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    func showSubtitleDownload() {
        overlayVisible = false
        hideTask?.cancel()
        subtitleSelectionVisible = false
        subtitleDownloadVisible = true
    }

    func hideSubtitleDownload() {
        subtitleDownloadVisible = false
        overlayVisible = true
        resetHideTimer()
    }

    func chapterImageUrl(for chapter: ServerChapter) -> String? {
        guard let item = playbackManager.currentEntry?.item,
              let tag = chapter.imageTag else { return nil }
        return playbackManager.chapterImageUrl(for: item, tag: tag, ticks: chapter.startPositionTicks)
    }

    func personImageUrl(for person: ServerPerson) -> String? {
        guard let personId = person.id, let tag = person.primaryImageTag else { return nil }
        return playbackManager.personImageUrl(personId: personId, tag: tag)
    }

    func cycleZoom() {
        player.cycleZoomMode()
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackManager.setRate(speed)
    }

    func adjustSubtitleDelay(by delta: TimeInterval) {
        subtitleDelay += delta
        player.setSubtitleDelay(subtitleDelay)
    }

    func resetSubtitleDelay() {
        subtitleDelay = 0
        player.setSubtitleDelay(0)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
