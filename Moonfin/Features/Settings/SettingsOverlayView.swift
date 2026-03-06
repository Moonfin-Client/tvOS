import SwiftUI

struct SettingsOverlayView: View {
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var container: AppContainer
    let focusNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            Color.clear

            settingsPanel
        }
    }

    private var settingsPanel: some View {
        ZStack {
            screenView
                .id(settingsRouter.path.last ?? .main)
                .transition(screenTransition)
                .prefersDefaultFocus(in: focusNamespace)
        }
        .frame(width: 350)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large, style: .continuous)
                .fill(theme.colorScheme.surface)
        )
        .animation(.easeInOut(duration: 0.3), value: settingsRouter.path)
        .onExitCommand {
            settingsRouter.goBack()
        }
    }

    private var screenTransition: AnyTransition {
        switch settingsRouter.navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch settingsRouter.path.last ?? .main {
        case .main:
            SettingsMainScreen()
        case .authentication:
            SettingsAuthenticationScreen()
        case .authenticationSortBy:
            SettingsPickerScreen(
                title: "Sort Servers By",
                selection: Binding(
                    get: { container.authPreferences.sortBy },
                    set: { container.authPreferences.sortBy = $0 }
                ),
                displayName: \.displayName
            )
        case .authenticationAutoSignIn:
            SettingsPickerScreen(
                title: "Auto Sign In",
                selection: Binding(
                    get: { container.authPreferences.autoLoginBehavior },
                    set: { container.authPreferences.autoLoginBehavior = $0 }
                ),
                displayName: \.displayName
            )
        case .customization:
            SettingsCustomizationScreen()
        case .customizationTheme:
            SettingsThemePickerScreen()
        case .customizationClock:
            SettingsPickerScreen(
                title: "Clock",
                selection: container.userPreferences.binding(for: UserPreferences.clockBehavior),
                displayName: \.displayName
            )
        case .customizationWatchedIndicator:
            SettingsPickerScreen(
                title: "Watched Indicator",
                selection: container.userPreferences.binding(for: UserPreferences.watchedIndicator),
                displayName: \.displayName
            )
        case .customizationScreensaver:
            SettingsScreensaverScreen()
        case .customizationScreensaverMode:
            SettingsPickerScreen(
                title: "Screensaver Mode",
                selection: container.userPreferences.binding(for: UserPreferences.screensaverMode),
                displayName: \.displayName
            )
        case .plugin:
            SettingsMoonfinScreen()
        case .moonfinNavbarPosition:
            SettingsPickerScreen(
                title: "Navbar Position",
                selection: container.userPreferences.binding(for: UserPreferences.navbarPosition),
                displayName: \.displayName
            )
        case .moonfinShuffleContentType:
            SettingsPickerScreen(
                title: "Shuffle Content Type",
                selection: container.userPreferences.binding(for: UserPreferences.shuffleContentType),
                displayName: \.displayName
            )
        case .moonfinMediaBarContentType:
            SettingsPickerScreen(
                title: "Media Bar Content",
                selection: container.userPreferences.binding(for: UserPreferences.mediaBarContentType),
                displayName: \.displayName
            )
        case .moonfinMediaBarItemCount:
            SettingsPickerScreen(
                title: "Media Bar Items",
                selection: container.userPreferences.binding(for: UserPreferences.mediaBarItemCount),
                displayName: \.displayName
            )
        case .moonfinMediaBarColor:
            SettingsPickerScreen(
                title: "Media Bar Color",
                selection: container.userPreferences.binding(for: UserPreferences.mediaBarOverlayColor),
                displayName: \.displayName
            )
        case .moonfinMediaBarOpacity:
            SettingsMediaBarOpacityScreen()
        case .playback:
            SettingsPlaybackScreen()
        case .playbackNextUpBehavior:
            SettingsPickerScreen(
                title: "Next Up Behavior",
                selection: container.userPreferences.binding(for: UserPreferences.nextUpBehavior),
                displayName: \.displayName
            )
        case .playbackAudioBehavior:
            SettingsPickerScreen(
                title: "Audio Behavior",
                selection: container.userPreferences.binding(for: UserPreferences.audioBehavior),
                displayName: \.displayName
            )
        case .telemetry:
            SettingsTelemetryScreen()
        case .about:
            SettingsAboutScreen()
        default:
            SettingsPlaceholderScreen()
        }
    }
}

struct SettingsPlaceholderScreen: View {
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack {
            Spacer()
            Text("Coming Soon")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.listCaption)
            Spacer()
        }
    }
}
