import SwiftUI

struct SettingsMoonfinScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var prefs: UserPreferences { container.userPreferences }
    private var pluginEnabled: Bool { prefs[UserPreferences.pluginSyncEnabled] }

    var body: some View {
        SettingsScreenLayout(title: "Moonfin") {
            SettingsToggleButton(
                icon: "arrow.triangle.2.circlepath",
                heading: "Plugin Sync",
                caption: "Sync settings with Moonfin server plugin",
                isOn: pluginSyncBinding
            )

            SettingsListButton(
                icon: "rectangle.topthird.inset.filled",
                heading: "Navbar Position",
                caption: "Where to display the navigation bar",
                trailingText: prefs[UserPreferences.navbarPosition].displayName,
                action: { settingsRouter.navigate(to: .moonfinNavbarPosition) }
            )

            SettingsListButton(
                icon: "shuffle",
                heading: "Shuffle Content Type",
                caption: "Default content for shuffle",
                trailingText: prefs[UserPreferences.shuffleContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinShuffleContentType) }
            )

            SettingsToggleButton(
                icon: "shuffle",
                heading: "Show Shuffle Button",
                caption: "Show shuffle in toolbar",
                isOn: prefs.binding(for: UserPreferences.showShuffleButton)
            )

            SettingsToggleButton(
                icon: "theatermasks",
                heading: "Show Genres Button",
                caption: "Show genres in toolbar",
                isOn: prefs.binding(for: UserPreferences.showGenresButton)
            )

            SettingsToggleButton(
                icon: "heart.fill",
                heading: "Show Favorites Button",
                caption: "Show favorites in toolbar",
                isOn: prefs.binding(for: UserPreferences.showFavoritesButton)
            )

            SettingsToggleButton(
                icon: "movieclapper.fill",
                heading: "Show Libraries Button",
                caption: "Show libraries in toolbar",
                isOn: prefs.binding(for: UserPreferences.showLibrariesInToolbar)
            )

            SettingsToggleButton(
                icon: "arrow.triangle.merge",
                heading: "Merge Continue Watching & Next Up",
                caption: "Combine into a single row",
                isOn: prefs.binding(for: UserPreferences.mergeContinueWatchingNextUp)
            )

            SettingsToggleButton(
                icon: "folder",
                heading: "Enable Folder View",
                caption: "Show folders button in toolbar",
                isOn: prefs.binding(for: UserPreferences.enableFolderView)
            )

            SettingsToggleButton(
                icon: "photo.artframe",
                heading: "Backdrop",
                caption: "Show background images",
                isOn: prefs.binding(for: UserPreferences.backdropEnabled)
            )

            SettingsListButton(
                icon: "aqi.medium",
                heading: "Details Background Blur",
                caption: "Blur amount on detail screens",
                trailingText: "\(prefs[UserPreferences.detailsBackgroundBlur])",
                action: { settingsRouter.navigate(to: .moonfinDetailsBlur) }
            )

            SettingsListButton(
                icon: "aqi.low",
                heading: "Browsing Background Blur",
                caption: "Blur amount when browsing",
                trailingText: "\(prefs[UserPreferences.browsingBackgroundBlur])",
                action: { settingsRouter.navigate(to: .moonfinBrowsingBlur) }
            )

            SettingsListButton(
                icon: "sparkles",
                heading: "Seasonal Surprise",
                caption: "Decorative seasonal animations",
                trailingText: prefs[UserPreferences.seasonalSurprise].displayName,
                action: { settingsRouter.navigate(to: .moonfinSeasonalSurprise) }
            )

            SettingsToggleButton(
                icon: "rectangle.inset.filled",
                heading: "Media Bar",
                caption: "Featured slideshow on home screen",
                isOn: prefs.binding(for: UserPreferences.mediaBarEnabled)
            )

            SettingsListButton(
                icon: "film.stack",
                heading: "Media Bar Content",
                caption: "What to show in the media bar",
                trailingText: prefs[UserPreferences.mediaBarContentType].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarContentType) }
            )

            SettingsListButton(
                icon: "number",
                heading: "Media Bar Items",
                caption: "Number of slides",
                trailingText: prefs[UserPreferences.mediaBarItemCount].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarItemCount) }
            )

            SettingsListButton(
                icon: "circle.lefthalf.filled.inverse",
                heading: "Media Bar Overlay",
                caption: "Overlay opacity",
                trailingText: "\(prefs[UserPreferences.mediaBarOverlayOpacity])%",
                action: { settingsRouter.navigate(to: .moonfinMediaBarOpacity) }
            )

            SettingsListButton(
                icon: "paintpalette",
                heading: "Media Bar Color",
                caption: "Overlay color",
                trailingText: prefs[UserPreferences.mediaBarOverlayColor].displayName,
                action: { settingsRouter.navigate(to: .moonfinMediaBarColor) }
            )

            SettingsToggleButton(
                icon: "play.rectangle",
                heading: "Trailer Preview",
                caption: "Play trailers in media bar",
                isOn: prefs.binding(for: UserPreferences.mediaBarTrailerPreview)
            )

            SettingsToggleButton(
                icon: "tv",
                heading: "Episode Preview",
                caption: "Show episode previews on detail screens",
                isOn: prefs.binding(for: UserPreferences.episodePreviewEnabled)
            )

            SettingsToggleButton(
                icon: "speaker.wave.1",
                heading: "Preview Audio",
                caption: "Play audio during previews",
                isOn: prefs.binding(for: UserPreferences.previewAudioEnabled)
            )

            SettingsToggleButton(
                icon: "music.note",
                heading: "Theme Music",
                caption: "Play theme music on detail screens",
                isOn: prefs.binding(for: UserPreferences.themeMusicEnabled)
            )

            SettingsToggleButton(
                icon: "music.note.house",
                heading: "Theme Music on Home Rows",
                caption: "Play when browsing home rows",
                isOn: prefs.binding(for: UserPreferences.themeMusicOnHomeRows)
            )

            SettingsListButton(
                icon: "speaker.wave.2",
                heading: "Theme Music Volume",
                caption: "Playback volume",
                trailingText: "\(prefs[UserPreferences.themeMusicVolume])%",
                action: { settingsRouter.navigate(to: .moonfinThemeMusicVolume) }
            )

            SettingsListButton(
                icon: "film",
                heading: "Jellyseerr",
                caption: "Media request management",
                trailingText: container.seerrRepository.isAvailable.value ? "On" : "Off",
                action: { settingsRouter.navigate(to: .seerr) }
            )

            SettingsListButton(
                icon: "lock.shield",
                heading: "Parental Controls",
                caption: "Block content by rating",
                trailingText: container.parentalControlsRepository.isEnabled ? "On" : "Off",
                action: { settingsRouter.navigate(to: .moonfinParentalControls) }
            )

            SettingsListButton(
                icon: "person.2.fill",
                heading: "SyncPlay",
                caption: "Synchronized playback settings",
                trailingText: prefs[UserPreferences.syncPlayEnabled] ? "On" : "Off",
                action: { settingsRouter.navigate(to: .moonfinSyncPlay) }
            )

            SettingsToggleButton(
                icon: "server.rack",
                heading: "Multi-Server",
                caption: "Aggregate content from all logged-in servers",
                isOn: prefs.binding(for: UserPreferences.enableMultiServerLibraries)
            )

            if pluginEnabled {
                SettingsToggleButton(
                    icon: "star.fill",
                    heading: "Additional Ratings",
                    caption: "Show MDBList ratings on media bar",
                    isOn: prefs.binding(for: UserPreferences.enableAdditionalRatings)
                )

                SettingsToggleButton(
                    icon: "tv",
                    heading: "Episode Ratings",
                    caption: "Show TMDB episode ratings",
                    isOn: prefs.binding(for: UserPreferences.enableEpisodeRatings)
                )

                SettingsToggleButton(
                    icon: "textformat",
                    heading: "Rating Labels",
                    caption: "Show text labels next to rating icons",
                    isOn: prefs.binding(for: UserPreferences.showRatingLabels)
                )
            }
        }
    }

    private var pluginSyncBinding: Binding<Bool> {
        Binding(
            get: { prefs[UserPreferences.pluginSyncEnabled] },
            set: { newValue in
                prefs[UserPreferences.pluginSyncEnabled] = newValue
                if newValue {
                    Task { await container.pluginSyncService.initialSync() }
                } else {
                    container.pluginSyncService.unregisterChangeListener()
                }
            }
        )
    }
}
