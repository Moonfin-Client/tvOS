import SwiftUI

struct SettingsMoonfinScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Moonfin") {
            SettingsListButton(
                icon: "rectangle.topthird.inset.filled",
                heading: "Navbar Position",
                caption: "Where to display the navigation bar",
                trailingText: prefs[UserPreferences.navbarPosition].displayName,
                action: { settingsRouter.navigate(to: .moonfinNavbarPosition) }
            )

            SettingsListButton(
                icon: "shuffle",
                heading: "Shuffle Content Type",
                caption: "Default content for shuffle",
                trailingText: prefs[UserPreferences.shuffleContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinShuffleContentType) }
            )

            SettingsToggleButton(
                icon: "photo.artframe",
                heading: "Backdrop",
                caption: "Show background images",
                isOn: prefs.binding(for: UserPreferences.backdropEnabled)
            )
        }
    }
}
