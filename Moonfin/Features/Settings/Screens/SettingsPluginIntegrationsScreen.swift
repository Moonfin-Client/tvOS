import SwiftUI

struct SettingsPluginIntegrationsScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }
    private var pluginEnabled: Bool { prefs[UserPreferences.pluginSyncEnabled] }

    var body: some View {
        SettingsScreenLayout(title: "Integrations") {
            SettingsListButton(
                icon: "film",
                heading: "Seerr",
                caption: "Media request management",
                trailingText: container.seerrRepository.isAvailable.value ? "On" : "Off",
                action: { settingsRouter.navigate(to: .seerr) }
            )
            .focused($focusedRoute, equals: .seerr)

            SettingsToggleButton(
                icon: "server.rack",
                heading: "Multi-Server",
                caption: "Aggregate content from all logged-in servers",
                isOn: prefs.binding(for: UserPreferences.enableMultiServerLibraries)
            )

            if pluginEnabled {
                SettingsToggleButton(
                    icon: "star.fill",
                    heading: "Additional Ratings",
                    caption: "Show MDBList ratings on media bar",
                    isOn: prefs.binding(for: UserPreferences.enableAdditionalRatings)
                )

                SettingsToggleButton(
                    icon: "tv",
                    heading: "Episode Ratings",
                    caption: "Show TMDB episode ratings",
                    isOn: prefs.binding(for: UserPreferences.enableEpisodeRatings)
                )

                SettingsToggleButton(
                    icon: "textformat",
                    heading: "Rating Labels",
                    caption: "Show text labels next to rating icons",
                    isOn: prefs.binding(for: UserPreferences.showRatingLabels)
                )
            }
        }
        .restoresFocus($focusedRoute)
    }
}
