import SwiftUI

struct SettingsPluginBackgroundsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Backgrounds") {
            SettingsToggleButton(
                icon: "photo.artframe",
                heading: "Backdrop",
                caption: "Show background images",
                isOn: prefs.binding(for: UserPreferences.backdropEnabled)
            )

            SettingsListButton(
                icon: "aqi.medium",
                heading: "Details Background Blur",
                caption: "Blur amount on detail screens",
                trailingText: "\(prefs[UserPreferences.detailsBackgroundBlur])",
                action: { settingsRouter.navigate(to: .moonfinDetailsBlur) }
            )
            .focused($focusedRoute, equals: .moonfinDetailsBlur)

            SettingsListButton(
                icon: "aqi.low",
                heading: "Browsing Background Blur",
                caption: "Blur amount when browsing",
                trailingText: "\(prefs[UserPreferences.browsingBackgroundBlur])",
                action: { settingsRouter.navigate(to: .moonfinBrowsingBlur) }
            )
            .focused($focusedRoute, equals: .moonfinBrowsingBlur)

            SettingsListButton(
                icon: "sparkles",
                heading: "Seasonal Surprise",
                caption: "Decorative seasonal animations",
                trailingText: prefs[UserPreferences.seasonalSurprise].displayName,
                action: { settingsRouter.navigate(to: .moonfinSeasonalSurprise) }
            )
            .focused($focusedRoute, equals: .moonfinSeasonalSurprise)
        }
        .restoresFocus($focusedRoute)
    }
}
