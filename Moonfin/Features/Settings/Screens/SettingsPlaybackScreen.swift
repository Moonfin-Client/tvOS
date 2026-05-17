import SwiftUI

struct SettingsPlaybackScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var supportsMediaSegments: Bool {
        container.serverRepository.currentServer.value?.serverType.supports(.mediaSegments) == true
    }

    private var bitrateLabel: String {
        let value = prefs[UserPreferences.maxBitrate]
        if value == 0 { return "Auto" }
        if value >= 1_000_000 {
            return "\(value / 1_000_000) Mbps"
        }
        return "\(value / 1000) Kbps"
    }

    var body: some View {
        SettingsScreenLayout(title: "Video Playback Preferences") {
            if supportsMediaSegments {
                SettingsListButton(
                    icon: "scissors",
                    heading: "Skip Intros and Outros",
                    caption: "Choose action behavior for media segments",
                    action: { settingsRouter.navigate(to: .playbackMediaSegments) }
                )
                .focused($focusedRoute, equals: .playbackMediaSegments)
            } else {
                SettingsListButton(
                    icon: "scissors",
                    heading: "Skip Intros and Outros",
                    caption: "Not available on current server",
                    action: { }
                )
            }

            SettingsToggleButton(
                icon: "pause.circle",
                heading: "Show Description On Pause",
                caption: "Display overview while playback is paused",
                isOn: prefs.binding(for: UserPreferences.showDescriptionOnPause)
            )

            SettingsListButton(
                icon: "speedometer",
                heading: "Max Streaming Bitrate",
                caption: "Upper limit for streaming quality",
                trailingText: bitrateLabel,
                action: { settingsRouter.navigate(to: .playbackMaxBitrate) }
            )
            .focused($focusedRoute, equals: .playbackMaxBitrate)

            SettingsListButton(
                icon: "rectangle.badge.checkmark",
                heading: "Max Resolution",
                caption: "Upper limit for video resolution",
                trailingText: prefs[UserPreferences.maxVideoResolution].displayName,
                action: { settingsRouter.navigate(to: .playbackMaxResolution) }
            )
            .focused($focusedRoute, equals: .playbackMaxResolution)

            SettingsListButton(
                icon: "arrow.up.left.and.arrow.down.right",
                heading: "Player Zoom Mode",
                caption: "Default scaling mode for video playback",
                trailingText: prefs[UserPreferences.playerZoomMode].displayName,
                action: { settingsRouter.navigate(to: .playbackZoomMode) }
            )
            .focused($focusedRoute, equals: .playbackZoomMode)

            SettingsToggleButton(
                icon: "memorychip",
                heading: "Hardware Decoding",
                caption: "Use hardware decoding when available",
                isOn: prefs.binding(for: UserPreferences.hardwareDecoding)
            )

            SettingsListButton(
                icon: "speedometer",
                heading: "Refresh Rate Switching",
                caption: "Choose refresh rate switching behavior",
                trailingText: prefs[UserPreferences.refreshRateSwitchingBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackRefreshRateSwitching) }
            )
            .focused($focusedRoute, equals: .playbackRefreshRateSwitching)

            SettingsToggleButton(
                icon: "film.stack",
                heading: Strings.trickPlay,
                caption: Strings.trickPlayDescription,
                isOn: prefs.binding(for: UserPreferences.trickPlayEnabled)
            )

            SettingsListButton(
                icon: "gobackward",
                heading: "Resume Rewind",
                caption: "Seconds to rewind when resuming playback",
                action: { settingsRouter.navigate(to: .playbackResumeSubtractDuration) }
            )
            .focused($focusedRoute, equals: .playbackResumeSubtractDuration)

            SettingsListButton(
                icon: "arrow.uturn.backward",
                heading: "Unpause Rewind",
                caption: "Seconds to rewind when unpausing",
                action: { settingsRouter.navigate(to: .playbackUnpauseRewind) }
            )
            .focused($focusedRoute, equals: .playbackUnpauseRewind)

            SettingsListButton(
                icon: "backward.fill",
                heading: "Skip Back Length",
                caption: "Back-skip interval in milliseconds",
                trailingText: "\(prefs[UserPreferences.skipBackLength]) ms",
                action: { settingsRouter.navigate(to: .playbackSkipBackLength) }
            )
            .focused($focusedRoute, equals: .playbackSkipBackLength)

            SettingsListButton(
                icon: "forward.fill",
                heading: "Skip Forward Length",
                caption: "Seconds to skip forward",
                action: { settingsRouter.navigate(to: .playbackSkipForwardLength) }
            )
            .focused($focusedRoute, equals: .playbackSkipForwardLength)

        }
        .restoresFocus($focusedRoute)
    }
}
