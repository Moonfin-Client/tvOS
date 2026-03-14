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
        case .authenticationPinCode:
            SettingsAuthPinCodeScreen()
        case .authenticationServer(let serverId):
            SettingsAuthServerScreen(serverId: serverId)
        case .authenticationServerUser(let serverId, let userId):
            SettingsAuthServerUserScreen(serverId: serverId, userId: userId)
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
        case .customizationSubtitles:
            SettingsSubtitlesScreen()
        case .customizationSubtitlesTextColor:
            SettingsSubtitleColorPickerScreen(
                title: "Text Color",
                preference: UserPreferences.subtitlesTextColor
            )
        case .customizationSubtitlesBackgroundColor:
            SettingsSubtitleColorPickerScreen(
                title: "Background Color",
                preference: UserPreferences.subtitlesBackgroundColor
            )
        case .customizationSubtitlesEdgeColor:
            SettingsSubtitleColorPickerScreen(
                title: "Edge Color",
                preference: UserPreferences.subtitlesStrokeColor
            )
        case .customizationSubtitlesTextSize:
            SettingsSubtitleTextSizeScreen()
        case .customizationSubtitlesOffset:
            SettingsSubtitleOffsetScreen()
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
        case .home:
            SettingsHomeScreen()
        case .homePosterSize:
            SettingsPickerScreen(
                title: "Poster Size",
                selection: container.userPreferences.binding(for: UserPreferences.homePosterSize),
                displayName: \.displayName
            )
        case .homeRowsImageType:
            SettingsPickerScreen(
                title: "Image Type",
                selection: container.userPreferences.binding(for: UserPreferences.homeRowsImageType),
                displayName: \.displayName
            )
        case .libraries:
            SettingsLibrariesScreen()
        case .librariesDisplay(let itemId, let displayPreferencesId, let serverId, let userId):
            SettingsLibraryDisplayScreen(
                itemId: itemId,
                displayPreferencesId: displayPreferencesId,
                serverId: serverId,
                userId: userId
            )
        case .librariesDisplayImageSize(let itemId, _, _, _):
            SettingsPickerScreen(
                title: "Image Size",
                selection: libraryBinding(itemId: itemId, keyPath: \.posterSize),
                displayName: \.displayName
            )
        case .librariesDisplayImageType(let itemId, _, _, _):
            SettingsPickerScreen(
                title: "Image Type",
                selection: libraryBinding(itemId: itemId, keyPath: \.imageType),
                displayName: \.displayName
            )
        case .librariesDisplayGrid(let itemId, _, _, _):
            SettingsPickerScreen(
                title: "Grid Direction",
                selection: libraryBinding(itemId: itemId, keyPath: \.gridDirection),
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
        case .moonfinThemeMusicVolume:
            SettingsSyncPlayValueScreen(
                title: "Theme Music Volume",
                preference: UserPreferences.themeMusicVolume,
                options: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
                suffix: "%"
            )
        case .moonfinDetailsBlur:
            SettingsSyncPlayValueScreen(
                title: "Details Background Blur",
                preference: UserPreferences.detailsBackgroundBlur,
                options: [0, 5, 10, 15, 20, 25, 30, 35, 40],
                suffix: ""
            )
        case .moonfinBrowsingBlur:
            SettingsSyncPlayValueScreen(
                title: "Browsing Background Blur",
                preference: UserPreferences.browsingBackgroundBlur,
                options: [0, 5, 10, 15, 20, 25, 30, 35, 40],
                suffix: ""
            )
        case .moonfinSeasonalSurprise:
            SettingsPickerScreen(
                title: "Seasonal Surprise",
                selection: container.userPreferences.binding(for: UserPreferences.seasonalSurprise),
                displayName: \.displayName
            )
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
        case .playbackNextUpTimeout:
            SettingsSyncPlayValueScreen(
                title: "Next Up Timeout",
                preference: UserPreferences.nextUpTimeout,
                options: [0, 5, 10, 15, 20, 25, 30, 45, 60],
                suffix: " sec"
            )
        case .playbackInactivityPrompt:
            StillWatchingSettingsScreen()
        case .playbackMaxBitrate:
            SettingsMaxBitrateScreen()
        case .playbackAudioBehavior:
            SettingsPickerScreen(
                title: "Audio Behavior",
                selection: container.userPreferences.binding(for: UserPreferences.audioBehavior),
                displayName: \.displayName
            )
        case .playbackAudioOutput:
            SettingsPickerScreen(
                title: "Audio Output",
                selection: container.userPreferences.binding(for: UserPreferences.audioOutput),
                displayName: \.displayName
            )
        case .playbackSlideshowInterval:
            SettingsPickerScreen(
                title: "Slideshow Interval",
                selection: container.userPreferences.binding(for: UserPreferences.photoSlideshowInterval),
                displayName: \.displayName
            )
        case .playbackAdvanced:
            SettingsPlaybackAdvancedScreen()
        case .playbackResumeSubtractDuration:
            SettingsSyncPlayValueScreen(
                title: "Resume Pre-roll",
                preference: UserPreferences.resumeSubtractDuration,
                options: [0, 3, 5, 7, 10, 20, 30, 60, 120, 300],
                suffix: " sec"
            )
        case .playbackSkipForwardLength:
            SettingsSyncPlayValueScreen(
                title: "Skip Forward Length",
                preference: UserPreferences.skipForwardLength,
                options: [5, 10, 15, 20, 25, 30],
                suffix: " sec"
            )
        case .playbackUnpauseRewind:
            SettingsSyncPlayValueScreen(
                title: "Unpause Rewind",
                preference: UserPreferences.unpauseRewindDuration,
                options: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                suffix: " sec"
            )
        case .playbackVideoStartDelay:
            SettingsSyncPlayValueScreen(
                title: "Video Start Delay",
                preference: UserPreferences.videoStartDelay,
                options: [0, 250, 500, 1000, 2000, 3000, 5000],
                suffix: " ms"
            )
        case .playbackMaxResolution:
            SettingsPickerScreen(
                title: "Max Resolution",
                selection: container.userPreferences.binding(for: UserPreferences.maxVideoResolution),
                displayName: \.displayName
            )
        case .playbackZoomMode:
            SettingsPickerScreen(
                title: "Default Zoom",
                selection: container.userPreferences.binding(for: UserPreferences.playerZoomMode),
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
        case .seerr:
            SettingsSeerrScreen()
        case .seerrRows:
            SettingsSeerrRowsScreen()
        case .seerrFetchLimit:
            SettingsPickerScreen(
                title: "Fetch Limit",
                selection: seerrFetchLimitBinding,
                displayName: \.displayName
            )
        case .moonfinParentalControls:
            SettingsParentalControlsScreen()
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

    private var seerrFetchLimitBinding: Binding<SeerrFetchLimit> {
        let prefs = container.seerrRepository.getPreferences()
        return Binding(
            get: { prefs?[SeerrPreferences.fetchLimit] ?? .medium },
            set: { prefs?[SeerrPreferences.fetchLimit] = $0 }
        )
    }

    private func libraryBinding<T>(itemId: String, keyPath: ReferenceWritableKeyPath<LibraryPreferences, T>) -> Binding<T> {
        let prefs = LibraryPreferences(store: container.preferenceStore, libraryId: itemId)
        return Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = $0 }
        )
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
