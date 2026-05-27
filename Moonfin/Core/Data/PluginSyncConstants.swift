import Foundation

enum SyncType {
    case boolean
    case int
    case string
    case `enum`
    case list
}

enum PreferenceSource {
    case user
    case seerr
    case parental
}

struct SyncablePreference {
    let key: String
    let type: SyncType
    let serverKey: String
    let defaultValue: Any
    let source: PreferenceSource

    init(key: String, type: SyncType, serverKey: String, defaultValue: Any, source: PreferenceSource = .user) {
        self.key = key
        self.type = type
        self.serverKey = serverKey
        self.defaultValue = defaultValue
        self.source = source
    }
}

enum PluginSyncConstants {
    static let snapshotKey = "moonfin_sync_snapshot"
    static let snapshotVersionKey = "_snapshot_version"
    static let snapshotVersion = 9
    static let clientId = "moonfin-appletv"
    static let pingPath = "/Moonfin/Ping"
    static let settingsPath = "/Moonfin/Settings"
    static let themesPath = "/Moonfin/Themes"
    static let mediaBarPath = "/Moonfin/MediaBar"
    static let jellyseerrConfigPath = "/Moonfin/Jellyseerr/Config"
    static let debounceMs: UInt64 = 500

    static let syncablePreferences: [SyncablePreference] = [
        SyncablePreference(key: "visual_theme", type: .enum, serverKey: "visualTheme", defaultValue: "moonfin"),
        SyncablePreference(key: "pref_custom_theme_id", type: .string, serverKey: "customThemeId", defaultValue: ""),

        SyncablePreference(key: "navbar_position", type: .enum, serverKey: "navbarPosition", defaultValue: "top"),
        SyncablePreference(key: "navbar_color", type: .enum, serverKey: "navbarColor", defaultValue: "gray"),
        SyncablePreference(key: "navbar_opacity", type: .int, serverKey: "navbarOpacity", defaultValue: 100),
        SyncablePreference(key: "shuffle_content_type", type: .enum, serverKey: "shuffleContentType", defaultValue: "both"),

        SyncablePreference(key: "navbar_show_shuffle", type: .boolean, serverKey: "showShuffleButton", defaultValue: true),
        SyncablePreference(key: "navbar_show_genres", type: .boolean, serverKey: "showGenresButton", defaultValue: true),
        SyncablePreference(key: "navbar_show_favorites", type: .boolean, serverKey: "showFavoritesButton", defaultValue: true),
        SyncablePreference(key: "navbar_show_libraries", type: .boolean, serverKey: "showLibrariesInToolbar", defaultValue: true),

        SyncablePreference(key: "merge_continue_next_up", type: .boolean, serverKey: "mergeContinueWatchingNextUp", defaultValue: false),
        SyncablePreference(key: "enable_folder_view", type: .boolean, serverKey: "enableFolderView", defaultValue: false),
        SyncablePreference(key: "seasonal_surprise", type: .enum, serverKey: "seasonalSurprise", defaultValue: "none"),
        SyncablePreference(key: "theme_music_on_home_rows", type: .boolean, serverKey: "themeMusicOnHomeRows", defaultValue: false),

        SyncablePreference(key: "media_bar_enabled", type: .boolean, serverKey: "mediaBarEnabled", defaultValue: true),
        SyncablePreference(key: "media_bar_mode", type: .enum, serverKey: "mediaBarMode", defaultValue: "moonfin"),
        SyncablePreference(key: "media_bar_content_type", type: .enum, serverKey: "mediaBarContentType", defaultValue: "both"),
        SyncablePreference(key: "media_bar_item_count", type: .enum, serverKey: "mediaBarItemCount", defaultValue: "10"),
        SyncablePreference(key: "media_bar_overlay_opacity", type: .int, serverKey: "mediaBarOpacity", defaultValue: 50),
        SyncablePreference(key: "media_bar_overlay_color", type: .enum, serverKey: "mediaBarOverlayColor", defaultValue: "gray"),
        SyncablePreference(key: "media_bar_auto_advance", type: .boolean, serverKey: "mediaBarAutoAdvance", defaultValue: true),
        SyncablePreference(key: "media_bar_interval_ms", type: .int, serverKey: "mediaBarIntervalMs", defaultValue: 10_000),
        SyncablePreference(key: "media_bar_trailer_preview", type: .boolean, serverKey: "mediaBarTrailerPreview", defaultValue: true),
        SyncablePreference(key: "media_bar_trailer_audio", type: .boolean, serverKey: "mediaBarTrailerAudio", defaultValue: true),
        SyncablePreference(key: "media_bar_source_type", type: .enum, serverKey: "mediaBarSourceType", defaultValue: "library"),
        SyncablePreference(key: "media_bar_library_ids", type: .list, serverKey: "mediaBarLibraryIds", defaultValue: [String]()),
        SyncablePreference(key: "media_bar_collection_ids", type: .list, serverKey: "mediaBarCollectionIds", defaultValue: [String]()),
        SyncablePreference(key: "media_bar_excluded_genres", type: .list, serverKey: "mediaBarExcludedGenres", defaultValue: [String]()),

        SyncablePreference(key: "theme_music_enabled", type: .boolean, serverKey: "themeMusicEnabled", defaultValue: false),
        SyncablePreference(key: "theme_music_volume", type: .int, serverKey: "themeMusicVolume", defaultValue: 30),

        SyncablePreference(key: "backdrop_enabled", type: .boolean, serverKey: "backdropEnabled", defaultValue: true),
        SyncablePreference(key: "details_background_blur", type: .int, serverKey: "detailsScreenBlur", defaultValue: 10),
        SyncablePreference(key: "browsing_background_blur", type: .int, serverKey: "browsingBlur", defaultValue: 10),
        SyncablePreference(key: "home_rows_style", type: .enum, serverKey: "homeRowsStyle", defaultValue: "v2"),
        SyncablePreference(key: "home_rows_image_type_override", type: .boolean, serverKey: "homeRowsImageTypeOverride", defaultValue: false),
        SyncablePreference(key: "home_poster_size", type: .enum, serverKey: "posterSize", defaultValue: "medium"),
        SyncablePreference(key: "display_favorites_rows", type: .boolean, serverKey: "displayFavoritesRows", defaultValue: true),
        SyncablePreference(key: "display_collections_rows", type: .boolean, serverKey: "displayCollectionsRows", defaultValue: true),
        SyncablePreference(key: "display_genres_rows", type: .boolean, serverKey: "displayGenresRows", defaultValue: true),
        SyncablePreference(key: "favorites_row_sort_by", type: .enum, serverKey: "favoritesRowSortBy", defaultValue: "name"),
        SyncablePreference(key: "collections_row_sort_by", type: .enum, serverKey: "collectionsRowSortBy", defaultValue: "name"),
        SyncablePreference(key: "genres_row_sort_by", type: .enum, serverKey: "genresRowSortBy", defaultValue: "name"),
        SyncablePreference(key: "genres_row_items", type: .enum, serverKey: "genresRowItemFilter", defaultValue: "both"),
        SyncablePreference(key: "home_rows_image_type", type: .enum, serverKey: "homeRowsImageType", defaultValue: "poster"),
        SyncablePreference(key: "home_image_type_continue_watching", type: .enum, serverKey: "homeImageTypeContinueWatching", defaultValue: "thumb"),
        SyncablePreference(key: "home_image_type_next_up", type: .enum, serverKey: "homeImageTypeNextUp", defaultValue: "thumb"),
        SyncablePreference(key: "home_image_type_my_media", type: .enum, serverKey: "homeImageTypeMyMedia", defaultValue: "thumb"),
        SyncablePreference(key: "home_image_type_libraries", type: .enum, serverKey: "homeImageTypeLibraries", defaultValue: "poster"),
        SyncablePreference(key: "home_image_type_live_tv", type: .enum, serverKey: "homeImageTypeLiveTv", defaultValue: "thumb"),
        SyncablePreference(key: "home_image_use_series_image", type: .boolean, serverKey: "homeImageUseSeriesImage", defaultValue: false),

        SyncablePreference(key: "enable_additional_ratings", type: .boolean, serverKey: "mdblistEnabled", defaultValue: false),
        SyncablePreference(key: "tmdb_api_key", type: .string, serverKey: "tmdbApiKey", defaultValue: ""),
        SyncablePreference(key: "enable_episode_ratings", type: .boolean, serverKey: "tmdbEpisodeRatingsEnabled", defaultValue: false),
        SyncablePreference(key: "show_rating_labels", type: .boolean, serverKey: "mdblistShowRatingNames", defaultValue: true),
        SyncablePreference(key: "show_rating_badges", type: .boolean, serverKey: "mdblistShowRatingBadges", defaultValue: true),
        SyncablePreference(key: "watched_indicator", type: .enum, serverKey: "watchedIndicator", defaultValue: "always"),

        SyncablePreference(key: "enable_multi_server_libraries", type: .boolean, serverKey: "enableMultiServerLibraries", defaultValue: false),

        SyncablePreference(key: "user_pin_enabled", type: .boolean, serverKey: "userPinEnabled", defaultValue: false),
        SyncablePreference(key: "user_pin_hash", type: .string, serverKey: "userPinHash", defaultValue: ""),

        SyncablePreference(key: "seerr_enabled", type: .boolean, serverKey: "jellyseerrEnabled", defaultValue: false, source: .seerr),
        SyncablePreference(key: "seerr_api_key", type: .string, serverKey: "jellyseerrApiKey", defaultValue: "", source: .seerr),
        SyncablePreference(key: "seerr_block_nsfw", type: .boolean, serverKey: "jellyseerrBlockNsfw", defaultValue: true, source: .seerr),

        SyncablePreference(key: "syncplay_enabled", type: .boolean, serverKey: "showSyncPlayButton", defaultValue: false),

        SyncablePreference(key: "episode_preview_enabled", type: .boolean, serverKey: "episodePreviewEnabled", defaultValue: true),
        SyncablePreference(key: "preview_audio_enabled", type: .boolean, serverKey: "previewAudioEnabled", defaultValue: true),
        SyncablePreference(key: "card_focus_expansion", type: .boolean, serverKey: "cardFocusExpansion", defaultValue: true),
        SyncablePreference(key: "focus_color", type: .string, serverKey: "focusColor", defaultValue: ""),

        SyncablePreference(key: "blocked_ratings", type: .list, serverKey: "blockedRatings", defaultValue: [String](), source: .parental),

        SyncablePreference(key: "home_active_sections", type: .list, serverKey: "homeRowOrder", defaultValue: [String]()),
    ]

    static let allLocalKeys: Set<String> = Set(syncablePreferences.map(\.key))
    static let allServerKeys: Set<String> = Set(syncablePreferences.map(\.serverKey))
    static let serverToLocal: [String: SyncablePreference] = {
        Dictionary(uniqueKeysWithValues: syncablePreferences.map { ($0.serverKey, $0) })
    }()
    static let localToServer: [String: SyncablePreference] = {
        Dictionary(uniqueKeysWithValues: syncablePreferences.map { ($0.key, $0) })
    }()
}
