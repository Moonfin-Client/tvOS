import SwiftUI

struct SettingsPluginMediaBarScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var isMediaBarDisabled: Bool {
        prefs[UserPreferences.mediaBarMode] == .off
    }

    var body: some View {
        SettingsScreenLayout(title: "Media Bar") {
            SettingsListButton(
                icon: "switch.2",
                heading: "Media Bar Style",
                caption: "Choose media bar style or turn off",
                trailingText: prefs[UserPreferences.mediaBarMode].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarMode) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarMode)

            if !isMediaBarDisabled {
            SettingsListButton(
                icon: "film.stack",
                heading: "Content Type",
                caption: "What to show in the media bar",
                trailingText: prefs[UserPreferences.mediaBarContentType] == .both ? "Movies & TV Shows" : prefs[UserPreferences.mediaBarContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarContentType) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarContentType)

            SettingsListButton(
                icon: "number",
                heading: "Item Count",
                caption: "Number of media bar items",
                trailingText: prefs[UserPreferences.mediaBarItemCount].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarItemCount) }
            )
            .focused($focusedRoute, equals: .moonfinMediaBarItemCount)

            SettingsListButton(
                icon: "film",
                heading: "Source Libraries",
                caption: "Select libraries used as media bar sources",
                trailingText: selectedCountLabel(prefs[UserPreferences.mediaBarLibraryIds]),
                action: { settingsRouter.navigate(to: .dynamicContentMediaBarSourceLibraries) }
            )
            .focused($focusedRoute, equals: .dynamicContentMediaBarSourceLibraries)

            SettingsListButton(
                icon: "square.stack.3d.up",
                heading: "Source Collections",
                caption: "Select collections used as media bar sources",
                trailingText: selectedCountLabel(prefs[UserPreferences.mediaBarCollectionIds]),
                action: { settingsRouter.navigate(to: .dynamicContentMediaBarSourceCollections) }
            )
            .focused($focusedRoute, equals: .dynamicContentMediaBarSourceCollections)

            SettingsListButton(
                icon: "tag.slash",
                heading: "Excluded Genres",
                caption: "Exclude genres from media bar items",
                trailingText: selectedCountLabel(prefs[UserPreferences.mediaBarExcludedGenres]),
                action: { settingsRouter.navigate(to: .dynamicContentMediaBarExcludedGenres) }
            )
            .focused($focusedRoute, equals: .dynamicContentMediaBarExcludedGenres)

            SettingsToggleButton(
                icon: "play.fill",
                heading: "Auto Advance",
                caption: "Automatically advance media bar slides",
                isOn: prefs.binding(for: UserPreferences.mediaBarAutoAdvance)
            )

            if prefs[UserPreferences.mediaBarAutoAdvance] {
                SettingsListButton(
                    icon: "timer",
                    heading: "Auto Advance Interval",
                    caption: "Time between slide advances",
                    trailingText: "\(prefs[UserPreferences.mediaBarIntervalMs]) ms",
                    action: { settingsRouter.navigate(to: .moonfinMediaBarInterval) }
                )
                .focused($focusedRoute, equals: .moonfinMediaBarInterval)
            }

            SettingsToggleButton(
                icon: "speaker.wave.2.fill",
                heading: "Trailer Audio",
                caption: "Play audio during media bar trailer previews",
                isOn: prefs.binding(for: UserPreferences.mediaBarTrailerAudio)
            )

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
            }

        }
        .restoresFocus($focusedRoute)
    }

    private func selectedCountLabel(_ ids: [String]) -> String {
        ids.isEmpty ? "All" : "\(ids.count) selected"
    }
}
