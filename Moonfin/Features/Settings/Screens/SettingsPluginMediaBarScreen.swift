import SwiftUI

struct SettingsPluginMediaBarScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Media Bar") {
            SettingsToggleButton(
                icon: "rectangle.inset.filled",
                heading: "Media Bar",
                caption: "Featured slideshow on home screen",
                isOn: prefs.binding(for: UserPreferences.mediaBarEnabled)
            )

            SettingsListButton(
                icon: "film.stack",
                heading: "Media Bar Content",
                caption: "What to show in the media bar",
                trailingText: prefs[UserPreferences.mediaBarContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarContentType) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarContentType)

            SettingsListButton(
                icon: "number",
                heading: "Media Bar Items",
                caption: "Number of slides",
                trailingText: prefs[UserPreferences.mediaBarItemCount].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarItemCount) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarItemCount)

            SettingsListButton(
                icon: "circle.lefthalf.filled.inverse",
                heading: "Media Bar Overlay",
                caption: "Overlay opacity",
                trailingText: "\(prefs[UserPreferences.mediaBarOverlayOpacity])%",
                action: { settingsRouter.navigate(to: .moonfinMediaBarOpacity) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarOpacity)

            SettingsListButton(
                icon: "paintpalette",
                heading: "Media Bar Color",
                caption: "Overlay color",
                trailingText: prefs[UserPreferences.mediaBarOverlayColor].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarColor) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarColor)

            SettingsToggleButton(
                icon: "play.rectangle",
                heading: "Trailer Preview",
                caption: "Play trailers in media bar",
                isOn: prefs.binding(for: UserPreferences.mediaBarTrailerPreview)
            )

            SettingsToggleButton(
                icon: "speaker.wave.2",
                heading: "Trailer Audio",
                caption: "Play audio in media bar trailers",
                isOn: prefs.binding(for: UserPreferences.mediaBarTrailerAudio)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
