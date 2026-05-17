import SwiftUI

struct SettingsDynamicLocalPreviewsScreen: View {
    @EnvironmentObject var container: AppContainer

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Local Previews") {
            SettingsToggleButton(
                icon: "play.rectangle.on.rectangle",
                heading: "Trailer Preview",
                caption: "Automatically play trailer previews",
                isOn: prefs.binding(for: UserPreferences.mediaBarTrailerPreview)
            )

            SettingsToggleButton(
                icon: "tv",
                heading: "Media Preview",
                caption: "Enable media previews in browse surfaces",
                isOn: prefs.binding(for: UserPreferences.mediaPreviewEnabled)
            )

            SettingsToggleButton(
                icon: "speaker.wave.2",
                heading: "Preview Audio",
                caption: "Enable audio while previews are playing",
                isOn: prefs.binding(for: UserPreferences.previewAudioEnabled)
            )
        }
    }
}

struct SettingsDynamicSeasonalEffectsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Seasonal Effects") {
            SettingsListButton(
                icon: "sparkles",
                heading: "Seasonal Surprise",
                caption: "Select seasonal visual overlay effect",
                trailingText: prefs[UserPreferences.seasonalSurprise].displayName,
                action: { settingsRouter.navigate(to: .moonfinSeasonalSurprise) }
            )
            .focused($focusedRoute, equals: .moonfinSeasonalSurprise)
        }
        .restoresFocus($focusedRoute)
    }
}
