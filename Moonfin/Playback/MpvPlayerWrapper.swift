import Foundation
import UIKit
import AVFoundation
import Darwin
import os
#if canImport(Metal)
import Metal
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(MPVKit)
import MPVKit
#endif

@MainActor
final class MpvPlayerWrapper: VLCPlayerWrapper {
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "MpvPlayer")
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeBackground = false
    private var wasPlayingBeforeInterruption = false
    private var usesMpvBackend = false
    private var engine: MPVEngine?
    private let videoSurface = MPVVideoSurface()
    private var activeProfile: MPVRenderProfile = .metal
    private var renderUpdatePending = false
    private var renderDisplayLink: CADisplayLink?
    private var renderTickCounter: UInt = 0
    private var mpvSubtitleOptions: [String: Any] = [:]
    private var forcedBackendForNextPlayback: PlaybackBackendDirective?
    private var forcedFallbackReasonForNextPlayback: String?
    private var pendingMpvStartPosition: TimeInterval?
    private var pendingMpvSeekAttempts = 0
    private var pendingMpvSeekLastAttemptAt: CFAbsoluteTime = 0
    private let maxPendingMpvSeekAttempts = 60
    private let minPendingMpvSeekRetryInterval: CFAbsoluteTime = 0.2
    private var requestedContentRange: VideoDynamicRange = .unknown
    private var sinkIsHdrCapable = false
    private var activeToneMappingMode = "auto"
    private var lastRenderTimestamp: CFAbsoluteTime = 0
    private var lastWatchdogWarningAt: CFAbsoluteTime = 0
    private var renderWatchdogTimer: Timer?

    override init() {
        super.init()
        registerLifecycleObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            stopRenderScheduler()
            resetEngine()
            videoSurface.teardown()
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func attachVideoView(_ view: UIView) {
        super.attachVideoView(view)
        videoSurface.attach(to: view)
    }

    override func play(url: URL, startPosition: TimeInterval = 0) async {
        if forcedBackendForNextPlayback == .tvvlcKit {
            usesMpvBackend = false
            updatePlaybackBackend(identifier: PlaybackBackendDirective.tvvlcKit.rawValue, fallbackReason: forcedFallbackReasonForNextPlayback)
            forcedBackendForNextPlayback = nil
            forcedFallbackReasonForNextPlayback = nil
            await super.play(url: url, startPosition: startPosition)
            return
        }

        if startMpvPlayback(url.absoluteString, startPosition: startPosition > 0 ? startPosition : nil) {
            forcedBackendForNextPlayback = nil
            forcedFallbackReasonForNextPlayback = nil
            return
        }

        usesMpvBackend = false
        updatePlaybackBackend(identifier: PlaybackBackendDirective.tvvlcKit.rawValue, fallbackReason: "mpv_load_failed")
        await super.play(url: url, startPosition: startPosition)
    }

    override func configureSubtitleAppearance(_ options: [String: Any]) {
        super.configureSubtitleAppearance(options)
        mpvSubtitleOptions = options
        engine?.applySubtitleStyle(options)
    }

    override func play(streamUrl: String, startPosition: TimeInterval = 0) async {
        if forcedBackendForNextPlayback == .tvvlcKit {
            usesMpvBackend = false
            updatePlaybackBackend(identifier: PlaybackBackendDirective.tvvlcKit.rawValue, fallbackReason: forcedFallbackReasonForNextPlayback)
            forcedBackendForNextPlayback = nil
            forcedFallbackReasonForNextPlayback = nil
            await super.play(streamUrl: streamUrl, startPosition: startPosition)
            return
        }

        if startMpvPlayback(streamUrl, startPosition: startPosition > 0 ? startPosition : nil) {
            forcedBackendForNextPlayback = nil
            forcedFallbackReasonForNextPlayback = nil
            return
        }

        usesMpvBackend = false
        updatePlaybackBackend(identifier: PlaybackBackendDirective.tvvlcKit.rawValue, fallbackReason: "mpv_load_failed")
        await super.play(streamUrl: streamUrl, startPosition: startPosition)
    }

    override func configurePreferredBackendForNextPlayback(_ backend: PlaybackBackendDirective, fallbackReason: String?) {
        forcedBackendForNextPlayback = backend
        forcedFallbackReasonForNextPlayback = fallbackReason
        if backend == .tvvlcKit {
            updatePlaybackBackend(identifier: backend.rawValue, fallbackReason: fallbackReason)
        }
    }

    override func configureDynamicRangeIntent(contentRange: VideoDynamicRange, sinkIsHdrCapable: Bool) {
        requestedContentRange = contentRange
        self.sinkIsHdrCapable = sinkIsHdrCapable

        guard usesMpvBackend else { return }
        applyDynamicRangeIntent()
    }

    override func dynamicRangeTelemetrySnapshot() -> [String: String] {
        guard usesMpvBackend, let engine else {
            return [
                "mpv_dynamic_range_telemetry": "unavailable",
                "mpv_intent_content_range": requestedContentRange.rawValue,
                "mpv_intent_sink_hdr_capable": sinkIsHdrCapable ? "true" : "false",
                "mpv_intent_tone_mapping": activeToneMappingMode
            ]
        }

        let inputPrimaries = engine.getStringProperty("video-params/primaries") ?? "unknown"
        let inputTransfer = engine.getStringProperty("video-params/gamma") ?? "unknown"
        let outputPrimaries = engine.getStringProperty("video-out-params/primaries") ?? "unknown"
        let outputTransfer = engine.getStringProperty("video-out-params/gamma") ?? "unknown"
        let inputPeak = engine.getDoubleProperty("video-params/sig-peak")
            .map { String(format: "%.2f", $0) } ?? "unknown"

        return [
            "mpv_dynamic_range_telemetry": "available",
            "mpv_intent_content_range": requestedContentRange.rawValue,
            "mpv_intent_sink_hdr_capable": sinkIsHdrCapable ? "true" : "false",
            "mpv_intent_tone_mapping": activeToneMappingMode,
            "mpv_input_primaries": inputPrimaries,
            "mpv_input_transfer": inputTransfer,
            "mpv_input_sig_peak": inputPeak,
            "mpv_output_primaries": outputPrimaries,
            "mpv_output_transfer": outputTransfer
        ]
    }

    override func pause() {
        if usesMpvBackend {
            _ = engine?.setPause(true)
            state = .paused
            return
        }
        super.pause()
    }

    override func resume() {
        if usesMpvBackend {
            _ = engine?.setPause(false)
            state = .playing
            return
        }
        super.resume()
    }

    override func stop() {
        if usesMpvBackend {
            _ = engine?.stopPlayback()
            stopRenderScheduler()
            usesMpvBackend = false
            pendingMpvStartPosition = nil
            pendingMpvSeekAttempts = 0
            pendingMpvSeekLastAttemptAt = 0
            state = .idle
            position = 0
            currentTime = 0
            duration = 0
            bufferProgress = 0
            audioTracks = []
            subtitleTracks = []
            currentAudioTrackIndex = -1
            currentSubtitleTrackIndex = -1
            resetEngine()
            return
        }

        super.stop()
        wasPlayingBeforeBackground = false
    }

    override func seek(to seconds: TimeInterval) {
        if usesMpvBackend {
            _ = engine?.seekAbsolute(seconds)
            currentTime = max(0, seconds)
            if duration > 0 {
                position = Float(max(0, min(1, currentTime / duration)))
            }
            return
        }
        super.seek(to: seconds)
    }

    override func seekBy(_ delta: TimeInterval) {
        if usesMpvBackend {
            _ = engine?.seekRelative(delta)
            return
        }
        super.seekBy(delta)
    }

    override func seekToPosition(_ pos: Float) {
        if usesMpvBackend {
            let target = TimeInterval(max(0, min(1, pos))) * duration
            _ = engine?.seekAbsolute(target)
            return
        }
        super.seekToPosition(pos)
    }

    override func setRate(_ newRate: Float) {
        if usesMpvBackend {
            _ = engine?.setSpeed(newRate)
            rate = newRate
            return
        }
        super.setRate(newRate)
    }

    override func setAudioTrack(_ trackIndex: Int32) {
        if usesMpvBackend {
            _ = engine?.setAudioTrack(trackIndex)
            currentAudioTrackIndex = trackIndex
            return
        }
        super.setAudioTrack(trackIndex)
    }

    override func setSubtitleTrack(_ trackIndex: Int32) {
        if usesMpvBackend {
            _ = engine?.setSubtitleTrack(trackIndex)
            currentSubtitleTrackIndex = trackIndex
            return
        }
        super.setSubtitleTrack(trackIndex)
    }

    override func disableSubtitles() {
        if usesMpvBackend {
            _ = engine?.disableSubtitles()
            currentSubtitleTrackIndex = -1
            return
        }
        super.disableSubtitles()
    }

    override func setSubtitleDelay(_ interval: TimeInterval) {
        if usesMpvBackend {
            _ = engine?.command(["set", "sub-delay", String(interval)])
            return
        }
        super.setSubtitleDelay(interval)
    }

    override func setAudioDelay(_ interval: TimeInterval) {
        if usesMpvBackend {
            _ = engine?.command(["set", "audio-delay", String(interval)])
            return
        }
        super.setAudioDelay(interval)
    }

    override func addSubtitle(url: URL) {
        if usesMpvBackend {
            _ = engine?.command(["sub-add", url.absoluteString])
            return
        }
        super.addSubtitle(url: url)
    }

    override func setZoomMode(_ mode: ZoomMode) {
        if usesMpvBackend {
            switch mode {
            case .fit:
                _ = engine?.command(["set", "video-aspect-override", "-1"])
                _ = engine?.command(["set", "panscan", "0"])
            case .autoCrop:
                _ = engine?.command(["set", "video-aspect-override", "-1"])
                _ = engine?.command(["set", "panscan", "1.0"])
            case .stretch:
                _ = engine?.command(["set", "video-aspect-override", "16:9"])
                _ = engine?.command(["set", "panscan", "0"])
            }
            zoomMode = mode
            return
        }
        super.setZoomMode(mode)
    }

    override func cycleZoomMode() {
        setZoomMode(zoomMode.next)
    }

    private func startMpvPlayback(_ url: String, startPosition: TimeInterval?) -> Bool {
        pendingMpvStartPosition = (startPosition ?? 0) > 0 ? startPosition : nil
        pendingMpvSeekAttempts = 0
        pendingMpvSeekLastAttemptAt = 0

        if ensureEngine(profile: .metal), engine?.loadFile(url) == true {
            engine?.applySubtitleStyle(mpvSubtitleOptions)
            applyDynamicRangeIntent()
            usesMpvBackend = true
            updatePlaybackBackend(identifier: "mpv", fallbackReason: nil)
            state = .opening
            startRenderScheduler()
            return true
        }

        let metalError = engine?.lastInitError
        resetEngine()

        if ensureEngine(profile: .software), engine?.loadFile(url) == true {
            engine?.applySubtitleStyle(mpvSubtitleOptions)
            applyDynamicRangeIntent()
            usesMpvBackend = true
            let reason = metalError.map { "metal_renderer_unavailable:\($0)" } ?? "metal_renderer_unavailable"
            updatePlaybackBackend(identifier: "mpv", fallbackReason: reason)
            state = .opening
            startRenderScheduler()
            return true
        }

        resetEngine()
        pendingMpvStartPosition = nil
        pendingMpvSeekAttempts = 0
        pendingMpvSeekLastAttemptAt = 0
        return false
    }

    private func applyPendingMpvStartPositionIfNeeded() {
        guard usesMpvBackend, let startPosition = pendingMpvStartPosition, startPosition > 0, let engine else { return }

        if let current = engine.getDoubleProperty("time-pos"), current.isFinite {
            if abs(current - startPosition) <= 1.5 {
                pendingMpvStartPosition = nil
                pendingMpvSeekAttempts = 0
                pendingMpvSeekLastAttemptAt = 0
                return
            }
        }

        guard pendingMpvSeekAttempts < maxPendingMpvSeekAttempts else {
            pendingMpvStartPosition = nil
            pendingMpvSeekAttempts = 0
            pendingMpvSeekLastAttemptAt = 0
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        guard pendingMpvSeekLastAttemptAt == 0 || (now - pendingMpvSeekLastAttemptAt) >= minPendingMpvSeekRetryInterval else {
            return
        }

        if engine.seekAbsolute(startPosition) {
            pendingMpvSeekAttempts += 1
            pendingMpvSeekLastAttemptAt = now
        }
    }

    private func ensureEngine(profile: MPVRenderProfile) -> Bool {
        if let engine, activeProfile == profile {
            return engine.isReady
        }

        resetEngine()

        let created = MPVEngine(
            renderProfile: profile,
            drawableHandle: videoSurface.drawableHandle,
            updateHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.renderUpdatePending = true
                }
            }
        )

        guard created.isReady else {
            return false
        }

        engine = created
        activeProfile = profile
        return true
    }

    private func resetEngine() {
        engine = nil
    }

    private func applyDynamicRangeIntent() {
        guard let engine else { return }

        let isHdrContent: Bool = {
            switch requestedContentRange {
            case .hdr10, .hlg, .hdr10Plus, .dolbyVision:
                return true
            case .sdr, .unknown:
                return false
            }
        }()

        if isHdrContent && sinkIsHdrCapable {
            activeToneMappingMode = "clip"
            _ = engine.setRuntimeOption("tone-mapping", value: "clip")
            _ = engine.setRuntimeOption("hdr-compute-peak", value: "no")
        } else if isHdrContent {
            activeToneMappingMode = "bt.2390"
            _ = engine.setRuntimeOption("tone-mapping", value: "bt.2390")
            _ = engine.setRuntimeOption("hdr-compute-peak", value: "yes")
        } else {
            activeToneMappingMode = "auto"
            _ = engine.setRuntimeOption("tone-mapping", value: "auto")
            _ = engine.setRuntimeOption("hdr-compute-peak", value: "yes")
        }
    }

    private func startRenderScheduler() {
        stopRenderScheduler()
        renderTickCounter = 0
        lastRenderTimestamp = CFAbsoluteTimeGetCurrent()
        lastWatchdogWarningAt = 0
        let link = CADisplayLink(target: self, selector: #selector(handleRenderTick))
        link.add(to: .main, forMode: .common)
        renderDisplayLink = link
        renderWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkRenderWatchdog()
            }
        }
    }

    private func stopRenderScheduler() {
        renderDisplayLink?.invalidate()
        renderDisplayLink = nil
        renderWatchdogTimer?.invalidate()
        renderWatchdogTimer = nil
        renderUpdatePending = false
    }

    private func checkRenderWatchdog() {
        guard usesMpvBackend, state == .playing else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastRenderTimestamp
        if elapsed > 2, now - lastWatchdogWarningAt > 15 {
            lastWatchdogWarningAt = now
            logger.warning("render_watchdog stall detected: no render update for \(String(format: "%.1f", elapsed))s")
        }
    }

    @objc private func handleRenderTick() {
        guard usesMpvBackend else { return }
        if renderUpdatePending {
            renderUpdatePending = false
            engine?.drainPendingEvents { [weak self] event in
                guard let self else { return }
                self.applyEvent(event)
            }
            lastRenderTimestamp = CFAbsoluteTimeGetCurrent()
        }
        renderTickCounter &+= 1
        if renderTickCounter % 30 == 0 {
            updateFromMpvProperties()
        }
        videoSurface.updateLayout()
    }

    override func snapshotPlaybackPosition() -> TimeInterval {
        guard usesMpvBackend, let engine else {
            return super.snapshotPlaybackPosition()
        }

        if let pos = engine.getDoubleProperty("time-pos"), pos.isFinite, pos >= 0 {
            return pos
        }

        return super.snapshotPlaybackPosition()
    }

    private func applyEvent(_ event: MPVEngine.Event) {
        switch event.id {
        case MPVEngine.EventID.startFile.rawValue:
            state = .opening
        case MPVEngine.EventID.fileLoaded.rawValue:
            state = .buffering(0.25)
            applyPendingMpvStartPositionIfNeeded()
            refreshTracksFromMpv()
        case MPVEngine.EventID.playbackRestart.rawValue:
            applyPendingMpvStartPositionIfNeeded()
            state = .playing
            refreshTracksFromMpv()
        case MPVEngine.EventID.endFile.rawValue:
            if event.endReason == .error {
                state = .error
            } else {
                state = .ended
            }
        case MPVEngine.EventID.seek.rawValue:
            state = .buffering(0.25)
        case MPVEngine.EventID.propertyChange.rawValue:
            applyPropertyEvent(event)
        case MPVEngine.EventID.shutdown.rawValue:
            state = .stopped
            usesMpvBackend = false
            stopRenderScheduler()
            resetEngine()
        default:
            break
        }
    }

    private func applyPropertyEvent(_ event: MPVEngine.Event) {
        guard let propertyName = event.propertyName else { return }

        switch propertyName {
        case "pause":
            if let paused = event.boolValue {
                state = paused ? .paused : .playing
            }
        case "time-pos":
            if let timePos = event.doubleValue {
                currentTime = max(0, timePos)
                if duration > 0 {
                    position = Float(max(0, min(1, currentTime / duration)))
                }
            }
        case "duration":
            if let dur = event.doubleValue, dur.isFinite, dur > 0 {
                duration = dur
                if duration > 0 {
                    position = Float(max(0, min(1, currentTime / duration)))
                }
            }
        case "paused-for-cache":
            if let pausedForCache = event.boolValue {
                if pausedForCache {
                    state = .buffering(bufferProgress)
                } else if state == .buffering(bufferProgress) {
                    state = .playing
                }
            }
        case "cache-buffering-state":
            if let pct = event.doubleValue {
                let normalized = Float(max(0, min(1, pct / 100)))
                bufferProgress = normalized
                if normalized < 1, state != .paused {
                    state = .buffering(normalized)
                }
            }
        case "eof-reached":
            if event.boolValue == true {
                state = .ended
            }
        case "aid":
            if let aid = event.intValue, let intValue = Int32(exactly: aid) {
                currentAudioTrackIndex = intValue
            }
        case "sid":
            if let sid = event.intValue, let intValue = Int32(exactly: sid) {
                currentSubtitleTrackIndex = intValue
            } else {
                currentSubtitleTrackIndex = -1
            }
        case "track-list/count":
            refreshTracksFromMpv()
        default:
            break
        }
    }

    private func updateFromMpvProperties() {
        guard let engine else { return }

        applyPendingMpvStartPositionIfNeeded()

        if let pos = engine.getDoubleProperty("time-pos") {
            currentTime = pos
        }

        if let dur = engine.getDoubleProperty("duration"), dur.isFinite, dur > 0 {
            duration = dur
        }

        if duration > 0 {
            position = Float(max(0, min(1, currentTime / duration)))
        }

        if let paused = engine.getFlagProperty("pause") {
            if paused {
                state = .paused
            } else if state == .opening || state == .buffering(0.25) || state == .paused {
                state = .playing
            }
        }

        if let pausedForCache = engine.getFlagProperty("paused-for-cache"), pausedForCache {
            state = .buffering(bufferProgress)
        }

        if let cachePct = engine.getDoubleProperty("cache-buffering-state") {
            let normalized = Float(max(0, min(1, cachePct / 100)))
            bufferProgress = normalized
            if normalized < 1, state != .paused {
                state = .buffering(normalized)
            }
        }

        if let eofReached = engine.getFlagProperty("eof-reached"), eofReached {
            state = .ended
        }

        if let aid = engine.getInt64Property("aid"), let intValue = Int32(exactly: aid) {
            if currentAudioTrackIndex != intValue {
                currentAudioTrackIndex = intValue
            }
        }

        if let sid = engine.getInt64Property("sid"), let intValue = Int32(exactly: sid) {
            if currentSubtitleTrackIndex != intValue {
                currentSubtitleTrackIndex = intValue
            }
        } else if currentSubtitleTrackIndex != -1 {
            currentSubtitleTrackIndex = -1
        }
    }

    private func refreshTracksFromMpv() {
        guard usesMpvBackend, let engine else { return }
        let tracks = engine.trackList()

        let nextAudio = tracks
            .filter { $0.type == .audio }
            .compactMap(makeTrack)

        let nextSubtitles = tracks
            .filter { $0.type == .subtitle }
            .compactMap(makeTrack)

        if nextAudio != audioTracks {
            audioTracks = nextAudio
        }
        if nextSubtitles != subtitleTracks {
            subtitleTracks = nextSubtitles
        }
    }

    private func makeTrack(from track: MPVEngine.TrackInfo) -> VLCTrack? {
        guard let id = Int32(exactly: track.id) else {
            return nil
        }

        var parts: [String] = []
        if let title = normalizedTrackText(track.title) {
            parts.append(title)
        }
        if let language = normalizedTrackText(track.language), !parts.contains(language) {
            parts.append(language)
        }
        if track.isForced {
            parts.append("Forced")
        }
        if track.isDefault {
            parts.append("Default")
        }

        let name: String
        if parts.isEmpty {
            name = "Track \(id)"
        } else {
            name = parts.joined(separator: " - ")
        }

        return VLCTrack(
            id: id,
            name: name,
            language: normalizedTrackText(track.language),
            title: normalizedTrackText(track.title),
            isDefault: track.isDefault,
            isForced: track.isForced,
            codec: normalizedTrackText(track.codec)
        )
    }

    private func normalizedTrackText(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.wasPlayingBeforeBackground = self.isPlaying
                    if self.wasPlayingBeforeBackground {
                        self.pause()
                    }
                    self.videoSurface.updateLayout()
                }
            }
        )

        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.videoSurface.updateLayout()
                    if self.wasPlayingBeforeBackground {
                        self.wasPlayingBeforeBackground = false
                        self.resume()
                    }
                }
            }
        )

        lifecycleObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard
                        let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                        let type = AVAudioSession.InterruptionType(rawValue: rawType)
                    else {
                        return
                    }

                    switch type {
                    case .began:
                        self.wasPlayingBeforeInterruption = self.isPlaying
                        if self.wasPlayingBeforeInterruption {
                            self.pause()
                        }
                    case .ended:
                        let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                        if self.wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                            self.wasPlayingBeforeInterruption = false
                            self.resume()
                        } else {
                            self.wasPlayingBeforeInterruption = false
                        }
                    @unknown default:
                        self.wasPlayingBeforeInterruption = false
                    }
                }
            }
        )
    }

    static func makePlayer() -> VLCPlayerWrapper {
#if canImport(MPVKit)
        return MpvPlayerWrapper()
#else
        return VLCPlayerWrapper()
#endif
    }

    static func makePreferredPlayer(defaults: UserDefaults = .standard) -> VLCPlayerWrapper {
        let raw = defaults.string(forKey: UserPreferences.playbackPlayerBackend.key)
        let requested = PlaybackPlayerBackend(rawValue: raw ?? "") ?? .mpv
        let active = PlaybackBackendSupport.resolve(for: requested).active

        switch active {
        case .tvvlcKit:
            return VLCPlayerWrapper()
        case .mpv:
            return makePlayer()
        }
    }
}

