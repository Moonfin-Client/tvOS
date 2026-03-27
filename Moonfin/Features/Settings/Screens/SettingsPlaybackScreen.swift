import SwiftUI

struct SettingsPlaybackScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var stillWatchingLabel: String {
        let val = prefs[UserPreferences.stillWatchingThreshold]
        return val > 0 ? "\(val) episodes" : "Disabled"
    }

    private var nextUpTimeoutLabel: String {
        let val = prefs[UserPreferences.nextUpTimeout]
        return val > 0 ? "\(val) sec" : "Disabled"
    }

    private var supportsMediaSegments: Bool {
        container.serverRepository.currentServer.value?.serverType.supports(.mediaSegments) == true
    }

    var body: some View {
        SettingsScreenLayout(title: "Playback") {
            SettingsListButton(
                icon: "forward.end",
                heading: "Next Up Behavior",
                caption: "How next up is displayed",
                trailingText: prefs[UserPreferences.nextUpBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackNextUpBehavior) }
            )
            .focused($focusedRoute, equals: .playbackNextUpBehavior)

            SettingsListButton(
                icon: "timer",
                heading: "Next Up Timeout",
                caption: "Auto-play countdown duration",
                trailingText: nextUpTimeoutLabel,
                action: { settingsRouter.navigate(to: .playbackNextUpTimeout) }
            )
            .focused($focusedRoute, equals: .playbackNextUpTimeout)

            SettingsListButton(
                icon: "pause.circle",
                heading: "Still Watching Prompt",
                caption: "Ask after N episodes",
                trailingText: stillWatchingLabel,
                action: { settingsRouter.navigate(to: .playbackInactivityPrompt) }
            )
            .focused($focusedRoute, equals: .playbackInactivityPrompt)

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Audio Behavior",
                caption: "Audio track selection",
                trailingText: prefs[UserPreferences.audioBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioBehavior) }
            )
            .focused($focusedRoute, equals: .playbackAudioBehavior)

            SettingsListButton(
                icon: "photo.on.rectangle",
                heading: "Slideshow Interval",
                caption: "Time between photos",
                trailingText: prefs[UserPreferences.photoSlideshowInterval].displayName,
                action: { settingsRouter.navigate(to: .playbackSlideshowInterval) }
            )
            .focused($focusedRoute, equals: .playbackSlideshowInterval)

            SettingsToggleButton(
                icon: "film.stack",
                heading: Strings.prerollsEnabled,
                caption: Strings.prerollsEnabledDescription,
                isOn: prefs.binding(for: UserPreferences.cinemaModeEnabled)
            )

            if supportsMediaSegments {
                SettingsListButton(
                    icon: "scissors",
                    heading: "Media Segments",
                    caption: "Skip intros, outros, and more",
                    action: { settingsRouter.navigate(to: .playbackMediaSegments) }
                )
                .focused($focusedRoute, equals: .playbackMediaSegments)
            }

            SettingsListButton(
                icon: "gearshape.2",
                heading: "Advanced",
                caption: "Resolution, zoom, delays, and more",
                action: { settingsRouter.navigate(to: .playbackAdvanced) }
            )
            .focused($focusedRoute, equals: .playbackAdvanced)
        }
        .restoresFocus($focusedRoute)
    }
}
