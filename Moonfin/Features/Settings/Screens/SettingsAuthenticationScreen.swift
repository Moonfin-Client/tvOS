import SwiftUI

struct SettingsAuthenticationScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    private var authPrefs: AuthenticationPreferences { container.authPreferences }
    private var servers: [Server] { container.serverRepository.storedServers.value }

    var body: some View {
        SettingsScreenLayout(title: "Authentication") {
            SettingsListButton(
                icon: "arrow.left.arrow.right",
                heading: "Sort Servers By",
                caption: "Order of servers in the list",
                trailingText: authPrefs.sortBy.displayName,
                action: { settingsRouter.navigate(to: .authenticationSortBy) }
            )
            .focused($focusedRoute, equals: .authenticationSortBy)

            SettingsListButton(
                icon: "person.crop.circle.badge.checkmark",
                heading: "Auto Sign In",
                caption: "Automatically sign in on launch",
                trailingText: authPrefs.autoLoginBehavior.displayName,
                action: { settingsRouter.navigate(to: .authenticationAutoSignIn) }
            )
            .focused($focusedRoute, equals: .authenticationAutoSignIn)

            SettingsToggleButton(
                icon: "lock",
                heading: "Always Authenticate",
                caption: "Require authentication every launch",
                isOn: Binding(
                    get: { authPrefs.alwaysAuthenticate },
                    set: { authPrefs.alwaysAuthenticate = $0 }
                )
            )

            if !servers.isEmpty {
                Divider()
                    .background(theme.colorScheme.listCaption.opacity(0.3))
                    .padding(.vertical, SpaceTokens.spaceXs)

                Text("Servers")
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .padding(.bottom, SpaceTokens.space2xs)

                ForEach(servers) { server in
                    SettingsListButton(
                        icon: server.serverType == .jellyfin ? "server.rack" : "tv",
                        heading: server.name,
                        caption: server.address,
                        action: { settingsRouter.navigate(to: .authenticationServer(serverId: server.id.uuidString)) }
                    )
                    .focused($focusedRoute, equals: .authenticationServer(serverId: server.id.uuidString))
                }
            }
        }
        .restoresFocus($focusedRoute)
    }
}