private enum MPVRenderProfile {
    case metal
    case software
}

private final class MPVVideoSurface {
    private weak var hostView: UIView?
    private let metalLayer = SafeMetalLayer()

    init() {
#if canImport(Metal)
        metalLayer.device = MTLCreateSystemDefaultDevice()
#endif
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.isOpaque = true
    }

    var drawableHandle: UInt64? {
        UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
    }

    func attach(to view: UIView) {
        hostView = view
        metalLayer.removeFromSuperlayer()
        view.layer.addSublayer(metalLayer)
        updateLayout()
    }

    func updateLayout() {
        guard let hostView else { return }
        let bounds = hostView.bounds
        if metalLayer.frame != bounds {
            metalLayer.frame = bounds
        }
        let scale = hostView.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        if metalLayer.contentsScale != scale {
            metalLayer.contentsScale = scale
        }
    }

    func teardown() {
        metalLayer.removeFromSuperlayer()
        hostView = nil
    }
}

private final class SafeMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

private final class MPVEngine {
    enum TrackType: String {
        case audio
        case subtitle = "sub"
        case video
        case unknown
    }

    struct TrackInfo {
        var id: Int64
        var type: TrackType
        var title: String?
        var language: String?
        var isDefault: Bool
        var isForced: Bool
        var codec: String?
    }

