import SwiftUI

struct SettingsPlaybackSyncPlayRootScreen: View {
    @FocusState private var focusedRoute: SettingsRoute?

    var body: some View {
        SettingsScreenLayout(title: "Playback and SyncPlay") {
            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .playbackVideoPreferences,
                icon: "play.circle",
                heading: "Video Playback Preferences",
                caption: "Streaming, playback overlays, skipping, and media segments"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .playbackAudioPreferences,
                icon: "speaker.wave.2",
                heading: "Audio Preferences",
                caption: "Night mode, output behavior, and audio defaults"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .playbackSubtitles,
                icon: "captions.bubble",
                heading: "Subtitles",
                caption: "Subtitle defaults and appearance"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .playbackAutomationQueue,
                icon: "list.bullet.rectangle.portrait",
                heading: "Automation and Queue",
                caption: "Next Up, still watching, cinema mode, and queue behavior"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .moonfinSyncPlay,
                icon: "person.3.fill",
                heading: "SyncPlay",
                caption: "Sync settings and group playback"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .playbackAdvanced,
                icon: "gearshape.2",
                heading: "Advanced Options",
                caption: "Advanced playback and Live TV direct-play behavior"
            )

            SettingsNavRow(
                focusedRoute: $focusedRoute,
                route: .liveTvGuideOptions,
                icon: "tv",
                heading: "Live TV Guide",
                caption: "Guide layout, channel order, badges, and filters"
            )
        }
        .restoresFocus($focusedRoute)
    }
}
