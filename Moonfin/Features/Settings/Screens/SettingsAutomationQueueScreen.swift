import SwiftUI

struct SettingsAutomationQueueScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Automation and Queue") {
            SettingsToggleButton(
                icon: "film.stack",
                heading: "Cinema Mode",
                caption: "Enable cinema mode automation",
                isOn: prefs.binding(for: UserPreferences.cinemaModeEnabled)
            )

            SettingsToggleButton(
                icon: "list.bullet.rectangle",
                heading: "Media Queuing",
                caption: "Auto-queue upcoming media",
                isOn: prefs.binding(for: UserPreferences.mediaQueuingEnabled)
            )

            SettingsListButton(
                icon: "forward.end",
                heading: "Next Up Display",
                caption: "Choose how the Next Up overlay behaves",
                trailingText: prefs[UserPreferences.nextUpBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackNextUpBehavior) }
            )
            .focused($focusedRoute, equals: .playbackNextUpBehavior)

            SettingsListButton(
                icon: "timer",
                heading: "Next Up Timeout",
                caption: "Control how long the Next Up prompt stays visible",
                trailingText: "\(prefs[UserPreferences.nextUpTimeout])s",
                action: { settingsRouter.navigate(to: .playbackNextUpTimeout) }
            )
            .focused($focusedRoute, equals: .playbackNextUpTimeout)

            SettingsListButton(
                icon: "pause.circle",
                heading: "Still Watching Prompt",
                caption: "Choose when playback asks if you are still watching",
                action: { settingsRouter.navigate(to: .playbackInactivityPrompt) }
            )
            .focused($focusedRoute, equals: .playbackInactivityPrompt)
        }
        .restoresFocus($focusedRoute)
    }
}
