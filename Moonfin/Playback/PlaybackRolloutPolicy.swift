import Foundation

enum PlaybackRolloutPolicy {
    static func resolve(
        requested: PlaybackPlayerBackend,
        stage: PlaybackMpvCanaryStage,
        localKillSwitch: Bool
    ) -> PlaybackBackendSupport.Resolution {
        PlaybackBackendSupport.resolve(for: requested)
    }

    static func effectiveRequestedDirective(
        requested: PlaybackPlayerBackend,
        stage: PlaybackMpvCanaryStage,
        localKillSwitch: Bool
    ) -> PlaybackBackendDirective {
        .mpv
    }
}
