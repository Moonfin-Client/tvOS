import SwiftUI

struct SettingsAccountSecurityScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var container: AppContainer
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Account and Security") {
            SettingsListButton(
                icon: "arrow.left.arrow.right",
                heading: "Sort Servers By",
                caption: "Order of servers in the list",
                trailingText: container.authPreferences.sortBy.displayName,
                action: { settingsRouter.navigate(to: .authenticationSortBy) }
            )
            .focused($focusedRoute, equals: .authenticationSortBy)

            SettingsListButton(
                icon: "person.crop.circle.badge.checkmark",
                heading: "Auto Login",
                caption: "Controls how user auto-selection behaves at startup",
                trailingText: container.authPreferences.autoLoginBehavior.displayName,
                action: { settingsRouter.navigate(to: .authenticationAutoSignIn) }
            )
            .focused($focusedRoute, equals: .authenticationAutoSignIn)

            SettingsToggleButton(
                icon: "lock",
                heading: "Always Authenticate",
                caption: "Require password even with a saved token",
                isOn: Binding(
                    get: { container.authPreferences.alwaysAuthenticate },
                    set: { container.authPreferences.alwaysAuthenticate = $0 }
                )
            )

            SettingsListButton(
                icon: "person.crop.circle.badge.checkmark",
                heading: "Authentication",
                caption: "Auto login, sign-in behavior, and stored servers",
                action: { settingsRouter.navigate(to: .authentication) }
            )
            .focused($focusedRoute, equals: .authentication)

            SettingsListButton(
                icon: "lock",
                heading: "PIN Code",
                caption: "Protect access with a device PIN",
                action: { settingsRouter.navigate(to: .authenticationPinCode) }
            )
            .focused($focusedRoute, equals: .authenticationPinCode)

            SettingsListButton(
                icon: "lock.shield",
                heading: "Blocked Ratings",
                caption: "Restrict content by parental rating",
                trailingText: container.parentalControlsRepository.isEnabled ? "Enabled" : "Disabled",
                action: { settingsRouter.navigate(to: .moonfinParentalControls) }
            )
            .focused($focusedRoute, equals: .moonfinParentalControls)

            SettingsToggleButton(
                icon: "rectangle.portrait.and.arrow.right",
                heading: "Confirm Exit",
                caption: "Ask for confirmation before exiting the app",
                isOn: prefs.binding(for: UserPreferences.confirmExit)
            )

            SettingsListButton(
                icon: "questionmark.circle",
                heading: "PIN Code Management",
                caption: "(Placeholder) PIN management actions",
                action: {}
            )
            .disabled(true)

            SettingsListButton(
                icon: "questionmark.circle",
                heading: "Blocked Ratings Checklist",
                caption: "(Placeholder) Dynamic checklist for ratings",
                action: {}
            )
            .disabled(true)
        }
        .restoresFocus($focusedRoute)
    }
}
