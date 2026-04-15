import SwiftUI
import UIKit

@MainActor
final class InactivityTracker: ObservableObject {

    @Published private(set) var isScreensaverVisible = false {
        didSet {
            updateIdleTimerState()
        }
    }

    private let userPreferences: UserPreferences
    private weak var playbackCoordinator: PlaybackCoordinator?
    private var timer: DispatchWorkItem?
    private var lockCount = 0
    private var lastInteractionAt = Date()

    init(userPreferences: UserPreferences, playbackCoordinator: PlaybackCoordinator) {
        self.userPreferences = userPreferences
        self.playbackCoordinator = playbackCoordinator
        resetTimer()
        updateIdleTimerState()
    }

    private var isEnabled: Bool {
        userPreferences[UserPreferences.screensaverEnabled]
    }

    private var timeout: TimeInterval {
        TimeInterval(userPreferences[UserPreferences.screensaverTimeout]) * 60.0
    }

    private var isPlaybackActive: Bool {
        guard let coordinator = playbackCoordinator else { return false }
        if let video = coordinator.videoPlayerManager, video.playbackState == .playing || video.playbackState == .paused {
            return true
        }
        if let audio = coordinator.audioManager,
           audio.playbackManager.playbackState == .playing || audio.playbackManager.playbackState == .paused {
            return true
        }
        return false
    }

    private var shouldDisableSystemIdleTimer: Bool {
        isEnabled || lockCount > 0 || isPlaybackActive || isScreensaverVisible
    }

    func notifyInteraction() {
        timer?.cancel()
        lastInteractionAt = Date()
        if isScreensaverVisible {
            isScreensaverVisible = false
        }
        updateIdleTimerState()
        resetTimer()
    }

    func addLock() {
        lockCount += 1
        timer?.cancel()
        if isScreensaverVisible {
            isScreensaverVisible = false
        }
        updateIdleTimerState()
    }

    func removeLock() {
        lockCount = max(0, lockCount - 1)
        updateIdleTimerState()
        if lockCount == 0 {
            resetTimer()
        }
    }

    private func resetTimer() {
        timer?.cancel()
        updateIdleTimerState()
        guard isEnabled, lockCount == 0 else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }

                if self.lockCount > 0 || self.isPlaybackActive {
                    self.resetTimer()
                    return
                }

                let elapsed = Date().timeIntervalSince(self.lastInteractionAt)
                guard elapsed >= self.timeout else {
                    self.resetTimer()
                    return
                }

                self.isScreensaverVisible = true
            }
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func updateIdleTimerState() {
        let shouldDisable = shouldDisableSystemIdleTimer
        guard UIApplication.shared.isIdleTimerDisabled != shouldDisable else { return }
        UIApplication.shared.isIdleTimerDisabled = shouldDisable
    }
}
