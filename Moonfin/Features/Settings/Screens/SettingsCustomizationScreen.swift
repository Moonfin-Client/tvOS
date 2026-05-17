import SwiftUI

struct SettingsCustomizationScreen: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Customization") {
            SettingsListButton(
                icon: "paintpalette",
                heading: "Appearance Theme",
                caption: "Select your app appearance theme",
                trailingText: theme.activeSpec.displayName,
                action: { settingsRouter.navigate(to: .customizationAppearanceTheme) }
            )
            .focused($focusedRoute, equals: .customizationAppearanceTheme)

            SettingsListButton(
                icon: "circle.lefthalf.filled",
                heading: "Focus Border Color",
                caption: "Color of the focus indicator",
                trailingText: theme.focusBorder.displayName,
                action: { settingsRouter.navigate(to: .customizationFocusBorder) }
            )
            .focused($focusedRoute, equals: .customizationFocusBorder)

            SettingsListButton(
                icon: "clock",
                heading: "Clock",
                caption: "When to show the clock",
                trailingText: prefs[UserPreferences.clockBehavior].displayName,
                action: { settingsRouter.navigate(to: .customizationClock) }
            )
            .focused($focusedRoute, equals: .customizationClock)

            SettingsListButton(
                icon: "checkmark.circle",
                heading: "Watched Indicator",
                caption: "When to show watched status",
                trailingText: prefs[UserPreferences.watchedIndicator].displayName,
                action: { settingsRouter.navigate(to: .customizationWatchedIndicator) }
            )
            .focused($focusedRoute, equals: .customizationWatchedIndicator)

            SettingsListButton(
                icon: "captions.bubble",
                heading: "Subtitles",
                caption: "Appearance and defaults",
                action: { settingsRouter.navigate(to: .customizationSubtitles) }
            )
            .focused($focusedRoute, equals: .customizationSubtitles)

            SettingsListButton(
                icon: "books.vertical",
                heading: "Libraries",
                caption: "Per-library display settings",
                action: { settingsRouter.navigate(to: .libraries) }
            )
            .focused($focusedRoute, equals: .libraries)
        }
        .restoresFocus($focusedRoute)
    }
}
