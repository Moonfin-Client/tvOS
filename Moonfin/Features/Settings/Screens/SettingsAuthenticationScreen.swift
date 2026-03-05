import SwiftUI

struct SettingsAuthenticationScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var authPrefs: AuthenticationPreferences { container.authPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Authentication") {
            SettingsListButton(
                icon: "arrow.left.arrow.right",
                heading: "Sort Servers By",
                caption: "Order of servers in the list",
                trailingText: authPrefs.sortBy.displayName,
                action: { settingsRouter.navigate(to: .authenticationSortBy) }
            )

            SettingsListButton(
                icon: "person.crop.circle.badge.checkmark",
                heading: "Auto Sign In",
                caption: "Automatically sign in on launch",
                trailingText: authPrefs.autoLoginBehavior.displayName,
                action: { settingsRouter.navigate(to: .authenticationAutoSignIn) }
            )

            SettingsToggleButton(
                icon: "lock",
                heading: "Always Authenticate",
                caption: "Require authentication every launch",
                isOn: Binding(
                    get: { authPrefs.alwaysAuthenticate },
                    set: { authPrefs.alwaysAuthenticate = $0 }
                )
            )
        }
    }
}
