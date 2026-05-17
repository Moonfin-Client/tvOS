import SwiftUI

struct SettingsNavigationScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Navigation") {
            SettingsListButton(
                icon: "sidebar.left",
                heading: "Navigation Style",
                caption: "Choose top or left navigation",
                trailingText: prefs[UserPreferences.navbarPosition].displayName,
                action: { settingsRouter.navigate(to: .moonfinNavbarPosition) }
            )
            .focused($focusedRoute, equals: .moonfinNavbarPosition)

            SettingsListButton(
                icon: "paintpalette",
                heading: "Navbar Color",
                caption: "Choose navbar color",
                trailingText: prefs[UserPreferences.navbarColor].displayName,
                action: { settingsRouter.navigate(to: .moonfinNavbarColor) }
            )
            .focused($focusedRoute, equals: .moonfinNavbarColor)

            SettingsListButton(
                icon: "circle.lefthalf.filled.inverse",
                heading: "Navbar Opacity",
                caption: "Set navbar opacity percentage",
                trailingText: "\(prefs[UserPreferences.navbarOpacity])%",
                action: { settingsRouter.navigate(to: .moonfinNavbarOpacity) }
            )
            .focused($focusedRoute, equals: .moonfinNavbarOpacity)

            SettingsToggleButton(
                icon: "shuffle",
                heading: "Show Shuffle Button",
                caption: "Display the shuffle shortcut",
                isOn: prefs.binding(for: UserPreferences.showShuffleButton)
            )

            SettingsListButton(
                icon: "shuffle",
                heading: "Shuffle Content Type Filter",
                caption: "Restrict shuffle to a content type",
                trailingText: prefs[UserPreferences.shuffleContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinShuffleContentType) }
            )
            .focused($focusedRoute, equals: .moonfinShuffleContentType)

            SettingsToggleButton(
                icon: "theatermasks",
                heading: "Show Genres Button",
                caption: "Display the genres shortcut",
                isOn: prefs.binding(for: UserPreferences.showGenresButton)
            )

            SettingsToggleButton(
                icon: "heart.fill",
                heading: "Show Favorites Button",
                caption: "Display the favorites shortcut",
                isOn: prefs.binding(for: UserPreferences.showFavoritesButton)
            )

            SettingsToggleButton(
                icon: "movieclapper.fill",
                heading: "Show Libraries In Toolbar",
                caption: "Display the libraries shortcut",
                isOn: prefs.binding(for: UserPreferences.showLibrariesInToolbar)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