    enum EventID: Int32 {
        case shutdown = 1
        case startFile = 6
        case endFile = 7
        case fileLoaded = 8
        case playbackRestart = 21
        case propertyChange = 22
        case seek = 20
    }

    enum EndReason: Int32 {
        case eof = 0
        case stop = 2
        case quit = 3
        case error = 4
        case redirect = 5
    }

    struct Event {
        var id: Int32
        var endReason: EndReason?
        var propertyName: String?
        var boolValue: Bool?
        var doubleValue: Double?
        var intValue: Int64?
    }

    private struct MPVEvent {
        var eventId: Int32
        var error: Int32
        var replyUserdata: UInt64
        var data: UnsafeMutableRawPointer?
    }

    private struct MPVEventProperty {
        var name: UnsafePointer<CChar>?
        var format: Int32
        var data: UnsafeMutableRawPointer?
    }

    private struct MPVEventEndFile {
        var reason: Int32
        var error: Int32
        var playlistEntryId: Int64
        var playlistInsertId: Int64
        var playlistInsertNumEntries: Int32
    }

    private typealias MPVCreateFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias MPVInitializeFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias MPVTerminateDestroyFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias MPVCommandFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
    private typealias MPVSetOptionFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
    private typealias MPVSetOptionStringFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias MPVSetWakeupCallbackFn = @convention(c) (UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void
    private typealias MPVGetPropertyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
    private typealias MPVWaitEventFn = @convention(c) (UnsafeMutableRawPointer?, Double) -> UnsafeMutableRawPointer?
    private typealias MPVObservePropertyFn = @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafePointer<CChar>?, Int32) -> Int32
    private typealias MPVSetPropertyStringFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias MPVErrorStringFn = @convention(c) (Int32) -> UnsafePointer<CChar>?

