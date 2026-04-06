import Foundation
import Combine

@MainActor
final class AudioNowPlayingViewModel: ObservableObject {
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var isFavorite = false
    @Published var isScrubbing = false
    @Published var scrubPosition: Float = 0
    @Published var showQueue = false
    @Published var showLyrics = false

    let audioManager: AudioManager
    private let client: MediaServerClient
    private var lyricsTask: Task<Void, Never>?
    private var lyricsItemId: String?
    private var scrubSeekTask: Task<Void, Never>?
    private var trackObserver: AnyCancellable?
    private var playerObserver: AnyCancellable?

    var player: MpvPlayerWrapper { audioManager.player }
    var playbackManager: PlaybackManager { audioManager.playbackManager }

    var currentItem: ServerItem? { audioManager.currentItem }

    var trackTitle: String { currentItem?.name ?? "" }

    var artistName: String {
        currentItem?.artists?.joined(separator: ", ")
            ?? currentItem?.albumArtist
            ?? ""
    }

    var albumName: String {
        currentItem?.album ?? ""
    }

    var albumArtUrl: URL? {
        guard let item = currentItem else { return nil }
        return audioManager.albumArtUrl(for: item)
    }

    var positionText: String { formatTime(displayCurrentTime) }

    var remainingText: String {
        let remaining = player.duration - displayCurrentTime
        guard remaining > 0 else { return "0:00" }
        return "-\(formatTime(remaining))"
    }

    var displayedProgress: Float {
        isScrubbing ? scrubPosition : player.position
    }

    var hasLyrics: Bool { !lyrics.isEmpty }

    var lyricsAvailable: Bool {
        hasLyrics || isLoadingLyrics || (currentItem?.hasLyrics == true && supportsLyrics)
    }

    var supportsLyrics: Bool {
        client.serverType.featureSupport.isSupported(.lyrics)
    }

    private var displayCurrentTime: TimeInterval {
        isScrubbing ? TimeInterval(scrubPosition) * player.duration : player.currentTime
    }

    init(audioManager: AudioManager, client: MediaServerClient) {
        self.audioManager = audioManager
        self.client = client
        syncCurrentItemState()
        observeTrackChanges()
        observePlayerUpdates()
        clearLyricsState()
        loadLyricsForCurrentTrack(autoShow: true)
    }

    func toggleQueue() {
        showQueue.toggle()
        if showQueue {
            showLyrics = false
        }
    }

    func toggleLyrics() {
        if showLyrics {
            showLyrics = false
            return
        }

        showQueue = false

        if hasLyrics {
            showLyrics = true
            return
        }

        guard currentItem?.hasLyrics == true, supportsLyrics else { return }
        showLyrics = true
        loadLyricsForCurrentTrack(autoShow: true)
    }

    func togglePlayPause() {
        if player.isPlaying {
            playbackManager.pause()
        } else {
            playbackManager.resume()
        }
    }

    func next() async {
        await audioManager.next()
    }

    func previous() async {
        await audioManager.previous()
    }

    func playQueueItem(at index: Int) async {
        await audioManager.playEntry(at: index)
    }

    func toggleFavorite() {
        isFavorite.toggle()
    }

    func beginScrub() {
        isScrubbing = true
        scrubPosition = player.position
    }

    func updateScrub(by delta: Float) {
        scrubPosition = max(0, min(1, scrubPosition + delta))
        debouncedSeek()
    }

    func commitScrub() {
        guard isScrubbing else { return }
        scrubSeekTask?.cancel()
        let target = TimeInterval(scrubPosition) * player.duration
        playbackManager.seek(to: target)
        isScrubbing = false
    }

    func cancelScrub() {
        scrubSeekTask?.cancel()
        isScrubbing = false
    }

    func loadLyricsForCurrentTrack(autoShow: Bool = false) {
        guard let item = currentItem,
              item.hasLyrics == true,
              supportsLyrics else {
            if autoShow { showLyrics = false }
            clearLyricsState()
            return
        }

        if item.id == lyricsItemId, (hasLyrics || isLoadingLyrics) { return }
        lyricsItemId = item.id

        lyricsTask?.cancel()
        lyrics = []
        isLoadingLyrics = false

        isLoadingLyrics = true
        lyricsTask = Task {
            do {
                let result = try await client.lyricsApi.getLyrics(itemId: item.id)
                guard !Task.isCancelled else { return }
                lyrics = result.lyrics
                if autoShow { showLyrics = !result.lyrics.isEmpty }
            } catch {
                lyrics = []
                if autoShow { showLyrics = false }
            }
            isLoadingLyrics = false
        }
    }

    private func observeTrackChanges() {
        trackObserver = audioManager.playbackManager.$currentIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cancelScrub()
                self.syncCurrentItemState()
                self.clearLyricsState()
                self.loadLyricsForCurrentTrack(autoShow: true)
                self.objectWillChange.send()
            }
    }

    private func observePlayerUpdates() {
        playerObserver = audioManager.player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private func debouncedSeek() {
        scrubSeekTask?.cancel()
        scrubSeekTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, isScrubbing else { return }
            let target = TimeInterval(scrubPosition) * player.duration
            playbackManager.seek(to: target)
        }
    }

    private func syncCurrentItemState() {
        isFavorite = currentItem?.userData?.isFavorite ?? false
    }

    private func clearLyricsState() {
        lyricsTask?.cancel()
        lyricsItemId = nil
        isLoadingLyrics = false
        lyrics = []
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
