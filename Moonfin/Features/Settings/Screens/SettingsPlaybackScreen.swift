import SwiftUI

struct SettingsPlaybackScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

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
                icon: "speaker.wave.2",
                heading: "Audio Behavior",
                caption: "Audio track selection",
                trailingText: prefs[UserPreferences.audioBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioBehavior) }
            )

            SettingsListButton(
                icon: "speedometer",
                heading: "Max Bitrate",
                caption: "Limit streaming quality",
                action: { settingsRouter.navigate(to: .playbackMaxBitrate) }
            )
        }
    }
}
