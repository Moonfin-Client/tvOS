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

    case customizationScreensaver
    case customizationScreensaverTimeout
    case customizationScreensaverAgeRating
    case customizationScreensaverMode
    case customizationScreensaverDimming

    case home
    case homeSection(index: Int)
    case homePosterSize
    case homeRowsImageType

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
    case playbackInactivityPrompt
    case playbackPrerolls
    case playbackMediaSegments
    case playbackMediaSegment(segmentType: String)
    case playbackAdvanced
    case playbackResumeSubtractDuration
    case playbackMaxBitrate
    case playbackMaxResolution
    case playbackRefreshRateSwitching
    case playbackZoomMode
    case playbackAudioBehavior

    case jellyseerr
    case jellyseerrRows

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
    case moonfinSyncPlay
    case moonfinSyncPlayMinDelay
    case moonfinSyncPlayMaxDelay
    case moonfinSyncPlayDuration
    case moonfinSyncPlayMinDelaySkip
    case moonfinSyncPlayExtraOffset

    case syncPlay
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
    var navigationDirection: NavigationDirection = .forward

    enum NavigationDirection {
        case forward, backward
    }

    func open(to route: SettingsRoute = .main) {
        navigationDirection = .forward
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
        path.removeLast()
        if path.isEmpty { dismiss() }
    }

    func dismiss() {
        isPresented = false
        path = []
    }
}