    private enum Format {
        static let string: Int32 = 1
        static let flag: Int32 = 3
        static let int64: Int32 = 4
        static let double: Int32 = 5
    }

    private let createFn: MPVCreateFn?
    private let initializeFn: MPVInitializeFn?
    private let terminateDestroyFn: MPVTerminateDestroyFn?
    private let commandFn: MPVCommandFn?
    private let setOptionFn: MPVSetOptionFn?
    private let setOptionStringFn: MPVSetOptionStringFn?
    private let setWakeupCallbackFn: MPVSetWakeupCallbackFn?
    private let getPropertyFn: MPVGetPropertyFn?
    private let waitEventFn: MPVWaitEventFn?
    private let observePropertyFn: MPVObservePropertyFn?
    private let setPropertyStringFn: MPVSetPropertyStringFn?
    private let errorStringFn: MPVErrorStringFn?

    private var handle: UnsafeMutableRawPointer?
    private var wakeupHandler: (() -> Void)?

    var isReady: Bool { handle != nil }
    private(set) var lastInitError: String?

    init(renderProfile: MPVRenderProfile, drawableHandle: UInt64?, updateHandler: @escaping () -> Void) {
        createFn = Self.resolveSymbol("mpv_create", as: MPVCreateFn.self)
        initializeFn = Self.resolveSymbol("mpv_initialize", as: MPVInitializeFn.self)
        terminateDestroyFn = Self.resolveSymbol("mpv_terminate_destroy", as: MPVTerminateDestroyFn.self)
        commandFn = Self.resolveSymbol("mpv_command", as: MPVCommandFn.self)
        setOptionFn = Self.resolveSymbol("mpv_set_option", as: MPVSetOptionFn.self)
        setOptionStringFn = Self.resolveSymbol("mpv_set_option_string", as: MPVSetOptionStringFn.self)
        setWakeupCallbackFn = Self.resolveSymbol("mpv_set_wakeup_callback", as: MPVSetWakeupCallbackFn.self)
        getPropertyFn = Self.resolveSymbol("mpv_get_property", as: MPVGetPropertyFn.self)
        waitEventFn = Self.resolveSymbol("mpv_wait_event", as: MPVWaitEventFn.self)
        observePropertyFn = Self.resolveSymbol("mpv_observe_property", as: MPVObservePropertyFn.self)
        setPropertyStringFn = Self.resolveSymbol("mpv_set_property_string", as: MPVSetPropertyStringFn.self)
        errorStringFn = Self.resolveSymbol("mpv_error_string", as: MPVErrorStringFn.self)

        guard let createFn, let initializeFn else { return }
        let created = createFn()

        if let drawableHandle {
            var layerHandle = Int64(bitPattern: drawableHandle)
            _ = setInt64Option("wid", value: &layerHandle, on: created)
        }

        _ = setOptionString("subs-match-os-language", value: "yes", on: created)
        _ = setOptionString("subs-fallback", value: "yes", on: created)
        _ = setOptionString("vo", value: "gpu-next", on: created)
        _ = setOptionString("gpu-api", value: "vulkan", on: created)
        _ = setOptionString("gpu-context", value: "moltenvk", on: created)
        _ = setOptionString("hwdec-codecs", value: "all", on: created)
        _ = setOptionString("target-colorspace-hint", value: "auto", on: created)
        _ = setOptionString("target-colorspace-hint-mode", value: "auto", on: created)
        _ = setOptionString("tone-mapping", value: "auto", on: created)
        _ = setOptionString("hdr-compute-peak", value: "yes", on: created)
        _ = setOptionString("allow-delayed-peak-detect", value: "yes", on: created)
        _ = setOptionString("deband", value: "yes", on: created)
        _ = setOptionString("temporal-dither", value: "yes", on: created)
        _ = setOptionString("vd-lavc-film-grain", value: "gpu", on: created)
        _ = setOptionString("video-rotate", value: "no", on: created)

        _ = setOptionString("demuxer-max-bytes", value: "250MiB", on: created)
        _ = setOptionString("demuxer-max-back-bytes", value: "75MiB", on: created)
        _ = setOptionString("cache", value: "yes", on: created)
        _ = setOptionString("cache-secs", value: "120", on: created)

        switch renderProfile {
        case .metal:
            _ = setOptionString("hwdec", value: "videotoolbox", on: created)
        case .software:
            _ = setOptionString("hwdec", value: "no", on: created)
            _ = setOptionString("gpu-sw", value: "yes", on: created)
        }

        let initResult = initializeFn(created)
        guard initResult >= 0 else {
            if let errorStringFn, let cStr = errorStringFn(initResult) {
                lastInitError = String(cString: cStr)
            }
            terminateDestroyFn?(created)
            return
        }

        handle = created
        wakeupHandler = updateHandler
        installWakeupCallback()
        observeCoreProperties()
    }

