import SwiftUI

struct SettingsPlaybackAdvancedScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var resumeLabel: String {
        let val = prefs[UserPreferences.resumeSubtractDuration]
        return val == 0 ? "None" : "\(val) sec"
    }

    private var skipForwardLabel: String {
        "\(prefs[UserPreferences.skipForwardLength]) sec"
    }

    private var unpauseRewindLabel: String {
        let val = prefs[UserPreferences.unpauseRewindDuration]
        return val == 0 ? "None" : "\(val) sec"
    }

    private var bitrateLabel: String {
        let value = prefs[UserPreferences.maxBitrate]
        if value == 0 { return "Auto" }
        if value >= 1_000_000 {
            let mbps = Double(value) / 1_000_000.0
            return mbps.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(mbps)) Mbps"
                : String(format: "%.1f Mbps", mbps)
        }
        let kbps = Double(value) / 1_000.0
        return String(format: "%.0f Kbps", kbps)
    }

    private var videoStartDelayLabel: String {
        let val = prefs[UserPreferences.videoStartDelay]
        return val == 0 ? "None" : "\(val) ms"
    }

    var body: some View {
        SettingsScreenLayout(title: "Advanced Playback") {
            sectionHeader("Customization")

            SettingsListButton(
                icon: "backward.frame",
                heading: "Resume Pre-roll",
                caption: "Rewind when resuming playback",
                trailingText: resumeLabel,
                action: { settingsRouter.navigate(to: .playbackResumeSubtractDuration) }
            )
            .focused($focusedRoute, equals: .playbackResumeSubtractDuration)

            SettingsListButton(
                icon: "forward",
                heading: "Skip Forward Length",
                caption: "Seconds to skip on swipe",
                trailingText: skipForwardLabel,
                action: { settingsRouter.navigate(to: .playbackSkipForwardLength) }
            )
            .focused($focusedRoute, equals: .playbackSkipForwardLength)

            SettingsListButton(
                icon: "gobackward",
                heading: "Unpause Rewind",
                caption: "Rewind when unpausing",
                trailingText: unpauseRewindLabel,
                action: { settingsRouter.navigate(to: .playbackUnpauseRewind) }
            )
            .focused($focusedRoute, equals: .playbackUnpauseRewind)

            SettingsToggleButton(
                icon: "text.below.photo",
                heading: "Show Description on Pause",
                caption: "Display media info when paused",
                isOn: prefs.binding(for: UserPreferences.showDescriptionOnPause)
            )

            sectionDivider()
            sectionHeader("Video")

            SettingsListButton(
                icon: "speedometer",
                heading: "Max Bitrate",
                caption: "Limit streaming quality",
                trailingText: bitrateLabel,
                action: { settingsRouter.navigate(to: .playbackMaxBitrate) }
            )
            .focused($focusedRoute, equals: .playbackMaxBitrate)

            SettingsListButton(
                icon: "rectangle.badge.checkmark",
                heading: "Max Resolution",
                caption: "Maximum video resolution",
                trailingText: prefs[UserPreferences.maxVideoResolution].displayName,
                action: { settingsRouter.navigate(to: .playbackMaxResolution) }
            )
            .focused($focusedRoute, equals: .playbackMaxResolution)

            SettingsListButton(
                icon: "arrow.up.left.and.arrow.down.right",
                heading: "Default Zoom",
                caption: "Video display mode",
                trailingText: prefs[UserPreferences.playerZoomMode].displayName,
                action: { settingsRouter.navigate(to: .playbackZoomMode) }
            )
            .focused($focusedRoute, equals: .playbackZoomMode)

            SettingsListButton(
                icon: "clock.badge.questionmark",
                heading: "Video Start Delay",
                caption: "Delay before playback begins",
                trailingText: videoStartDelayLabel,
                action: { settingsRouter.navigate(to: .playbackVideoStartDelay) }
            )
            .focused($focusedRoute, equals: .playbackVideoStartDelay)

            sectionDivider()
            sectionHeader("Audio")

            SettingsListButton(
                icon: "speaker.wave.1",
                heading: "Audio Output",
                caption: "Surround sound handling",
                trailingText: prefs[UserPreferences.audioOutput].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioOutput) }
            )
            .focused($focusedRoute, equals: .playbackAudioOutput)

            SettingsToggleButton(
                icon: "moon",
                heading: "Audio Night Mode",
                caption: "Compress dynamic range",
                isOn: prefs.binding(for: UserPreferences.audioNightMode)
            )

            sectionDivider()
            sectionHeader("Live TV")

            SettingsToggleButton(
                icon: "play.tv",
                heading: "Direct Play",
                caption: "Play live streams directly",
                isOn: prefs.binding(for: UserPreferences.liveTvDirectPlay)
            )
        }
        .restoresFocus($focusedRoute)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.bodyLg)
            .fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
            .padding(.bottom, SpaceTokens.space2xs)
    }

    private func sectionDivider() -> some View {
        Divider()
            .background(theme.colorScheme.listCaption.opacity(0.3))
            .padding(.vertical, SpaceTokens.spaceXs)
    }
}
