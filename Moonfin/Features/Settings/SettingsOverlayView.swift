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
        case .customizationScreensaverTimeout:
            SettingsScreensaverTimeoutScreen()
        case .customizationScreensaverDimming:
            SettingsScreensaverDimmingScreen()
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
        case .playbackMediaSegments:
            SettingsMediaSegmentsScreen()
        case .playbackMediaSegment(let segmentType):
            if let type = MediaSegmentType(rawValue: segmentType) {
                SettingsMediaSegmentScreen(segmentType: type)
            } else {
                SettingsPlaceholderScreen()
            }
        case .playbackNextUpBehavior:
            SettingsPickerScreen(
                title: "Next Up Behavior",
                selection: container.userPreferences.binding(for: UserPreferences.nextUpBehavior),
                displayName: \.displayName
            )
        case .playbackInactivityPrompt:
            StillWatchingSettingsScreen()
        case .playbackAudioBehavior:
            SettingsPickerScreen(
                title: "Audio Behavior",
                selection: container.userPreferences.binding(for: UserPreferences.audioBehavior),
                displayName: \.displayName
            )
        case .playbackSlideshowInterval:
            SettingsPickerScreen(
                title: "Slideshow Interval",
                selection: container.userPreferences.binding(for: UserPreferences.photoSlideshowInterval),
                displayName: \.displayName
            )
        case .language:
            SettingsLanguageScreen()
        case .telemetry:
            SettingsTelemetryScreen()
        case .about:
            SettingsAboutScreen()
        case .syncPlay:
            SyncPlayScreen()
        case .moonfinSyncPlay:
            SettingsSyncPlayScreen()
        case .moonfinSyncPlayMinDelay:
            SettingsSyncPlayValueScreen(
                title: "Min Delay (Speed)",
                preference: UserPreferences.syncPlayMinDelaySpeedToSync,
                options: [50, 100, 150, 200, 300, 500, 750, 1000],
                suffix: " ms"
            )
        case .moonfinSyncPlayMaxDelay:
            SettingsSyncPlayValueScreen(
                title: "Max Delay (Speed)",
                preference: UserPreferences.syncPlayMaxDelaySpeedToSync,
                options: [1000, 2000, 3000, 5000, 7500, 10000],
                suffix: " ms"
            )
        case .moonfinSyncPlayDuration:
            SettingsSyncPlayValueScreen(
                title: "Speed Duration",
                preference: UserPreferences.syncPlaySpeedToSyncDuration,
                options: [500, 750, 1000, 1500, 2000, 3000],
                suffix: " ms"
            )
        case .moonfinSyncPlayMinDelaySkip:
            SettingsSyncPlayValueScreen(
                title: "Min Delay (Skip)",
                preference: UserPreferences.syncPlayMinDelaySkipToSync,
                options: [500, 1000, 1500, 2000, 3000, 5000],
                suffix: " ms"
            )
        case .moonfinSyncPlayExtraOffset:
            SettingsSyncPlayValueScreen(
                title: "Extra Time Offset",
                preference: UserPreferences.syncPlayExtraTimeOffset,
                options: [-5000, -2000, -1000, -500, 0, 500, 1000, 2000, 5000],
                suffix: " ms"
            )
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
