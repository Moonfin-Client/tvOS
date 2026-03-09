import SwiftUI

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var overlayVisible = false
    @Published var trackSelectionVisible = false
    @Published var trackSelectionTab: TrackSelectionTab = .audio
    @Published var subtitleDelay: TimeInterval = 0

    let playbackManager: PlaybackManager

    private var hideTask: Task<Void, Never>?
    private let overlayTimeout: TimeInterval = 5

    var player: VLCPlayerWrapper { playbackManager.player }

    var title: String {
        guard let item = playbackManager.currentEntry?.item else { return "" }
        if let series = item.seriesName {
            var episodeLabel = series
            if let s = item.parentIndexNumber { episodeLabel += " — S\(s)" }
            if let e = item.indexNumber { episodeLabel += "E\(e)" }
            return episodeLabel
        }
        return item.name
    }

    var subtitle: String {
        guard let item = playbackManager.currentEntry?.item else { return "" }
        if item.seriesName != nil { return item.name }
        return ""
    }

    var nextQueueItem: ServerItem? {
        playbackManager.nextEntry?.item
    }

    var nextItemImageUrl: String? {
        guard let item = nextQueueItem else { return nil }
        return playbackManager.imageUrl(for: item, type: .backdrop)
    }

    var positionText: String {
        "\(formatTime(player.currentTime)) / \(formatTime(player.duration))"
    }

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
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
            if !trackSelectionVisible {
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

    func seekForward(seconds: TimeInterval = 15) {
        let target = min(player.currentTime + seconds, player.duration)
        playbackManager.seek(to: target)
        showOverlay()
    }

    func seekBackward(seconds: TimeInterval = 15) {
        let target = max(player.currentTime - seconds, 0)
        playbackManager.seek(to: target)
        showOverlay()
    }

    func showTrackSelection(tab: TrackSelectionTab = .audio) {
        trackSelectionTab = tab
        trackSelectionVisible = true
        hideTask?.cancel()
    }

    func hideTrackSelection() {
        trackSelectionVisible = false
        resetHideTimer()
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
