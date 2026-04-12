import SwiftUI

struct SettingsMainScreen: View {
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var container: AppContainer
    @FocusState private var focusedRoute: SettingsRoute?
    @Namespace private var screenNamespace

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: Strings.settings) {
            SettingsListButton(
                icon: "person.2",
                heading: Strings.authentication,
                caption: Strings.authenticationSummary,
                action: { settingsRouter.navigate(to: .authentication) }
            )
            .focused($focusedRoute, equals: .authentication)
            .prefersDefaultFocus(in: screenNamespace)

            SettingsListButton(
                icon: "paintbrush",
                heading: Strings.customization,
                caption: Strings.customizationSummary,
                action: { settingsRouter.navigate(to: .customization) }
            )
            .focused($focusedRoute, equals: .customization)

            SettingsListButton(
                icon: "house",
                heading: Strings.home,
                caption: Strings.homeSummary,
                action: { settingsRouter.navigate(to: .home) }
            )
            .focused($focusedRoute, equals: .home)

            SettingsListButton(
                icon: "gear",
                heading: Strings.plugin,
                caption: Strings.pluginSummary,
                action: { settingsRouter.navigate(to: .plugin) }
            )
            .focused($focusedRoute, equals: .plugin)

            SettingsListButton(
                icon: "sparkles",
                heading: Strings.screensaver,
                caption: Strings.screensaverSummary,
                action: { settingsRouter.navigate(to: .customizationScreensaver) }
            )
            .focused($focusedRoute, equals: .customizationScreensaver)

            SettingsListButton(
                icon: "play.circle",
                heading: Strings.playbackSettings,
                caption: Strings.playbackDescription,
                action: { settingsRouter.navigate(to: .playback) }
            )
            .focused($focusedRoute, equals: .playback)

            SettingsListButton(
                icon: "person.3.fill",
                heading: Strings.syncPlay,
                caption: Strings.syncPlaySummary,
                trailingText: prefs[UserPreferences.syncPlayEnabled] ? Strings.enabled : Strings.disabled,
                action: { settingsRouter.navigate(to: .moonfinSyncPlay) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlay)

            SettingsListButton(
                icon: "lock.shield",
                heading: Strings.parentalControls,
                caption: Strings.parentalControlsSummary,
                trailingText: container.parentalControlsRepository.isEnabled ? Strings.enabled : Strings.disabled,
                action: { settingsRouter.navigate(to: .moonfinParentalControls) }
            )
            .focused($focusedRoute, equals: .moonfinParentalControls)

            SettingsListButton(
                icon: "tv",
                heading: Strings.liveTvGuide,
                caption: Strings.liveTvPreferences,
                action: { settingsRouter.navigate(to: .liveTvGuideOptions) }
            )
            .focused($focusedRoute, equals: .liveTvGuideOptions)

            SettingsListButton(
                icon: "chart.bar",
                heading: Strings.telemetry,
                caption: Strings.telemetryDescription,
                action: { settingsRouter.navigate(to: .telemetry) }
            )
            .focused($focusedRoute, equals: .telemetry)

            SettingsListButton(
                icon: "info.circle",
                heading: Strings.about,
                caption: Strings.aboutSummary,
                action: { settingsRouter.navigate(to: .about) }
            )
            .focused($focusedRoute, equals: .about)
        }
        .focusScope(screenNamespace)
        .defaultFocus($focusedRoute, .authentication)
        .restoresFocus($focusedRoute)
        .onAppear {
            guard settingsRouter.path.count == 1,
                  settingsRouter.path.first == .main,
                  settingsRouter.lastPoppedRoute == nil else { return }
            focusedRoute = .authentication
        }
    }
}
