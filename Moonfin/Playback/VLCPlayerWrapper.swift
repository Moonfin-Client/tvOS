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

enum ZoomMode: String, StringRepresentableEnum, CaseIterable {
    case fit = "Fit"
    case autoCrop = "Auto Crop"
    case stretch = "Stretch"

    var displayName: String { rawValue }

    var next: ZoomMode {
        let all = ZoomMode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }

    var iconName: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .autoCrop: return "arrow.up.left.and.arrow.down.right"
        case .stretch: return "arrow.left.and.right"
        }
    }
}

struct VLCTrack: Identifiable, Equatable {
    let id: Int32
    let name: String
    let language: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool
    let codec: String?

    init(
        id: Int32,
        name: String,
        language: String? = nil,
        title: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        codec: String? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.title = title
        self.isDefault = isDefault
        self.isForced = isForced
        self.codec = codec
    }
}

@MainActor
class VLCPlayerWrapper: NSObject, ObservableObject {
    @Published var state: VLCPlayerState = .idle
    @Published var position: Float = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var bufferProgress: Float = 0
    @Published private(set) var isSeekable: Bool = false
    @Published var audioTracks: [VLCTrack] = []
    @Published var subtitleTracks: [VLCTrack] = []
    @Published var currentAudioTrackIndex: Int32 = -1
    @Published var currentSubtitleTrackIndex: Int32 = -1
    @Published var rate: Float = 1.0
    @Published internal(set) var zoomMode: ZoomMode = .fit

    private(set) var mediaPlayer: VLCMediaPlayer?
    private(set) var videoView: UIView?
    private var subtitleOptions: [String: Any] = [:]
    private var networkOptions: [String: Any] = [:]
    private var lastTimeUpdate: CFAbsoluteTime = 0
    private let timeUpdateInterval: CFAbsoluteTime = 0.25

    private nonisolated(unsafe) var timeUpdateScheduled = false
    private var tracksNeedRefresh = true
    private var audioSessionActive = false
    private var pendingSeekPosition: TimeInterval?
    private var pendingSeekAttempts = 0
    private let maxPendingSeekAttempts = 40

    private(set) var playbackBackendIdentifier: String = "tvvlckit"
    private(set) var playbackFallbackReason: String?

    var isPlaying: Bool { state == .playing }

    func updatePlaybackBackend(identifier: String, fallbackReason: String?) {
        playbackBackendIdentifier = identifier
        playbackFallbackReason = fallbackReason
    }

    func configurePreferredBackendForNextPlayback(_ backend: PlaybackBackendDirective, fallbackReason: String?) {
        updatePlaybackBackend(identifier: backend.rawValue, fallbackReason: fallbackReason)
    }

    func configureDynamicRangeIntent(contentRange: VideoDynamicRange, sinkIsHdrCapable: Bool) {}

    func dynamicRangeTelemetrySnapshot() -> [String: String] {
        [:]
    }

    func attachVideoView(_ view: UIView) {
        videoView = view
        mediaPlayer?.drawable = view
    }

    func configureSubtitleAppearance(_ options: [String: Any]) {
        subtitleOptions = options
    }

    func configureNetworkOptions(_ options: [String: Any]) {
        networkOptions = options
    }

