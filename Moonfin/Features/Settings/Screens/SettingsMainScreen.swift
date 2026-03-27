import SwiftUI

struct SettingsMainScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var container: AppContainer
    @FocusState private var focusedRoute: SettingsRoute?
    @Namespace private var screenNamespace

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Settings") {
            SettingsListButton(
                icon: "person.2",
                heading: Strings.authentication,
                caption: "Manage servers & users",
                action: { settingsRouter.navigate(to: .authentication) }
            )
            .focused($focusedRoute, equals: .authentication)
            .prefersDefaultFocus(in: screenNamespace)

            SettingsListButton(
                icon: "paintbrush",
                heading: Strings.customization,
                caption: "Theme, clock, watched indicators",
                action: { settingsRouter.navigate(to: .customization) }
            )
            .focused($focusedRoute, equals: .customization)

            SettingsListButton(
                icon: "house",
                heading: "Home",
                caption: "Sections, poster size, image type",
                action: { settingsRouter.navigate(to: .home) }
            )
            .focused($focusedRoute, equals: .home)

            SettingsListButton(
                icon: "gear",
                heading: "Plugin",
                caption: "Navbar, shuffle, media bar",
                action: { settingsRouter.navigate(to: .plugin) }
            )
            .focused($focusedRoute, equals: .plugin)

            SettingsListButton(
                icon: "sparkles",
                heading: "Screensaver",
                caption: "Mode, timeout, dimming",
                action: { settingsRouter.navigate(to: .customizationScreensaver) }
            )
            .focused($focusedRoute, equals: .customizationScreensaver)

            SettingsListButton(
                icon: "play.circle",
                heading: Strings.playbackSettings,
                caption: "Quality, next up, audio",
                action: { settingsRouter.navigate(to: .playback) }
            )
            .focused($focusedRoute, equals: .playback)

            SettingsListButton(
                icon: "person.2.fill",
                heading: "SyncPlay",
                caption: "Synchronized playback settings",
                trailingText: prefs[UserPreferences.syncPlayEnabled] ? "On" : "Off",
                action: { settingsRouter.navigate(to: .moonfinSyncPlay) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlay)

            SettingsListButton(
                icon: "lock.shield",
                heading: Strings.parentalControls,
                caption: "Block content by rating",
                trailingText: container.parentalControlsRepository.isEnabled ? "On" : "Off",
                action: { settingsRouter.navigate(to: .moonfinParentalControls) }
            )
            .focused($focusedRoute, equals: .moonfinParentalControls)

            SettingsListButton(
                icon: "tv",
                heading: Strings.liveTvGuide,
                caption: "Channel order, indicators, filters",
                action: { settingsRouter.navigate(to: .liveTvGuideOptions) }
            )
            .focused($focusedRoute, equals: .liveTvGuideOptions)

            SettingsListButton(
                icon: "chart.bar",
                heading: Strings.telemetry,
                caption: "Analytics & crash reporting",
                action: { settingsRouter.navigate(to: .telemetry) }
            )
            .focused($focusedRoute, equals: .telemetry)

            SettingsListButton(
                icon: "hammer",
                heading: "Developer",
                caption: "Debug tools & diagnostics",
                action: { settingsRouter.navigate(to: .developer) }
            )
            .focused($focusedRoute, equals: .developer)

            SettingsListButton(
                icon: "info.circle",
                heading: Strings.about,
                caption: "Version & licenses",
                action: { settingsRouter.navigate(to: .about) }
            )
            .focused($focusedRoute, equals: .about)
        }
        .focusScope(screenNamespace)
        .defaultFocus($focusedRoute, .authentication)
        .restoresFocus($focusedRoute)
    }
}