    deinit {
        clearWakeupCallback()
        terminateDestroyFn?(handle)
    }

    func loadFile(_ url: String) -> Bool {
        command(["loadfile", url, "replace"])
    }

    func setPause(_ paused: Bool) -> Bool {
        command(["set", "pause", paused ? "yes" : "no"])
    }

    func stopPlayback() -> Bool {
        command(["stop"])
    }

    func seekAbsolute(_ seconds: TimeInterval) -> Bool {
        command(["seek", String(seconds), "absolute"])
    }

    func seekRelative(_ seconds: TimeInterval) -> Bool {
        command(["seek", String(seconds), "relative"])
    }

    func setSpeed(_ speed: Float) -> Bool {
        command(["set", "speed", String(speed)])
    }

    func setAudioTrack(_ trackId: Int32) -> Bool {
        command(["set", "aid", String(trackId)])
    }

    func setSubtitleTrack(_ trackId: Int32) -> Bool {
        command(["set", "sid", String(trackId)])
    }

    func disableSubtitles() -> Bool {
        command(["set", "sid", "no"])
    }

    func setRuntimeOption(_ name: String, value: String) -> Bool {
        guard let handle, let setPropertyStringFn else { return false }
        let result = name.withCString { cName in
            value.withCString { cValue in
                setPropertyStringFn(handle, cName, cValue)
            }
        }
        return result >= 0
    }

