import SwiftUI

struct SettingsPluginToolbarScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Toolbar") {
            SettingsListButton(
                icon: "rectangle.topthird.inset.filled",
                heading: "Navbar Position",
                caption: "Where to display the navigation bar",
                trailingText: prefs[UserPreferences.navbarPosition].displayName,
                action: { settingsRouter.navigate(to: .moonfinNavbarPosition) }
            )
            .focused($focusedRoute, equals: .moonfinNavbarPosition)

            SettingsListButton(
                icon: "shuffle",
                heading: "Shuffle Content Type",
                caption: "Default content for shuffle",
                trailingText: prefs[UserPreferences.shuffleContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinShuffleContentType) }
            )
            .focused($focusedRoute, equals: .moonfinShuffleContentType)

            SettingsToggleButton(
                icon: "shuffle",
                heading: "Show Shuffle Button",
                caption: "Show shuffle in toolbar",
                isOn: prefs.binding(for: UserPreferences.showShuffleButton)
            )

            SettingsToggleButton(
                icon: "theatermasks",
                heading: "Show Genres Button",
                caption: "Show genres in toolbar",
                isOn: prefs.binding(for: UserPreferences.showGenresButton)
            )

            SettingsToggleButton(
                icon: "heart.fill",
                heading: "Show Favorites Button",
                caption: "Show favorites in toolbar",
                isOn: prefs.binding(for: UserPreferences.showFavoritesButton)
            )

            SettingsToggleButton(
                icon: "movieclapper.fill",
                heading: "Show Libraries Button",
                caption: "Show libraries in toolbar",
                isOn: prefs.binding(for: UserPreferences.showLibrariesInToolbar)
            )

            SettingsToggleButton(
                icon: "arrow.triangle.merge",
                heading: "Merge Continue Watching & Next Up",
                caption: "Combine into a single row",
                isOn: prefs.binding(for: UserPreferences.mergeContinueWatchingNextUp)
            )

            SettingsToggleButton(
                icon: "folder",
                heading: "Enable Folder View",
                caption: "Show folders button in toolbar",
                isOn: prefs.binding(for: UserPreferences.enableFolderView)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