    func configureAudioSession() {
        guard !audioSessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            audioSessionActive = true
        } catch {}
    }

    func play(url: URL, startPosition: TimeInterval = 0) async {
        stop()
        configureAudioSession()

        let player = VLCMediaPlayer()
        player.delegate = self
        if let view = videoView {
            player.drawable = view
        }

        let media = VLCMedia(url: url)
        var allOptions = subtitleOptions
        for (key, value) in networkOptions {
            allOptions[key] = value
        }
        if !allOptions.isEmpty {
            media.addOptions(allOptions)
        }
        player.media = media
        mediaPlayer = player
        tracksNeedRefresh = true
        state = .opening
        pendingSeekPosition = startPosition > 0 ? startPosition : nil
        pendingSeekAttempts = 0

        player.play()
    }

    func play(streamUrl: String, startPosition: TimeInterval = 0) async {
        guard let url = URL(string: streamUrl) else {
            return
        }
        await play(url: url, startPosition: startPosition)
    }

    func pause() {
        guard let player = mediaPlayer else { return }
        guard state == .playing || player.isPlaying else { return }
        player.pause()
        state = .paused
    }

    func resume() {
        guard let player = mediaPlayer else { return }
        guard !player.isPlaying else { return }
        player.play()
        state = .playing
    }

    func stop() {
        mediaPlayer?.drawable = nil
        mediaPlayer?.delegate = nil
        mediaPlayer?.stop()
        mediaPlayer = nil
        state = .idle
        position = 0
        currentTime = 0
        duration = 0
        bufferProgress = 0
        audioTracks = []
        subtitleTracks = []
        tracksNeedRefresh = true
        audioSessionActive = false
        pendingSeekPosition = nil
        pendingSeekAttempts = 0
    }

    func seek(to seconds: TimeInterval) {
        guard let player = mediaPlayer, isSeekable else { return }
        let ms = Int32(seconds * 1000)
        player.time = VLCTime(int: ms)
    }

    func seekBy(_ delta: TimeInterval) {
        seek(to: max(currentTime + delta, 0))
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

    func setZoomMode(_ mode: ZoomMode) {
        guard let player = mediaPlayer else { return }
        switch mode {
        case .fit:
            player.videoAspectRatio = nil
            player.videoCropGeometry = nil
        case .autoCrop:
            player.videoAspectRatio = nil
            player.videoCropGeometry = UnsafeMutablePointer<CChar>(mutating: ("16:9" as NSString).utf8String)
        case .stretch:
            player.videoAspectRatio = UnsafeMutablePointer<CChar>(mutating: ("16:9" as NSString).utf8String)
            player.videoCropGeometry = nil
        }
        zoomMode = mode
    }

    func cycleZoomMode() {
        setZoomMode(zoomMode.next)
    }

    func snapshotPlaybackPosition() -> TimeInterval {
        guard let player = mediaPlayer else { return currentTime }
        let preciseSeconds = TimeInterval(player.time.intValue) / 1000.0
        if preciseSeconds.isFinite, preciseSeconds >= 0 {
            return preciseSeconds
        }
        return currentTime
    }

    private func refreshTracks() {
        guard tracksNeedRefresh, let player = mediaPlayer else { return }

        let newAudio: [VLCTrack]
        if let names = player.audioTrackNames as? [String],
           let indexes = player.audioTrackIndexes as? [NSNumber] {
            newAudio = zip(indexes, names)
                .filter { $0.0.int32Value != -1 }
                .map { VLCTrack(id: $0.0.int32Value, name: $0.1) }
        } else {
            newAudio = []
        }

        let newSubs: [VLCTrack]
        if let names = player.videoSubTitlesNames as? [String],
           let indexes = player.videoSubTitlesIndexes as? [NSNumber] {
            newSubs = zip(indexes, names)
                .filter { $0.0.int32Value != -1 }
                .map { VLCTrack(id: $0.0.int32Value, name: $0.1) }
        } else {
            newSubs = []
        }

        if newAudio != audioTracks { audioTracks = newAudio }
        if newSubs != subtitleTracks { subtitleTracks = newSubs }

        let newAudioIdx = player.currentAudioTrackIndex
        let newSubIdx = player.currentVideoSubTitleIndex
        if newAudioIdx != currentAudioTrackIndex { currentAudioTrackIndex = newAudioIdx }
        if newSubIdx != currentSubtitleTrackIndex { currentSubtitleTrackIndex = newSubIdx }

        if !newAudio.isEmpty { tracksNeedRefresh = false }
    }

    private func updateTime(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || (now - lastTimeUpdate) >= timeUpdateInterval else { return }
        lastTimeUpdate = now

        guard let player = mediaPlayer else { return }

        if player.isPlaying && state != .playing {
            state = .playing
            tracksNeedRefresh = true
            refreshTracks()
        }

        applyPendingSeekIfReady(player)

        let newTime = TimeInterval(player.time.intValue) / 1000.0
        let newDuration = TimeInterval(abs(player.media?.length.intValue ?? 0)) / 1000.0
        let newPosition = player.position

        if abs(newTime - currentTime) > 0.01 { currentTime = newTime }
        if abs(newDuration - duration) > 0.1 { duration = newDuration }
        if abs(newPosition - position) > 0.0001 { position = newPosition }
    }

    private func applyPendingSeekIfReady(_ player: VLCMediaPlayer) {
        guard let seekPos = pendingSeekPosition else { return }
        guard player.state != .opening else { return }

        let ms = Int32(seekPos * 1000)
        let currentMs = player.time.intValue

        if abs(currentMs - ms) <= 1500 {
            pendingSeekPosition = nil
            pendingSeekAttempts = 0
            return
        }

        guard pendingSeekAttempts < maxPendingSeekAttempts else {
            pendingSeekPosition = nil
            pendingSeekAttempts = 0
            return
        }

        pendingSeekAttempts += 1
        player.time = VLCTime(int: ms)
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
                let bufferPct = player.position
                let pct = max(0, min(1, bufferPct))
                if abs(pct - bufferProgress) > 0.01 { bufferProgress = pct }
                newState = .buffering(pct)
            case .playing:
                bufferProgress = 1.0
                newState = .playing
                tracksNeedRefresh = true
                refreshTracks()
                applyPendingSeekIfReady(player)
            case .paused:
                newState = .paused
            case .stopped:
                newState = .stopped
            case .ended:
                newState = .ended
            case .error:
                newState = .error
            case .esAdded:
                tracksNeedRefresh = true
                refreshTracks()
                return
            @unknown default:
                return
            }

            isSeekable = player.isSeekable
            state = newState
            updateTime(force: true)
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard !timeUpdateScheduled else { return }
        timeUpdateScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timeUpdateScheduled = false
            self.updateTime()
        }
    }
}
