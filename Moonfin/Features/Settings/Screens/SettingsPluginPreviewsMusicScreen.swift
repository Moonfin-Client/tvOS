import SwiftUI

struct SettingsPluginPreviewsMusicScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Previews & Music") {
            SettingsToggleButton(
                icon: "tv",
                heading: "Media Preview",
                caption: "Show media previews on home rows",
                isOn: prefs.binding(for: UserPreferences.mediaPreviewEnabled)
            )

            SettingsToggleButton(
                icon: "speaker.wave.1",
                heading: "Preview Audio",
                caption: "Play audio during previews",
                isOn: prefs.binding(for: UserPreferences.previewAudioEnabled)
            )

            SettingsToggleButton(
                icon: "music.note",
                heading: "Theme Music",
                caption: "Play theme music on detail screens",
                isOn: prefs.binding(for: UserPreferences.themeMusicEnabled)
            )

            SettingsToggleButton(
                icon: "music.note.house",
                heading: "Theme Music on Home Rows",
                caption: "Play when browsing home rows",
                isOn: prefs.binding(for: UserPreferences.themeMusicOnHomeRows)
            )

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Theme Music Volume",
                caption: "Playback volume",
                trailingText: "\(prefs[UserPreferences.themeMusicVolume])%",
                action: { settingsRouter.navigate(to: .moonfinThemeMusicVolume) }
            )
            .focused($focusedRoute, equals: .moonfinThemeMusicVolume)
        }
        .restoresFocus($focusedRoute)
    }
}