    func applySubtitleStyle(_ options: [String: Any]) {
        let mappings: [(String, String)] = [
            ("freetype-rel-fontsize", "sub-font-size"),
            ("sub-margin", "sub-margin-y"),
            ("freetype-outline-thickness", "sub-border-size")
        ]

        for (sourceKey, targetKey) in mappings {
            guard let value = options[sourceKey] else { continue }
            _ = setOptionString(targetKey, value: String(describing: value), on: handle)
        }

        if let color = options["freetype-color"] as? Int {
            _ = setOptionString("sub-color", value: vlcColorToMpv(color, alpha: 255), on: handle)
        }

        if let outlineColor = options["freetype-outline-color"] as? Int {
            _ = setOptionString("sub-border-color", value: vlcColorToMpv(outlineColor, alpha: 255), on: handle)
        }

        let bgOpacity = options["freetype-background-opacity"] as? Int ?? 0
        if let bgColor = options["freetype-background-color"] as? Int {
            _ = setOptionString("sub-back-color", value: vlcColorToMpv(bgColor, alpha: bgOpacity), on: handle)
        } else {
            _ = setOptionString("sub-back-color", value: vlcColorToMpv(0, alpha: bgOpacity), on: handle)
        }

        if let bold = options["freetype-bold"] as? Bool {
            _ = setOptionString("sub-bold", value: bold ? "yes" : "no", on: handle)
        }

        if let assOverride = options["sub-ass-override"] as? String {
            _ = setOptionString("sub-ass-override", value: assOverride, on: handle)
        }
    }

