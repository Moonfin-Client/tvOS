import SwiftUI

struct SettingsScreensaverScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Screensaver") {
            SettingsToggleButton(
                icon: "moon.fill",
                heading: "Enabled",
                caption: "Show screensaver after inactivity",
                isOn: Binding(
                    get: { prefs[UserPreferences.screensaverEnabled] },
                    set: { prefs[UserPreferences.screensaverEnabled] = $0 }
                )
            )

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

            SettingsListButton(
                icon: "circle.lefthalf.filled",
                heading: "Dimming",
                caption: "Overlay darkness level",
                trailingText: dimmingCaption,
                action: { settingsRouter.navigate(to: .customizationScreensaverDimming) }
            )

            SettingsToggleButton(
                icon: "clock",
                heading: "Show Clock",
                caption: "Display bouncing clock on screensaver",
                isOn: Binding(
                    get: { prefs[UserPreferences.screensaverShowClock] },
                    set: { prefs[UserPreferences.screensaverShowClock] = $0 }
                )
            )
        }
    }

    private var dimmingCaption: String {
        let level = prefs[UserPreferences.screensaverDimmingLevel]
        return level == 0 ? "Off" : "\(level)%"
    }
}

struct SettingsScreensaverTimeoutScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var current: Int { container.userPreferences[UserPreferences.screensaverTimeout] }
    private let options: [(Int, String)] = [
        (1, "1 minute"), (2, "2 minutes"), (3, "3 minutes"),
        (5, "5 minutes"), (10, "10 minutes"), (15, "15 minutes"), (30, "30 minutes"),
    ]

    var body: some View {
        SettingsScreenLayout(title: "Timeout") {
            ForEach(options, id: \.0) { value, label in
                Button {
                    container.userPreferences[UserPreferences.screensaverTimeout] = value
                    settingsRouter.goBack()
                } label: {
                    ScreensaverOptionContent(label: label, isSelected: current == value)
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}

struct SettingsScreensaverDimmingScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var current: Int { container.userPreferences[UserPreferences.screensaverDimmingLevel] }
    private let options: [Int] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90]

    var body: some View {
        SettingsScreenLayout(title: "Dimming") {
            ForEach(options, id: \.self) { value in
                Button {
                    container.userPreferences[UserPreferences.screensaverDimmingLevel] = value
                    settingsRouter.goBack()
                } label: {
                    ScreensaverOptionContent(
                        label: value == 0 ? "Off" : "\(value)%",
                        isSelected: current == value
                    )
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }
}

private struct ScreensaverOptionContent: View {
    let label: String
    let isSelected: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            Text(label)
                .font(.bodyMd)
                .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

            Spacer()

            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.bodyMd)
                .foregroundColor(isSelected
                    ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                    : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
