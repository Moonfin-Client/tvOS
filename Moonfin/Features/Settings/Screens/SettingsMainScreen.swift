import SwiftUI

struct SettingsMainScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter

    var body: some View {
        SettingsScreenLayout(title: "Settings") {
            SettingsListButton(
                icon: "person.2",
                heading: "Authentication",
                caption: "Manage servers & users",
                action: { settingsRouter.navigate(to: .authentication) }
            )

            SettingsListButton(
                icon: "paintbrush",
                heading: "Customization",
                caption: "Theme, clock, watched indicators",
                action: { settingsRouter.navigate(to: .customization) }
            )

            SettingsListButton(
                icon: "gear",
                heading: "Moonfin",
                caption: "Navbar, shuffle, media bar",
                action: { settingsRouter.navigate(to: .plugin) }
            )

            SettingsListButton(
                icon: "sparkles",
                heading: "Screensaver",
                caption: "Mode, timeout, dimming",
                action: { settingsRouter.navigate(to: .customizationScreensaver) }
            )

            SettingsListButton(
                icon: "play.circle",
                heading: "Playback",
                caption: "Quality, next up, audio",
                action: { settingsRouter.navigate(to: .playback) }
            )

            SettingsListButton(
                icon: "chart.bar",
                heading: "Telemetry",
                caption: "Analytics & crash reporting",
                action: { settingsRouter.navigate(to: .telemetry) }
            )

            SettingsListButton(
                icon: "info.circle",
                heading: "About",
                caption: "Version & licenses",
                action: { settingsRouter.navigate(to: .about) }
            )
        }
    }
}
