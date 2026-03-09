import Foundation
import UIKit
import AVFoundation
import TVVLCKit

enum VLCPlayerState: Equatable {
    case idle
    case opening
    case buffering(Float)
    case playing
    case paused
    case stopped
    case ended
    case error
}

struct VLCTrack: Identifiable, Equatable {
    let id: Int32
    let name: String
}

@MainActor
final class VLCPlayerWrapper: NSObject, ObservableObject {
    @Published private(set) var state: VLCPlayerState = .idle
    @Published private(set) var position: Float = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isSeekable: Bool = false
    @Published private(set) var audioTracks: [VLCTrack] = []
    @Published private(set) var subtitleTracks: [VLCTrack] = []
    @Published private(set) var currentAudioTrackIndex: Int32 = -1
    @Published private(set) var currentSubtitleTrackIndex: Int32 = -1
    @Published private(set) var rate: Float = 1.0

    private(set) var mediaPlayer: VLCMediaPlayer?
    private(set) var videoView: UIView?
    private var subtitleOptions: [String: Any] = [:]

    var isPlaying: Bool { state == .playing }

    func attachVideoView(_ view: UIView) {
        videoView = view
        mediaPlayer?.drawable = view
    }

    func configureSubtitleAppearance(_ options: [String: Any]) {
        subtitleOptions = options
    }

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {}
    }

    func play(url: URL) async {
        stop()
        configureAudioSession()

        let player = VLCMediaPlayer()
        player.delegate = self
        if let view = videoView {
            player.drawable = view
        }

        let media = VLCMedia(url: url)
        var mediaOpts: [String: Any] = [
            "network-caching": 3000,
            "clock-jitter": 0,
        ]
        mediaOpts.merge(subtitleOptions) { _, new in new }
        media.addOptions(mediaOpts)
        player.media = media
        mediaPlayer = player
        state = .opening

        player.play()
    }

    func play(streamUrl: String) async {
        guard let url = URL(string: streamUrl) else { return }
        await play(url: url)
    }

    func pause() {
        mediaPlayer?.pause()
    }

    func resume() {
        mediaPlayer?.play()
    }

    func stop() {
        mediaPlayer?.stop()
        mediaPlayer?.delegate = nil
        mediaPlayer?.drawable = nil
        mediaPlayer = nil
        state = .idle
        position = 0
        currentTime = 0
        duration = 0
        audioTracks = []
        subtitleTracks = []
    }

    func seek(to seconds: TimeInterval) {
        guard let player = mediaPlayer, isSeekable else { return }
        let ms = Int32(seconds * 1000)
        player.time = VLCTime(int: ms)
    }

    func seekToPosition(_ pos: Float) {
        guard let player = mediaPlayer, isSeekable else { return }
        player.position = max(0, min(1, pos))
    }

    func setRate(_ newRate: Float) {
        mediaPlayer?.rate = newRate
        rate = newRate
    }

    func setAudioTrack(_ trackIndex: Int32) {
        mediaPlayer?.currentAudioTrackIndex = trackIndex
        currentAudioTrackIndex = trackIndex
    }

    func setSubtitleTrack(_ trackIndex: Int32) {
        mediaPlayer?.currentVideoSubTitleIndex = trackIndex
        currentSubtitleTrackIndex = trackIndex
    }

    func disableSubtitles() {
        setSubtitleTrack(-1)
    }

    func addSubtitle(url: URL) {
        mediaPlayer?.addPlaybackSlave(url, type: .subtitle, enforce: true)
    }

    func setSubtitleDelay(_ interval: TimeInterval) {
        let microseconds = Int(interval * 1_000_000)
        mediaPlayer?.currentVideoSubTitleDelay = microseconds
    }

    func setAudioDelay(_ interval: TimeInterval) {
        let microseconds = Int(interval * 1_000_000)
        mediaPlayer?.currentAudioPlaybackDelay = microseconds
    }

    private func refreshTracks() {
        guard let player = mediaPlayer else { return }

        if let names = player.audioTrackNames as? [String],
           let indexes = player.audioTrackIndexes as? [NSNumber] {
            audioTracks = zip(indexes, names).map { VLCTrack(id: $0.0.int32Value, name: $0.1) }
        }

        if let names = player.videoSubTitlesNames as? [String],
           let indexes = player.videoSubTitlesIndexes as? [NSNumber] {
            subtitleTracks = zip(indexes, names).map { VLCTrack(id: $0.0.int32Value, name: $0.1) }
        }

        currentAudioTrackIndex = player.currentAudioTrackIndex
        currentSubtitleTrackIndex = player.currentVideoSubTitleIndex
    }

    private func updateTime() {
        guard let player = mediaPlayer else { return }
        let currentMs = player.time?.intValue ?? 0
        let totalMs = abs(player.media?.length.intValue ?? 0)
        currentTime = TimeInterval(currentMs) / 1000.0
        duration = TimeInterval(totalMs) / 1000.0
        position = player.position
    }
}

extension VLCPlayerWrapper: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor in
            guard let player = mediaPlayer else { return }
            let vlcState = player.state

            let newState: VLCPlayerState
            switch vlcState {
            case .opening:
                newState = .opening
            case .buffering:
                newState = .buffering(0)
            case .playing:
                newState = .playing
                refreshTracks()
            case .paused:
                newState = .paused
            case .stopped:
                newState = .stopped
            case .ended:
                newState = .ended
            case .error:
                newState = .error
            case .esAdded:
                refreshTracks()
                return
            @unknown default:
                return
            }

            isSeekable = player.isSeekable
            state = newState
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor in
            updateTime()
        }
    }
}
