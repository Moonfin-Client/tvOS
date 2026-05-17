import SwiftUI

struct SettingsPlaybackAdvancedScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var videoStartDelayLabel: String {
        let val = prefs[UserPreferences.videoStartDelay]
        return val == 0 ? "None" : "\(val) ms"
    }

    private var playbackQualityProfileLabel: String {
        let selected = prefs[UserPreferences.playbackQualityProfile]
        if selected != .auto {
            return selected.displayName
        }

        let generation = VideoCapabilityDetector.current().generation
        return PlaybackQualityProfile.autoSummaryDisplayName(for: generation)
    }

    var body: some View {
        SettingsScreenLayout(title: "Advanced Playback") {
            SettingsListButton(
                icon: "gauge.with.dots.needle.50percent",
                heading: "Playback Quality",
                caption: "Compatibility profile for your Apple TV",
                trailingText: playbackQualityProfileLabel,
                action: { settingsRouter.navigate(to: .playbackQualityProfile) }
            )
            .focused($focusedRoute, equals: .playbackQualityProfile)

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
            Text("Audio controls are available under Audio Preferences.")
                .font(.caption)
                .foregroundColor(theme.colorScheme.listCaption)

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
