import SwiftUI

struct SettingsLibrariesScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Libraries") {
            SettingsListButton(
                icon: "eye",
                heading: "Library Visibility",
                caption: "Show or hide libraries in navigation and latest media",
                action: { settingsRouter.navigate(to: .placeholder(title: "Library Visibility")) }
            )

            SettingsToggleButton(
                icon: "folder",
                heading: "Enable Folder View",
                caption: "Show folder browsing mode option",
                isOn: container.userPreferences.binding(for: UserPreferences.enableFolderView)
            )

            SettingsToggleButton(
                icon: "network",
                heading: "Multi-Server Libraries",
                caption: "Aggregate libraries from all servers",
                isOn: container.userPreferences.binding(for: UserPreferences.enableMultiServerLibraries)
            )
        }
        .restoresFocus($focusedRoute)
    }
}