    private func vlcColorToMpv(_ rgb: Int, alpha: Int) -> String {
        let r = (rgb >> 16) & 0xFF
        let g = (rgb >> 8) & 0xFF
        let b = rgb & 0xFF
        let a = min(max(alpha, 0), 255)
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }

    func getDoubleProperty(_ name: String) -> Double? {
        guard let handle, let getPropertyFn else { return nil }
        var value: Double = 0
        let result = name.withCString { cName in
            getPropertyFn(handle, cName, Format.double, &value)
        }
        return result >= 0 ? value : nil
    }

    func getFlagProperty(_ name: String) -> Bool? {
        guard let handle, let getPropertyFn else { return nil }
        var value: Int32 = 0
        let result = name.withCString { cName in
            getPropertyFn(handle, cName, Format.flag, &value)
        }
        return result >= 0 ? value != 0 : nil
    }

    func getInt64Property(_ name: String) -> Int64? {
        guard let handle, let getPropertyFn else { return nil }
        var value: Int64 = 0
        let result = name.withCString { cName in
            getPropertyFn(handle, cName, Format.int64, &value)
        }
        return result >= 0 ? value : nil
    }

    func getStringProperty(_ name: String) -> String? {
        guard let handle, let getPropertyFn else { return nil }
        var raw: UnsafeMutablePointer<CChar>?
        let result = name.withCString { cName in
            getPropertyFn(handle, cName, Format.string, &raw)
        }
        guard result >= 0, let raw else { return nil }
        defer { free(raw) }
        return String(cString: raw)
    }

