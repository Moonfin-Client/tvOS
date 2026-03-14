import SwiftUI

struct SettingsPlaybackScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    private var stillWatchingLabel: String {
        let val = prefs[UserPreferences.stillWatchingThreshold]
        return val > 0 ? "\(val) episodes" : "Disabled"
    }

    private var supportsMediaSegments: Bool {
        container.serverRepository.currentServer.value?.serverType.supports(.mediaSegments) == true
    }

    private var bitrateLabel: String {
        let value = prefs[UserPreferences.maxBitrate]
        if value == 0 { return "Auto" }
        if value >= 1_000_000 {
            let mbps = Double(value) / 1_000_000.0
            return mbps.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(mbps)) Mbps"
                : String(format: "%.1f Mbps", mbps)
        }
        let kbps = Double(value) / 1_000.0
        return String(format: "%.0f Kbps", kbps)
    }

    var body: some View {
        SettingsScreenLayout(title: "Playback") {
            SettingsListButton(
                icon: "forward.end",
                heading: "Next Up Behavior",
                caption: "How next up is displayed",
                trailingText: prefs[UserPreferences.nextUpBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackNextUpBehavior) }
            )

            SettingsListButton(
                icon: "pause.circle",
                heading: "Still Watching Prompt",
                caption: "Ask after N episodes",
                trailingText: stillWatchingLabel,
                action: { settingsRouter.navigate(to: .playbackInactivityPrompt) }
            )

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Audio Behavior",
                caption: "Audio track selection",
                trailingText: prefs[UserPreferences.audioBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioBehavior) }
            )

            SettingsListButton(
                icon: "speaker.wave.1",
                heading: "Audio Output",
                caption: "Surround sound handling",
                trailingText: prefs[UserPreferences.audioOutput].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioOutput) }
            )

            SettingsListButton(
                icon: "speedometer",
                heading: "Max Bitrate",
                caption: "Limit streaming quality",
                trailingText: bitrateLabel,
                action: { settingsRouter.navigate(to: .playbackMaxBitrate) }
            )

            SettingsListButton(
                icon: "photo.on.rectangle",
                heading: "Slideshow Interval",
                caption: "Time between photos",
                trailingText: prefs[UserPreferences.photoSlideshowInterval].displayName,
                action: { settingsRouter.navigate(to: .playbackSlideshowInterval) }
            )

            if supportsMediaSegments {
                SettingsListButton(
                    icon: "scissors",
                    heading: "Media Segments",
                    caption: "Skip intros, outros, and more",
                    action: { settingsRouter.navigate(to: .playbackMediaSegments) }
                )
            }
        }
    }
}
