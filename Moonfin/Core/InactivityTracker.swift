import SwiftUI
import UIKit

@MainActor
final class InactivityTracker: ObservableObject {

    @Published private(set) var isScreensaverVisible = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = isScreensaverVisible
        }
    }

    private let userPreferences: UserPreferences
    private weak var playbackCoordinator: PlaybackCoordinator?
    private var timer: DispatchWorkItem?
    private var lockCount = 0

    init(userPreferences: UserPreferences, playbackCoordinator: PlaybackCoordinator) {
        self.userPreferences = userPreferences
        self.playbackCoordinator = playbackCoordinator
        resetTimer()
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

    func notifyInteraction() {
        timer?.cancel()
        if isScreensaverVisible {
            isScreensaverVisible = false
        }
        resetTimer()
    }

    func addLock() {
        lockCount += 1
        timer?.cancel()
    }

    func removeLock() {
        lockCount = max(0, lockCount - 1)
        if lockCount == 0 {
            resetTimer()
        }
    }

    private func resetTimer() {
        timer?.cancel()
        guard isEnabled, lockCount == 0 else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, self.lockCount == 0, !self.isPlaybackActive else { return }
                self.isScreensaverVisible = true
            }
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }
}
