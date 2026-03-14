import Foundation
import Combine

enum NextUpPromptState: Equatable {
    case hidden
    case nextUp(remaining: Int)
    case stillWatching
}

@MainActor
final class NextUpManager: ObservableObject {
    @Published private(set) var promptState: NextUpPromptState = .hidden

    private let preferences: UserPreferences
    private var countdownTask: Task<Void, Never>?
    private var countdownRemaining: Int = 0
    private var lastStillWatchingEpisodeCount: Int = -1

    private var countdownDuration: Int {
        preferences[UserPreferences.nextUpTimeout]
    }
    private let creditsThresholdSeconds: TimeInterval = 120

    var onPlayNext: (() async -> Void)?
    var onDismiss: (() -> Void)?

    init(preferences: UserPreferences) {
        self.preferences = preferences
    }

    func evaluateEndOfPlayback(
        currentTime: TimeInterval,
        duration: TimeInterval,
        hasNext: Bool,
        episodesPlayed: Int
    ) {
        guard promptState == .hidden else { return }
        guard duration > 0, hasNext else { return }

        let behavior = preferences[UserPreferences.nextUpBehavior]
        guard behavior != .disabled else { return }

        let threshold = preferences[UserPreferences.stillWatchingThreshold]
        if threshold > 0, episodesPlayed > 0,
           episodesPlayed % threshold == 0,
           episodesPlayed != lastStillWatchingEpisodeCount {
            lastStillWatchingEpisodeCount = episodesPlayed
            promptState = .stillWatching
            return
        }

        let remaining = duration - currentTime
        let triggerAt: TimeInterval = behavior == .extended ? creditsThresholdSeconds : 30

        guard countdownDuration > 0 else { return }

        if remaining <= triggerAt && remaining > 0 {
            startNextUpCountdown(seconds: min(Int(remaining), countdownDuration))
        }
    }

    func confirmPlayNext() {
        cancelCountdown()
        promptState = .hidden
        Task { await onPlayNext?() }
    }

    func dismiss() {
        cancelCountdown()
        promptState = .hidden
        onDismiss?()
    }

    func confirmStillWatching() {
        promptState = .hidden
    }

    func reset() {
        cancelCountdown()
        promptState = .hidden
    }

    func resetForNewQueue() {
        reset()
        lastStillWatchingEpisodeCount = -1
    }

    private func startNextUpCountdown(seconds: Int) {
        countdownRemaining = seconds
        promptState = .nextUp(remaining: countdownRemaining)

        countdownTask = Task {
            while countdownRemaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                countdownRemaining -= 1
                promptState = .nextUp(remaining: countdownRemaining)
            }

            guard !Task.isCancelled else { return }
            promptState = .hidden
            await onPlayNext?()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }
}
