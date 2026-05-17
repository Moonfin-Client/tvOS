import SwiftUI

struct SettingsPersonalizationScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Personalization") {
            SettingsListButton(
                icon: "paintbrush.pointed",
                heading: "General Style",
                caption: "Theme, focus, clock, backdrops, and theme music",
                action: { settingsRouter.navigate(to: .personalizationGeneralStyle) }
            )
            .focused($focusedRoute, equals: .personalizationGeneralStyle)

            SettingsListButton(
                icon: "sidebar.left",
                heading: "Navigation",
                caption: "Navbar layout, toolbar buttons, and navigation shortcuts",
                action: { settingsRouter.navigate(to: .personalizationNavigation) }
            )
            .focused($focusedRoute, equals: .personalizationNavigation)

            SettingsListButton(
                icon: "house",
                heading: "Home Screen",
                caption: "Rows, poster size, image type, and home behavior",
                action: { settingsRouter.navigate(to: .home) }
            )
            .focused($focusedRoute, equals: .home)

            SettingsListButton(
                icon: "books.vertical",
                heading: "Libraries",
                caption: "Library visibility and display settings",
                action: { settingsRouter.navigate(to: .libraries) }
            )
            .focused($focusedRoute, equals: .libraries)
        }
        .restoresFocus($focusedRoute)
    }
}
