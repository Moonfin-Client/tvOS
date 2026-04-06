import SwiftUI

enum SettingsRoute: Hashable {
    case main

    case authentication
    case authenticationServer(serverId: String)
    case authenticationServerUser(serverId: String, userId: String)
    case authenticationSortBy
    case authenticationAutoSignIn
    case authenticationPinCode

    case customization
    case customizationTheme
    case customizationClock
    case customizationWatchedIndicator
    case customizationSubtitles
    case customizationSubtitlesTextColor
    case customizationSubtitlesBackgroundColor
    case customizationSubtitlesEdgeColor
    case customizationSubtitlesTextSize
    case customizationSubtitlesOffset

    case customizationScreensaver
    case customizationScreensaverTimeout
    case customizationScreensaverAgeRating
    case customizationScreensaverMode
    case customizationScreensaverDimming

    case home
    case homeSection(index: Int)
    case homePosterSize
    case homeRowsImageType
    case homeImageTypeContinueWatching
    case homeImageTypeNextUp
    case homeImageTypeLibraries
    case homeImageTypeLiveTv

    case libraries
    case librariesDisplay(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayImageSize(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayImageType(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayGrid(itemId: String, displayPreferencesId: String, serverId: String, userId: String)

    case liveTvGuideFilters
    case liveTvGuideOptions
    case liveTvGuideChannelOrder

    case playback
    case playbackPlayer
    case playbackNextUp
    case playbackNextUpBehavior
    case playbackNextUpTimeout
    case playbackInactivityPrompt
    case playbackPrerolls
    case playbackMediaSegments
    case playbackMediaSegment(segmentType: String)
    case playbackAdvanced
    case playbackResumeSubtractDuration
    case playbackSkipForwardLength
    case playbackUnpauseRewind
    case playbackVideoStartDelay
    case playbackMaxBitrate
    case playbackMaxResolution
    case playbackRefreshRateSwitching
    case playbackZoomMode
    case playbackAudioBehavior
    case playbackAudioOutput
    case playbackSlideshowInterval

    case seerr
    case seerrRows
    case seerrFetchLimit

    case plugin
    case moonfinNavbarPosition
    case moonfinShuffleContentType
    case moonfinMediaBarContentType
    case moonfinMediaBarItemCount
    case moonfinMediaBarOpacity
    case moonfinMediaBarColor
    case moonfinThemeMusicVolume
    case moonfinSeasonalSurprise
    case moonfinDetailsBlur
    case moonfinBrowsingBlur
    case moonfinParentalControls
    case pluginToolbar
    case pluginMediaBar
    case pluginBackgrounds
    case pluginPreviewsMusic
    case pluginIntegrations
    case moonfinSyncPlay
    case moonfinSyncPlayMinDelay
    case moonfinSyncPlayMaxDelay
    case moonfinSyncPlayDuration
    case moonfinSyncPlayMinDelaySkip
    case moonfinSyncPlayExtraOffset

    case syncPlay
    case language
    case telemetry
    case developer
    case about
    case licenses
    case license(artifactId: String)
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var isPresented = false
    @Published var path: [SettingsRoute] = []
    @Published var lastPoppedRoute: SettingsRoute?
    var navigationDirection: NavigationDirection = .forward

    enum NavigationDirection {
        case forward, backward
    }

    func open(to route: SettingsRoute = .main) {
        navigationDirection = .forward
        lastPoppedRoute = nil
        path = [route]
        isPresented = true
    }

    func navigate(to route: SettingsRoute) {
        navigationDirection = .forward
        path.append(route)
    }

    func goBack() {
        guard !path.isEmpty else {
            dismiss()
            return
        }
        navigationDirection = .backward
        lastPoppedRoute = path.removeLast()
        if path.isEmpty { dismiss() }
    }

    func dismiss() {
        isPresented = false
        path = []
    }
}

struct SettingsFocusRestorationModifier: ViewModifier {
    @EnvironmentObject var settingsRouter: SettingsRouter
    var focusedRoute: FocusState<SettingsRoute?>.Binding

    func body(content: Content) -> some View {
        content.onAppear {
            guard let route = settingsRouter.lastPoppedRoute else { return }
            settingsRouter.lastPoppedRoute = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    focusedRoute.wrappedValue = route
                }
            }
        }
    }
}

extension View {
    func restoresFocus(_ focusedRoute: FocusState<SettingsRoute?>.Binding) -> some View {
        modifier(SettingsFocusRestorationModifier(focusedRoute: focusedRoute))
    }
}
