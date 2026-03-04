import SwiftUI

enum SettingsRoute: Hashable {

    // MARK: - Main

    case main

    // MARK: - Authentication

    case authentication
    case authenticationServer(serverId: String)
    case authenticationServerUser(serverId: String, userId: String)
    case authenticationSortBy
    case authenticationAutoSignIn
    case authenticationPinCode

    // MARK: - Customization

    case customization
    case customizationTheme
    case customizationClock
    case customizationWatchedIndicator
    case customizationSubtitles
    case customizationSubtitlesTextColor
    case customizationSubtitlesBackgroundColor
    case customizationSubtitlesEdgeColor

    // MARK: - Screensaver

    case customizationScreensaver
    case customizationScreensaverTimeout
    case customizationScreensaverAgeRating
    case customizationScreensaverMode
    case customizationScreensaverDimming

    // MARK: - Home

    case home
    case homeSection(index: Int)
    case homePosterSize
    case homeRowsImageType

    // MARK: - Libraries

    case libraries
    case librariesDisplay(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayImageSize(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayImageType(itemId: String, displayPreferencesId: String, serverId: String, userId: String)
    case librariesDisplayGrid(itemId: String, displayPreferencesId: String, serverId: String, userId: String)

    // MARK: - Live TV

    case liveTvGuideFilters
    case liveTvGuideOptions
    case liveTvGuideChannelOrder

    // MARK: - Playback

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

    // MARK: - Jellyseerr

    case jellyseerr
    case jellyseerrRows

    // MARK: - Moonfin

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

    // MARK: - Other

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

    func open(to route: SettingsRoute = .main) {
        path = [route]
        isPresented = true
    }

    func navigate(to route: SettingsRoute) {
        path.append(route)
    }

    func goBack() {
        guard !path.isEmpty else {
            dismiss()
            return
        }
        path.removeLast()
        if path.isEmpty { dismiss() }
    }

    func dismiss() {
        isPresented = false
        path = []
    }

    func reset(to route: SettingsRoute = .main) {
        path = [route]
    }
}
