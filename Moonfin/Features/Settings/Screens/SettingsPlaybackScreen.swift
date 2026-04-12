import SwiftUI

struct SettingsPlaybackScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }

    private var stillWatchingLabel: String {
        let val = prefs[UserPreferences.stillWatchingThreshold]
        return val > 0 ? Strings.episodeCount(val) : Strings.disabled
    }

    private var nextUpTimeoutLabel: String {
        let val = prefs[UserPreferences.nextUpTimeout]
        return val > 0 ? "\(val)\(Strings.secondsShort)" : Strings.disabled
    }

    private var supportsMediaSegments: Bool {
        container.serverRepository.currentServer.value?.serverType.supports(.mediaSegments) == true
    }

    var body: some View {
        SettingsScreenLayout(title: Strings.playbackSettings) {
            SettingsListButton(
                icon: "forward.end",
                heading: Strings.nextUpBehaviorTitle,
                caption: Strings.nextUpBehaviorDescription,
                trailingText: prefs[UserPreferences.nextUpBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackNextUpBehavior) }
            )
            .focused($focusedRoute, equals: .playbackNextUpBehavior)

            SettingsListButton(
                icon: "timer",
                heading: Strings.nextUpTimeoutTitle,
                caption: Strings.nextUpTimeoutDescription,
                trailingText: nextUpTimeoutLabel,
                action: { settingsRouter.navigate(to: .playbackNextUpTimeout) }
            )
            .focused($focusedRoute, equals: .playbackNextUpTimeout)

            SettingsListButton(
                icon: "pause.circle",
                heading: Strings.stillWatchingPrompt,
                caption: Strings.stillWatchingPromptDescription,
                trailingText: stillWatchingLabel,
                action: { settingsRouter.navigate(to: .playbackInactivityPrompt) }
            )
            .focused($focusedRoute, equals: .playbackInactivityPrompt)

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: Strings.audioBehavior,
                caption: Strings.audioBehaviorDescription,
                trailingText: prefs[UserPreferences.audioBehavior].displayName,
                action: { settingsRouter.navigate(to: .playbackAudioBehavior) }
            )
            .focused($focusedRoute, equals: .playbackAudioBehavior)

            SettingsListButton(
                icon: "photo.on.rectangle",
                heading: Strings.slideshowInterval,
                caption: Strings.slideshowIntervalDescription,
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

            SettingsToggleButton(
                icon: "film.stack",
                heading: Strings.trickPlay,
                caption: Strings.trickPlayDescription,
                isOn: prefs.binding(for: UserPreferences.trickPlayEnabled)
            )

            if supportsMediaSegments {
                SettingsListButton(
                    icon: "scissors",
                    heading: Strings.mediaSegmentsSettings,
                    caption: Strings.mediaSegmentsDescription,
                    action: { settingsRouter.navigate(to: .playbackMediaSegments) }
                )
                .focused($focusedRoute, equals: .playbackMediaSegments)
            }

            SettingsListButton(
                icon: "gearshape.2",
                heading: Strings.advanced,
                caption: Strings.advancedDescription,
                action: { settingsRouter.navigate(to: .playbackAdvanced) }
            )
            .focused($focusedRoute, equals: .playbackAdvanced)
        }
        .restoresFocus($focusedRoute)
    }
}