    func trackList() -> [TrackInfo] {
        guard let count = getInt64Property("track-list/count"), count > 0 else {
            return []
        }

        var tracks: [TrackInfo] = []
        tracks.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            let prefix = "track-list/\(index)"
            guard
                let id = getInt64Property("\(prefix)/id"),
                let typeRaw = getStringProperty("\(prefix)/type")
            else {
                continue
            }

            let type = TrackType(rawValue: typeRaw) ?? .unknown
            let title = getStringProperty("\(prefix)/title")
            let language = getStringProperty("\(prefix)/lang")
            let isDefault = getFlagProperty("\(prefix)/default") ?? false
            let isForced = getFlagProperty("\(prefix)/forced") ?? false
            let codec = getStringProperty("\(prefix)/codec")

            tracks.append(
                TrackInfo(
                    id: id,
                    type: type,
                    title: title,
                    language: language,
                    isDefault: isDefault,
                    isForced: isForced,
                    codec: codec
                )
            )
        }

        return tracks
    }

    func drainPendingEvents(_ handler: (Event) -> Void) {
        guard let handle, let waitEventFn else { return }

        while true {
            guard let rawPtr = waitEventFn(handle, 0) else { return }
            let event = rawPtr.load(as: MPVEvent.self)
            if event.eventId == 0 {
                return
            }
            handler(parseEvent(event))
        }
    }

    private func parseEvent(_ event: MPVEvent) -> Event {
        var mapped = Event(id: event.eventId)

        if event.eventId == EventID.endFile.rawValue,
           let data = event.data {
            let end = data.load(as: MPVEventEndFile.self)
            mapped.endReason = EndReason(rawValue: end.reason)
        }

        if event.eventId == EventID.propertyChange.rawValue,
           let data = event.data {
            let property = data.load(as: MPVEventProperty.self)
            if let cName = property.name {
                mapped.propertyName = String(cString: cName)
            }

            switch property.format {
            case Format.flag:
                if let p = property.data {
                    mapped.boolValue = p.load(as: Int32.self) != 0
                }
            case Format.int64:
                if let p = property.data {
                    mapped.intValue = p.load(as: Int64.self)
                }
            case Format.double:
                if let p = property.data {
                    mapped.doubleValue = p.load(as: Double.self)
                }
            default:
                break
            }
        }

        return mapped
    }

    private func installWakeupCallback() {
        guard let handle, let setWakeupCallbackFn else { return }
        setWakeupCallbackFn(handle, MPVEngine.wakeupTrampoline, Unmanaged.passUnretained(self).toOpaque())
    }

    private func observeCoreProperties() {
        _ = observeProperty("time-pos", format: Format.double, userData: 1)
        _ = observeProperty("duration", format: Format.double, userData: 2)
        _ = observeProperty("pause", format: Format.flag, userData: 3)
        _ = observeProperty("eof-reached", format: Format.flag, userData: 4)
        _ = observeProperty("paused-for-cache", format: Format.flag, userData: 5)
        _ = observeProperty("cache-buffering-state", format: Format.double, userData: 6)
        _ = observeProperty("aid", format: Format.int64, userData: 7)
        _ = observeProperty("sid", format: Format.int64, userData: 8)
        _ = observeProperty("track-list/count", format: Format.int64, userData: 9)
    }

    private func observeProperty(_ name: String, format: Int32, userData: UInt64) -> Bool {
        guard let handle, let observePropertyFn else { return false }
        let result = name.withCString { cName in
            observePropertyFn(handle, userData, cName, format)
        }
        return result >= 0
    }

    private func clearWakeupCallback() {
        guard let handle, let setWakeupCallbackFn else { return }
        setWakeupCallbackFn(handle, nil, nil)
    }

    private static let wakeupTrampoline: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
        guard let context else { return }
        let owner = Unmanaged<MPVEngine>.fromOpaque(context).takeUnretainedValue()
        owner.wakeupHandler?()
    }

    fileprivate func command(_ args: [String]) -> Bool {
        guard let handle, let commandFn else { return false }

        let cArgs = args.map { strdup($0) }
        defer {
            for cArg in cArgs {
                free(cArg)
            }
        }

        var argPointers = cArgs.map { ptr in
            ptr.map { UnsafePointer<CChar>($0) }
        }
        argPointers.append(nil)

        let result = argPointers.withUnsafeMutableBufferPointer { buffer in
            commandFn(handle, buffer.baseAddress)
        }

        return result >= 0
    }

    private func setInt64Option(_ name: String, value: inout Int64, on handle: UnsafeMutableRawPointer?) -> Bool {
        guard let handle, let setOptionFn else { return false }
        let result = name.withCString { cName in
            setOptionFn(handle, cName, Format.int64, &value)
        }
        return result >= 0
    }

    private func setOptionString(_ name: String, value: String, on handle: UnsafeMutableRawPointer?) -> Bool {
        guard let handle, let setOptionStringFn else { return false }
        let result = name.withCString { cName in
            value.withCString { cValue in
                setOptionStringFn(handle, cName, cValue)
            }
        }
        return result >= 0
    }

    private static func resolveSymbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}
