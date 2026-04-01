import Foundation

enum PlaybackRolloutPolicy {
    static func resolve(
        requested: PlaybackPlayerBackend,
        stage: PlaybackMpvCanaryStage,
        localKillSwitch: Bool
    ) -> PlaybackBackendSupport.Resolution {
        _ = stage
        _ = localKillSwitch
        return PlaybackBackendSupport.resolve(for: requested)
    }

    static func effectiveRequestedDirective(
        requested: PlaybackPlayerBackend,
        stage: PlaybackMpvCanaryStage,
        localKillSwitch: Bool
    ) -> PlaybackBackendDirective {
        let resolution = resolve(requested: requested, stage: stage, localKillSwitch: localKillSwitch)
        return resolution.active == .mpv ? .mpv : .tvvlcKit
    }
}
