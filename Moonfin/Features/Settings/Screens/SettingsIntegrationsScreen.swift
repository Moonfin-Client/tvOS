import SwiftUI

struct SettingsIntegrationsScreen: View {
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Integrations") {
            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .plugin,
                icon: "puzzlepiece.extension",
                heading: "Plugin",
                caption: "Plugin sync status and settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .integrationsMetadataRatings,
                icon: "star.fill",
                heading: "Metadata and Ratings",
                caption: "Additional rating provider settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .seerr,
                icon: "film",
                heading: "Seerr",
                caption: "Seerr integration settings"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .homeSections,
                icon: "rectangle.3.group",
                heading: "Home Screen Sections",
                caption: "Integration status and linked sections"
            )
        }
        .restoresFocus($focusedRoute)
    }
}
