import SwiftUI

struct SettingsAudioPreferencesScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Audio Preferences") {
            SettingsToggleButton(
                icon: "moon.fill",
                heading: "Night Mode",
                caption: "Compress dynamic range for quieter playback",
                isOn: prefs.binding(for: UserPreferences.audioNightMode)
            )

            SettingsListButton(
                icon: "globe",
                heading: "Default Audio Language",
                caption: "Preferred audio language",
                trailingText: prefs[UserPreferences.defaultAudioLanguage].displayName,
                action: { settingsRouter.navigate(to: .playbackDefaultAudioLanguage) }
            )
            .focused($focusedRoute, equals: .playbackDefaultAudioLanguage)

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Audio Behavior",
                caption: "Choose how audio output is handled",
                trailingText: prefs[UserPreferences.audioBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioBehavior) }
            )
            .focused($focusedRoute, equals: .playbackAudioBehavior)

            SettingsListButton(
                icon: "airplayaudio",
                heading: "Audio Output",
                caption: "Direct stream, passthrough, or stereo downmix",
                trailingText: prefs[UserPreferences.audioOutput].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioOutput) }
            )
            .focused($focusedRoute, equals: .playbackAudioOutput)

            SettingsToggleButton(
                icon: "speaker",
                heading: "AC3 Passthrough",
                caption: "Enable AC3 passthrough",
                isOn: prefs.binding(for: UserPreferences.ac3Enabled)
            )

            SettingsToggleButton(
                icon: "waveform.path.ecg",
                heading: "TrueHD Support",
                caption: "Enable TrueHD support",
                isOn: prefs.binding(for: UserPreferences.trueHdEnabled)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
