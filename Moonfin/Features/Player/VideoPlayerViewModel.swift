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
    @Published var playbackInfoVisible = false
    @Published var subtitleDelay: TimeInterval = 0
    @Published var isScrubbing = false
    @Published var scrubPosition: Float = 0

    let playbackManager: PlaybackManager
    let isLiveTV: Bool

    private var hideTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let overlayTimeout: TimeInterval = 5
    private let endTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    let skipBackSeconds: TimeInterval = 10
    let skipForwardSeconds: TimeInterval = 30

    private var _cachedTitle: String = ""
    private var _cachedSubtitle: String = ""
    private var _cachedChapters: [ServerChapter] = []
    private var _cachedCast: [ServerPerson] = []
    private var _cachedEntryId: String?

    var player: VLCPlayerWrapper { playbackManager.player }

    var title: String { ensureItemCache(); return _cachedTitle }
    var subtitle: String { ensureItemCache(); return _cachedSubtitle }
    var chapters: [ServerChapter] { ensureItemCache(); return _cachedChapters }
    var castMembers: [ServerPerson] { ensureItemCache(); return _cachedCast }
    var hasChapters: Bool { chapters.count > 1 }
    var hasCast: Bool { !castMembers.isEmpty }

    var nextQueueItem: ServerItem? {
        playbackManager.nextEntry?.item
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

    init(playbackManager: PlaybackManager, isLiveTV: Bool = false) {
        self.playbackManager = playbackManager
        self.isLiveTV = isLiveTV

        playbackManager.player.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        playbackManager.player.$audioTracks
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        playbackManager.player.$subtitleTracks
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        playbackManager.player.$currentAudioTrackIndex
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        playbackManager.player.$currentSubtitleTrackIndex
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        playbackManager.player.$rate
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

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
            }
            .store(in: &cancellables)

        playbackManager.player.$zoomMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func ensureItemCache() {
        let entryId = playbackManager.currentEntry?.id
        guard entryId != _cachedEntryId else { return }
        _cachedEntryId = entryId

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

        let people = item.people ?? []
        _cachedCast = people.filter { $0.type == .actor || $0.type == .guestStar }
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
            if !trackSelectionVisible && !chapterSelectionVisible && !castListVisible && !playbackInfoVisible && !isScrubbing {
                overlayVisible = false
            }
        }
    }

    func togglePlayPause() {
        if player.isPlaying {
            playbackManager.pause()
        } else {
            playbackManager.resume()
        }
        resetHideTimer()
    }

    func seekForward() {
        let target = min(player.currentTime + skipForwardSeconds, player.duration)
        playbackManager.seek(to: target)
        showOverlay()
    }

    func seekBackward() {
        let target = max(player.currentTime - skipBackSeconds, 0)
        playbackManager.seek(to: target)
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

    private func debouncedSeek() {
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
        playbackManager.seek(to: target)
        isScrubbing = false
        resetHideTimer()
    }

    func cancelScrub() {
        scrubSeekTask?.cancel()
        isScrubbing = false
        resetHideTimer()
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
        playbackManager.seek(to: position)
        hideChapterSelection()
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
        overlayVisible = false
        castListVisible = true
        hideTask?.cancel()
    }

    func hideCastList() {
        castListVisible = false
        overlayVisible = true
        resetHideTimer()
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
