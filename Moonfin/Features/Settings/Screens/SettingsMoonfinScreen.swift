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

            SettingsListButton(
                icon: "number",
                heading: "Media Bar Items",
                caption: "Number of slides",
                trailingText: prefs[UserPreferences.mediaBarItemCount].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarItemCount) }
            )

            SettingsListButton(
                icon: "circle.lefthalf.filled.inverse",
                heading: "Media Bar Overlay",
                caption: "Overlay opacity",
                trailingText: "\(prefs[UserPreferences.mediaBarOverlayOpacity])%",
                action: { settingsRouter.navigate(to: .moonfinMediaBarOpacity) }
            )

            SettingsListButton(
                icon: "paintpalette",
                heading: "Media Bar Color",
                caption: "Overlay color",
                trailingText: prefs[UserPreferences.mediaBarOverlayColor].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarColor) }
            )
        }
    }
}
