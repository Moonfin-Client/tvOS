import SwiftUI

struct SettingsGeneralStyleScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "General Style") {
            SettingsListButton(
                icon: "paintpalette",
                heading: "Appearance Theme",
                caption: "Select your app appearance theme",
                action: { settingsRouter.navigate(to: .placeholder(title: "Appearance Theme")) }
            )

            SettingsListButton(
                icon: "circle.lefthalf.filled",
                heading: "Focus Border Color",
                caption: "Adjust the focus highlight color",
                action: { settingsRouter.navigate(to: .customizationTheme) }
            )
            .focused($focusedRoute, equals: .customizationTheme)

            SettingsListButton(
                icon: "clock",
                heading: "Clock Display",
                caption: "Choose when the clock appears",
                action: { settingsRouter.navigate(to: .customizationClock) }
            )
            .focused($focusedRoute, equals: .customizationClock)

            SettingsToggleButton(
                icon: "calendar.badge.clock",
                heading: "24-Hour Clock",
                caption: "Use 24-hour time formatting",
                isOn: prefs.binding(for: UserPreferences.use24HourClock)
            )

            SettingsToggleButton(
                icon: "viewfinder.circle",
                heading: "Focus Expansion Animation",
                caption: "Scale focused cards for emphasis",
                isOn: prefs.binding(for: UserPreferences.cardFocusExpansion)
            )

            SettingsToggleButton(
                icon: "photo.artframe",
                heading: "Background Backdrops",
                caption: "Enable backdrop images in browsing and detail views",
                isOn: prefs.binding(for: UserPreferences.backdropEnabled)
            )

            SettingsListButton(
                icon: "aqi.low",
                heading: "Browsing Background Blur",
                caption: "Adjust blur while browsing",
                action: { settingsRouter.navigate(to: .moonfinBrowsingBlur) }
            )
            .focused($focusedRoute, equals: .moonfinBrowsingBlur)

            SettingsListButton(
                icon: "aqi.medium",
                heading: "Details Background Blur",
                caption: "Adjust blur on detail screens",
                action: { settingsRouter.navigate(to: .moonfinDetailsBlur) }
            )
            .focused($focusedRoute, equals: .moonfinDetailsBlur)

            SettingsListButton(
                icon: "checkmark.circle",
                heading: "Watched Indicators",
                caption: "Choose how watched state is shown",
                action: { settingsRouter.navigate(to: .customizationWatchedIndicator) }
            )
            .focused($focusedRoute, equals: .customizationWatchedIndicator)


            SettingsToggleButton(
                icon: "music.note",
                heading: "Theme Music",
                caption: "Play theme music on detail screens",
                isOn: prefs.binding(for: UserPreferences.themeMusicEnabled)
            )

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Theme Music Volume",
                caption: "Adjust theme music volume",
                action: { settingsRouter.navigate(to: .moonfinThemeMusicVolume) }
            )
            .focused($focusedRoute, equals: .moonfinThemeMusicVolume)
        }
        .restoresFocus($focusedRoute)
    }
}
