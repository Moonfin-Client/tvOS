import SwiftUI

struct SettingsScreensaverScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Screensaver") {
            SettingsListButton(
                icon: "wand.and.stars",
                heading: "Mode",
                caption: "Screensaver display mode",
                trailingText: prefs[UserPreferences.screensaverMode].displayName,
                action: { settingsRouter.navigate(to: .customizationScreensaverMode) }
            )

            SettingsListButton(
                icon: "timer",
                heading: "Timeout",
                caption: "Minutes before screensaver activates",
                trailingText: "\(prefs[UserPreferences.screensaverTimeout]) min",
                action: { settingsRouter.navigate(to: .customizationScreensaverTimeout) }
            )
        }
    }
}
