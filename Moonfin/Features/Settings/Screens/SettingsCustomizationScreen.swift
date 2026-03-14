import SwiftUI

struct SettingsCustomizationScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Customization") {
            SettingsListButton(
                icon: "circle.lefthalf.filled",
                heading: "Focus Border Color",
                caption: "Color of the focus indicator",
                trailingText: theme.focusBorder.displayName,
                action: { settingsRouter.navigate(to: .customizationTheme) }
            )

            SettingsListButton(
                icon: "clock",
                heading: "Clock",
                caption: "When to show the clock",
                trailingText: prefs[UserPreferences.clockBehavior].displayName,
                action: { settingsRouter.navigate(to: .customizationClock) }
            )

            SettingsListButton(
                icon: "checkmark.circle",
                heading: "Watched Indicator",
                caption: "When to show watched status",
                trailingText: prefs[UserPreferences.watchedIndicator].displayName,
                action: { settingsRouter.navigate(to: .customizationWatchedIndicator) }
            )

            SettingsListButton(
                icon: "captions.bubble",
                heading: "Subtitles",
                caption: "Appearance and defaults",
                action: { settingsRouter.navigate(to: .customizationSubtitles) }
            )

            SettingsListButton(
                icon: "books.vertical",
                heading: "Libraries",
                caption: "Per-library display settings",
                action: { settingsRouter.navigate(to: .libraries) }
            )
        }
    }
}
