import Foundation
import Combine

@MainActor
final class AudioNowPlayingViewModel: ObservableObject {
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var isLoadingLyrics = false
    @Published var showQueue = false
    @Published var showLyrics = false

    let audioManager: AudioManager
    private let client: MediaServerClient
    private var lyricsTask: Task<Void, Never>?
    private var trackObserver: AnyCancellable?
    private var playerObserver: AnyCancellable?

    var player: VLCPlayerWrapper { audioManager.player }
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

    var positionText: String { formatTime(player.currentTime) }

    var remainingText: String {
        let remaining = player.duration - player.currentTime
        guard remaining > 0 else { return "0:00" }
        return "-\(formatTime(remaining))"
    }

    var hasLyrics: Bool { !lyrics.isEmpty }

    var supportsLyrics: Bool {
        client.serverType.featureSupport.isSupported(.lyrics)
    }

    init(audioManager: AudioManager, client: MediaServerClient) {
        self.audioManager = audioManager
        self.client = client
        observeTrackChanges()
        observePlayerUpdates()
        loadLyricsForCurrentTrack()
    }

    func toggleQueue() {
        showQueue.toggle()
        if showQueue {
            showLyrics = false
        }
    }

    func toggleLyrics() {
        guard hasLyrics else { return }
        showLyrics.toggle()
        if showLyrics {
            showQueue = false
        }
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

    func loadLyricsForCurrentTrack() {
        lyricsTask?.cancel()
        lyrics = []

        guard let item = currentItem,
              item.hasLyrics == true,
              supportsLyrics else { return }

        isLoadingLyrics = true
        lyricsTask = Task {
            do {
                let result = try await client.lyricsApi.getLyrics(itemId: item.id)
                guard !Task.isCancelled else { return }
                lyrics = result.lyrics
            } catch {
                lyrics = []
            }
            isLoadingLyrics = false
        }
    }

    private func observeTrackChanges() {
        trackObserver = audioManager.playbackManager.$currentIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.showLyrics = false
                self.objectWillChange.send()
                self.loadLyricsForCurrentTrack()
            }
    }

    private func observePlayerUpdates() {
        playerObserver = audioManager.player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
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
