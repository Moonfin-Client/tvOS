import Foundation
import SwiftUI
import Combine
import Darwin

private func userPreferencesLocalized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

final class UserPreferences: ObservableObject {
    private var store: PreferenceStore
    let objectWillChange = ObservableObjectPublisher()

    static let maxBitrate = Preference(key: "playback_max_bitrate", defaultValue: 0)
    static let maxResolution = Preference(key: "playback_max_resolution", defaultValue: "")
    static let nextUpBehavior = Preference(key: "playback_next_up_behavior", defaultValue: NextUpBehavior.extended)
    static let resumeSubtractDuration = Preference(key: "playback_resume_subtract", defaultValue: 0)
    static let audioBehavior = Preference(key: "playback_audio_behavior", defaultValue: AudioBehavior.defaultTrack)
    static let audioOutput = Preference(key: "playback_audio_output", defaultValue: AudioOutput.directStream)
    static let lastAudioLanguage = Preference(key: "playback_last_audio_language", defaultValue: "")
    static let skipForwardLength = Preference(key: "playback_skip_forward", defaultValue: 30)
    static let unpauseRewindDuration = Preference(key: "playback_unpause_rewind", defaultValue: 0)
    static let showDescriptionOnPause = Preference(key: "playback_show_description_pause", defaultValue: false)
    static let maxVideoResolution = Preference(key: "playback_max_resolution_enum", defaultValue: MaxVideoResolution.auto)
    static let playbackQualityProfile = Preference(key: "playback_quality_profile", defaultValue: PlaybackQualityProfile.auto)
    static let playerZoomMode = Preference(key: "playback_zoom_mode", defaultValue: ZoomMode.fit)
    static let audioNightMode = Preference(key: "playback_audio_night_mode", defaultValue: false)
    static let liveTvDirectPlay = Preference(key: "playback_livetv_direct_play", defaultValue: true)
    static let videoStartDelay = Preference(key: "playback_video_start_delay", defaultValue: 0)
    static let cinemaModeEnabled = Preference(key: "cinema_mode_enabled", defaultValue: true)
    static let nativeDvDecodeEnabled = Preference(key: "native_dv_decode_enabled", defaultValue: true)
    static let hardwareDecoding = Preference(key: "hardware_decoding", defaultValue: true)
    static let refreshRateSwitchingBehavior = Preference(
        key: "refresh_rate_switching_behavior",
        defaultValue: RefreshRateSwitchingBehavior.disabled
    )
    static let skipBackLength = Preference(key: "playback_skip_back", defaultValue: 10_000)

    static let navbarPosition = Preference(key: "navbar_position", defaultValue: NavbarPosition.top)
    static let navbarColor = Preference(key: "navbar_color", defaultValue: MediaBarOverlayColor.gray)
    static let navbarOpacity = Preference(key: "navbar_opacity", defaultValue: 100)
    static let shuffleContentType = Preference(key: "shuffle_content_type", defaultValue: ShuffleContentType.both)

    static let homeSections = Preference(key: "home_active_sections", defaultValue: "")
    static let homePosterSize = Preference(key: "home_poster_size", defaultValue: PosterSize.medium)
    static let homeRowsImageType = Preference(key: "home_rows_image_type", defaultValue: ImageDisplayType.poster)
    static let homeImageTypeContinueWatching = Preference(key: "home_image_type_continue_watching", defaultValue: ImageDisplayType.thumb)
    static let homeImageTypeNextUp = Preference(key: "home_image_type_next_up", defaultValue: ImageDisplayType.thumb)
    static let homeImageTypeMyMedia = Preference(key: "home_image_type_my_media", defaultValue: ImageDisplayType.thumb)
    static let homeImageTypeLibraries = Preference(key: "home_image_type_libraries", defaultValue: ImageDisplayType.poster)
    static let homeImageTypeLiveTv = Preference(key: "home_image_type_live_tv", defaultValue: ImageDisplayType.thumb)
    static let homeImageUseSeriesImage = Preference(key: "home_image_use_series_image", defaultValue: false)
    static let displayFavoritesRows = Preference(key: "display_favorites_rows", defaultValue: true)
    static let favoritesRowSortBy = Preference(key: "favorites_row_sort_by", defaultValue: HomeRowSortBy.name)
    static let displayCollectionsRows = Preference(key: "display_collections_rows", defaultValue: true)
    static let collectionsRowSortBy = Preference(key: "collections_row_sort_by", defaultValue: HomeRowSortBy.name)
    static let displayGenresRows = Preference(key: "display_genres_rows", defaultValue: true)
    static let genresRowSortBy = Preference(key: "genres_row_sort_by", defaultValue: HomeRowSortBy.name)
    static let genresRowItems = Preference(key: "genres_row_items", defaultValue: GenresRowItems.both)
    static let homeRowInfoOverlay = Preference(key: "home_row_info_overlay", defaultValue: true)
    static let homeRowsStyle = Preference(key: "home_rows_style", defaultValue: HomeRowsStyle.v2)

    static let screensaverEnabled = Preference(key: "screensaver_enabled", defaultValue: true)
    static let screensaverTimeout = Preference(key: "screensaver_timeout", defaultValue: 5)
    static let screensaverMode = Preference(key: "screensaver_mode", defaultValue: ScreensaverMode.showcase)
    static let screensaverDimmingLevel = Preference(key: "screensaver_dimming_level", defaultValue: 0)
    static let screensaverShowClock = Preference(key: "screensaver_show_clock", defaultValue: true)
    static let screensaverAgeRatingRequired = Preference(key: "screensaver_age_rating_required", defaultValue: true)
    static let screensaverAgeRatingMax = Preference(key: "screensaver_age_rating_max", defaultValue: 13)

    static let clockBehavior = Preference(key: "clock_behavior", defaultValue: ClockBehavior.always)
    static let watchedIndicator = Preference(key: "watched_indicator", defaultValue: WatchedIndicatorBehavior.always)

    static let mediaBarEnabled = Preference(key: "media_bar_enabled", defaultValue: true)
    static let mediaBarContentType = Preference(key: "media_bar_content_type", defaultValue: MediaBarContentType.both)
    static let mediaBarItemCount = Preference(key: "media_bar_item_count", defaultValue: MediaBarItemCount.ten)
    static let mediaBarOverlayOpacity = Preference(key: "media_bar_overlay_opacity", defaultValue: 50)
    static let mediaBarOverlayColor = Preference(key: "media_bar_overlay_color", defaultValue: MediaBarOverlayColor.gray)
    static let mediaBarSourceType = Preference(key: "media_bar_source_type", defaultValue: MediaBarSourceType.library)
    static let mediaBarLibraryIds = Preference(key: "media_bar_library_ids", defaultValue: [String]())
    static let mediaBarCollectionIds = Preference(key: "media_bar_collection_ids", defaultValue: [String]())
    static let mediaBarExcludedGenres = Preference(key: "media_bar_excluded_genres", defaultValue: [String]())

    static let enableAdditionalRatings = Preference(key: "enable_additional_ratings", defaultValue: false)
    static let enableEpisodeRatings = Preference(key: "enable_episode_ratings", defaultValue: false)
    static let showRatingLabels = Preference(key: "show_rating_labels", defaultValue: true)
    static let showRatingBadges = Preference(key: "show_rating_badges", defaultValue: true)
    static let enabledRatings = Preference(
        key: "enabled_ratings",
        defaultValue: SettingsRatingSource.defaultOrder.map(\.rawValue)
    )

    static let backdropEnabled = Preference(key: "backdrop_enabled", defaultValue: true)
    static let detailsBackgroundBlur = Preference(key: "details_background_blur", defaultValue: 10)
    static let browsingBackgroundBlur = Preference(key: "browsing_background_blur", defaultValue: 10)

    static let seasonalSurprise = Preference(key: "seasonal_surprise", defaultValue: SeasonalSurprise.none)

    static let nextUpTimeout = Preference(key: "playback_next_up_timeout", defaultValue: 30)

    static let mergeContinueWatchingNextUp = Preference(key: "merge_continue_next_up", defaultValue: false)
    static let enableFolderView = Preference(key: "enable_folder_view", defaultValue: false)
    static let mediaBarTrailerPreview = Preference(key: "media_bar_trailer_preview", defaultValue: true)
    static let mediaBarTrailerAudio = Preference(key: "media_bar_trailer_audio", defaultValue: true)
    static let mediaBarMode = Preference(key: "media_bar_mode", defaultValue: MediaBarMode.moonfin)
    static let mediaBarAutoAdvance = Preference(key: "media_bar_auto_advance", defaultValue: true)
    static let mediaBarIntervalMs = Preference(key: "media_bar_interval_ms", defaultValue: 10_000)
    static let mediaPreviewEnabled = Preference(key: "episode_preview_enabled", defaultValue: true)
    static let previewAudioEnabled = Preference(key: "preview_audio_enabled", defaultValue: true)

    static let trickPlayEnabled = Preference(key: "trickplay_enabled", defaultValue: false)

    static let pluginSyncEnabled = Preference(key: "plugin_sync_enabled", defaultValue: false)
    static let pluginSyncAutoDetected = Preference(key: "plugin_sync_auto_detected", defaultValue: false)
    static let pluginCustomizationProfile = Preference(
        key: "plugin_customization_profile",
        defaultValue: PluginCustomizationProfile.tv
    )

    static let visualTheme = Preference(key: "visual_theme", defaultValue: VisualThemeId.moonfin)
    static let customThemeId = Preference(key: "pref_custom_theme_id", defaultValue: "")

    static let themeMusicEnabled = Preference(key: "theme_music_enabled", defaultValue: false)
    static let themeMusicVolume = Preference(key: "theme_music_volume", defaultValue: 30)
    static let themeMusicOnHomeRows = Preference(key: "theme_music_on_home_rows", defaultValue: false)

    static let telemetryEnabled = Preference(key: "telemetry_enabled", defaultValue: false)

    static let subtitlesTextColor = Preference(key: "subtitles_text_color", defaultValue: SubtitleColor.white)
    static let subtitlesBackgroundColor = Preference(key: "subtitles_background_color", defaultValue: SubtitleColor.transparent)
    static let subtitlesStrokeColor = Preference(key: "subtitles_text_stroke_color", defaultValue: SubtitleColor.black)
    static let subtitlesTextSize = Preference(key: "subtitles_text_size", defaultValue: 24)
    static let subtitlesOffsetPosition = Preference(key: "subtitles_offset_position", defaultValue: 8)
    static let subtitlesDefaultToNone = Preference(key: "subtitles_default_to_none", defaultValue: false)
    static let defaultSubtitleLanguage = Preference(
        key: "default_subtitle_language",
        defaultValue: DefaultSubtitleLanguage.none
    )
    static let pgsDirectPlay = Preference(key: "subtitles_pgs_direct_play", defaultValue: true)
    static let assDirectPlay = Preference(key: "subtitles_ass_direct_play", defaultValue: true)
    static let subtitlesOverrideASSStyles = Preference(key: "subtitles_override_ass_styles", defaultValue: false)
    static let defaultAudioLanguage = Preference(key: "default_audio_language", defaultValue: DefaultAudioLanguage.auto)
    static let ac3Enabled = Preference(key: "audio_ac3_enabled", defaultValue: false)
    static let trueHdEnabled = Preference(key: "audio_truehd_enabled", defaultValue: false)

    static let stillWatchingThreshold = Preference(key: "still_watching_threshold", defaultValue: 3)
    static let mediaQueuingEnabled = Preference(key: "media_queuing_enabled", defaultValue: true)

    static let mediaSegmentActions = Preference(
        key: "media_segment_actions",
        defaultValue: "Intro=askToSkip,Outro=askToSkip"
    )

    static let photoSlideshowInterval = Preference(key: "photo_slideshow_interval", defaultValue: SlideshowInterval.medium)

    static let liveTvChannelOrder = Preference(key: "livetv_channel_order", defaultValue: LiveTvChannelOrder.channelNumber)
    static let liveTvFavsAtTop = Preference(key: "livetv_favs_at_top", defaultValue: true)
    static let liveTvColorCodeGuide = Preference(key: "livetv_color_code_guide", defaultValue: false)
    static let liveTvShowHDIndicator = Preference(key: "livetv_show_hd_indicator", defaultValue: false)
    static let liveTvShowNewIndicator = Preference(key: "livetv_show_new_indicator", defaultValue: true)
    static let liveTvShowRepeatIndicator = Preference(key: "livetv_show_repeat_indicator", defaultValue: false)
    static let liveTvShowLiveIndicator = Preference(key: "livetv_show_live_indicator", defaultValue: false)

    static let liveTvFilterMovies = Preference(key: "livetv_filter_movies", defaultValue: false)
    static let liveTvFilterSeries = Preference(key: "livetv_filter_series", defaultValue: false)
    static let liveTvFilterNews = Preference(key: "livetv_filter_news", defaultValue: false)
    static let liveTvFilterKids = Preference(key: "livetv_filter_kids", defaultValue: false)
    static let liveTvFilterSports = Preference(key: "livetv_filter_sports", defaultValue: false)
    static let liveTvFilterPremiere = Preference(key: "livetv_filter_premiere", defaultValue: false)

    static let syncPlayEnabled = Preference(key: "syncplay_enabled", defaultValue: false)
    static let syncPlayAdvancedCorrectionEnabled = Preference(key: "syncplay_advanced_correction_enabled", defaultValue: true)
    static let syncPlayEnableSyncCorrection = Preference(key: "syncplay_sync_correction", defaultValue: true)
    static let syncPlayUseSpeedToSync = Preference(key: "syncplay_speed_to_sync", defaultValue: true)
    static let syncPlayUseSkipToSync = Preference(key: "syncplay_skip_to_sync", defaultValue: true)
    static let syncPlayMinDelaySpeedToSync = Preference(key: "syncplay_min_delay_speed", defaultValue: 100)
    static let syncPlayMaxDelaySpeedToSync = Preference(key: "syncplay_max_delay_speed", defaultValue: 5000)
    static let syncPlaySpeedToSyncDuration = Preference(key: "syncplay_speed_duration", defaultValue: 1000)
    static let syncPlayMinDelaySkipToSync = Preference(key: "syncplay_min_delay_skip", defaultValue: 2000)
    static let syncPlayExtraTimeOffset = Preference(key: "syncplay_extra_offset", defaultValue: 0)

    static let enableMultiServerLibraries = Preference(key: "enable_multi_server_libraries", defaultValue: false)

    static let userPinEnabled = Preference(key: "user_pin_enabled", defaultValue: false)
    static let userPinHash = Preference(key: "user_pin_hash", defaultValue: "")
    static let confirmExit = Preference(key: "confirm_exit", defaultValue: true)
    static let use24HourClock = Preference(key: "use_24_hour_clock", defaultValue: false)
    static let cardFocusExpansion = Preference(key: "card_focus_expansion", defaultValue: true)
    static let preferSystemImeKeyboard = Preference(key: "prefer_system_ime_keyboard", defaultValue: false)
    static let showSyncPlayButton = Preference(key: "show_syncplay_button", defaultValue: true)

    static let showShuffleButton = Preference(key: "navbar_show_shuffle", defaultValue: true)
    static let showGenresButton = Preference(key: "navbar_show_genres", defaultValue: true)
    static let showFavoritesButton = Preference(key: "navbar_show_favorites", defaultValue: true)
    static let showLibrariesInToolbar = Preference(key: "navbar_show_libraries", defaultValue: true)

    init(store: PreferenceStore) {
        self.store = store
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { store[preference] }
        set {
            objectWillChange.send()
            store[preference] = newValue
        }
    }
}

enum NextUpBehavior: String, StringRepresentableEnum, CaseIterable {
    case extended
    case minimal
    case disabled

    var displayName: String {
        switch self {
        case .extended: return userPreferencesLocalized("next_up_extended")
        case .minimal: return userPreferencesLocalized("next_up_minimal")
        case .disabled: return userPreferencesLocalized("disabled")
        }
    }
}

enum AudioBehavior: String, StringRepresentableEnum, CaseIterable {
    case defaultTrack
    case previouslySelected

    var displayName: String {
        switch self {
        case .defaultTrack: return userPreferencesLocalized("default_track")
        case .previouslySelected: return userPreferencesLocalized("previously_selected")
        }
    }
}

enum AudioOutput: String, StringRepresentableEnum, CaseIterable {
    case directStream
    case passthroughAtmos
    case downmixToStereo

    var displayName: String {
        switch self {
        case .directStream: return userPreferencesLocalized("direct_stream")
        case .passthroughAtmos:
            return Bundle.main.localizedString(
                forKey: "passthrough_atmos",
                value: "Passthrough (Dolby Atmos)",
                table: nil
            )
        case .downmixToStereo: return userPreferencesLocalized("downmix_to_stereo")
        }
    }
}

enum NavbarPosition: String, StringRepresentableEnum, CaseIterable {
    case top
    case left

    var displayName: String {
        switch self {
        case .top: return userPreferencesLocalized("top")
        case .left: return userPreferencesLocalized("left")
        }
    }
}

enum ShuffleContentType: String, StringRepresentableEnum, CaseIterable {
    case movies
    case tvShows
    case both

    var itemTypes: [ItemType] {
        switch self {
        case .movies: return [.movie]
        case .tvShows: return [.series]
        case .both: return [.movie, .series]
        }
    }

    var displayName: String {
        switch self {
        case .movies: return userPreferencesLocalized("movies")
        case .tvShows: return userPreferencesLocalized("tv_shows")
        case .both: return userPreferencesLocalized("both")
        }
    }
}

enum HomeRowSortBy: String, StringRepresentableEnum, CaseIterable {
    case name
    case dateAdded
    case premiereDate
    case rating
    case runtime
    case random
    case criticRating
    case communityRating

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .dateAdded: return "Date Added"
        case .premiereDate: return "Premiere Date"
        case .rating: return "Rating"
        case .runtime: return "Runtime"
        case .random: return "Random"
        case .criticRating: return "Critic Rating"
        case .communityRating: return "Community Rating"
        }
    }
}

enum GenresRowItems: String, StringRepresentableEnum, CaseIterable {
    case movies
    case series
    case both

    var displayName: String {
        switch self {
        case .movies: return userPreferencesLocalized("movies")
        case .series: return userPreferencesLocalized("tv_shows")
        case .both: return userPreferencesLocalized("both")
        }
    }
}

enum HomeRowsStyle: String, StringRepresentableEnum, CaseIterable {
    case v1
    case v2

    var displayName: String {
        switch self {
        case .v1: return "Classic"
        case .v2: return "Modern"
        }
    }
}

enum MediaBarMode: String, StringRepresentableEnum, CaseIterable {
    case moonfin
    case makd
    case off

    var displayName: String {
        switch self {
        case .moonfin: return "Moonfin"
        case .makd: return "MakD"
        case .off: return "Off"
        }
    }
}

enum RefreshRateSwitchingBehavior: String, StringRepresentableEnum, CaseIterable {
    case disabled
    case scaleOnTv
    case scaleOnDevice

    var displayName: String {
        switch self {
        case .disabled: return userPreferencesLocalized("disabled")
        case .scaleOnTv: return "Scale on TV"
        case .scaleOnDevice: return "Scale on Device"
        }
    }
}

enum DefaultAudioLanguage: String, StringRepresentableEnum, CaseIterable {
    case auto
    case eng
    case spa
    case fra
    case deu
    case ita
    case por
    case jpn
    case kor
    case zho
    case rus
    case ara
    case hin
    case nld
    case swe
    case nor
    case dan
    case fin
    case pol

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .eng: return "English"
        case .spa: return "Spanish"
        case .fra: return "French"
        case .deu: return "German"
        case .ita: return "Italian"
        case .por: return "Portuguese"
        case .jpn: return "Japanese"
        case .kor: return "Korean"
        case .zho: return "Chinese"
        case .rus: return "Russian"
        case .ara: return "Arabic"
        case .hin: return "Hindi"
        case .nld: return "Dutch"
        case .swe: return "Swedish"
        case .nor: return "Norwegian"
        case .dan: return "Danish"
        case .fin: return "Finnish"
        case .pol: return "Polish"
        }
    }
}

enum DefaultSubtitleLanguage: String, StringRepresentableEnum, CaseIterable {
    case none
    case eng
    case spa
    case fra
    case deu
    case ita
    case por
    case jpn
    case kor
    case zho
    case rus
    case ara
    case hin
    case nld
    case swe
    case nor
    case dan
    case fin
    case pol

    var displayName: String {
        switch self {
        case .none: return "None"
        case .eng: return "English"
        case .spa: return "Spanish"
        case .fra: return "French"
        case .deu: return "German"
        case .ita: return "Italian"
        case .por: return "Portuguese"
        case .jpn: return "Japanese"
        case .kor: return "Korean"
        case .zho: return "Chinese"
        case .rus: return "Russian"
        case .ara: return "Arabic"
        case .hin: return "Hindi"
        case .nld: return "Dutch"
        case .swe: return "Swedish"
        case .nor: return "Norwegian"
        case .dan: return "Danish"
        case .fin: return "Finnish"
        case .pol: return "Polish"
        }
    }
}

enum PluginCustomizationProfile: String, StringRepresentableEnum, CaseIterable {
    case global
    case desktop
    case mobile
    case tv

    var displayName: String {
        switch self {
        case .global: return "Global"
        case .desktop: return "Desktop"
        case .mobile: return "Mobile"
        case .tv: return "TV"
        }
    }
}

enum VisualThemeId: String, StringRepresentableEnum, CaseIterable {
    case moonfin
    case neonPulse

    var displayName: String {
        switch self {
        case .moonfin: return "Moonfin"
        case .neonPulse: return "Neon Pulse"
        }
    }
}

enum SettingsRatingSource: String, CaseIterable {
    case tomatoes
    case tomatoesAudience = "tomatoes_audience"
    case imdb
    case tmdb
    case metacritic
    case metacriticUser = "metacriticuser"
    case trakt
    case letterboxd
    case myanimelist
    case anilist
    case stars

    static let defaultOrder: [SettingsRatingSource] = [
        .tomatoes,
        .tomatoesAudience,
        .imdb,
        .tmdb,
        .metacritic,
        .metacriticUser,
        .trakt,
        .letterboxd,
        .myanimelist,
        .anilist,
        .stars,
    ]

    var displayName: String {
        switch self {
        case .tomatoes: return "Rotten Tomatoes"
        case .tomatoesAudience: return "RT Audience"
        case .imdb: return "IMDb"
        case .tmdb: return "TMDB"
        case .metacritic: return "Metacritic"
        case .metacriticUser: return "Metacritic User"
        case .trakt: return "Trakt"
        case .letterboxd: return "Letterboxd"
        case .myanimelist: return "MyAnimeList"
        case .anilist: return "AniList"
        case .stars: return "Stars"
        }
    }
}

enum PosterSize: String, StringRepresentableEnum, CaseIterable {
    case smallest
    case small
    case medium
    case large
    case xLarge

    var displayName: String {
        switch self {
        case .smallest: return userPreferencesLocalized("poster_size_smallest")
        case .small: return userPreferencesLocalized("poster_size_small")
        case .medium: return userPreferencesLocalized("poster_size_medium")
        case .large: return userPreferencesLocalized("poster_size_large")
        case .xLarge: return userPreferencesLocalized("poster_size_xlarge")
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .smallest: return 0.7
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.2
        case .xLarge: return 1.4
        }
    }
}

enum ImageDisplayType: String, StringRepresentableEnum, CaseIterable {
    case poster
    case thumb
    case banner
    case square

    var displayName: String {
        switch self {
        case .poster: return userPreferencesLocalized("image_type_poster")
        case .thumb: return userPreferencesLocalized("image_type_thumbnail")
        case .banner: return userPreferencesLocalized("image_type_banner")
        case .square: return userPreferencesLocalized("image_type_square")
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .poster: return 2.0 / 3.0
        case .thumb: return 16.0 / 9.0
        case .banner: return 16.0 / 9.0
        case .square: return 1.0
        }
    }

    static let homeRowOptions: [ImageDisplayType] = [.poster, .thumb, .banner]
}

enum ScreensaverMode: String, StringRepresentableEnum, CaseIterable {
    case logo
    case showcase
    case nowPlaying

    var displayName: String {
        switch self {
        case .logo: return userPreferencesLocalized("screensaver_logo")
        case .showcase: return userPreferencesLocalized("screensaver_library_showcase")
        case .nowPlaying: return userPreferencesLocalized("screensaver_now_playing")
        }
    }
}

enum ClockBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case inNavOnly
    case inVideo
    case never

    var displayName: String {
        switch self {
        case .always: return userPreferencesLocalized("always")
        case .inNavOnly: return userPreferencesLocalized("navigation_only")
        case .inVideo: return userPreferencesLocalized("in_video")
        case .never: return userPreferencesLocalized("never")
        }
    }
}

enum WatchedIndicatorBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case never
    case hideAfterWatched
    case episodesOnly

    var displayName: String {
        switch self {
        case .always: return userPreferencesLocalized("always")
        case .never: return userPreferencesLocalized("never")
        case .hideAfterWatched: return userPreferencesLocalized("hide_after_watched")
        case .episodesOnly: return userPreferencesLocalized("episodes_only")
        }
    }
}

enum SubtitleColor: String, StringRepresentableEnum, CaseIterable {
    case transparent
    case white
    case black
    case gray
    case red
    case green
    case blue
    case yellow
    case magenta
    case cyan

    var displayName: String {
        switch self {
        case .transparent: return userPreferencesLocalized("none")
        case .white: return userPreferencesLocalized("color_white")
        case .black: return userPreferencesLocalized("color_black")
        case .gray: return userPreferencesLocalized("color_gray")
        case .red: return userPreferencesLocalized("color_red")
        case .green: return userPreferencesLocalized("color_green")
        case .blue: return userPreferencesLocalized("color_blue")
        case .yellow: return userPreferencesLocalized("color_yellow")
        case .magenta: return userPreferencesLocalized("color_magenta")
        case .cyan: return userPreferencesLocalized("color_cyan")
        }
    }

    var argb: UInt32 {
        switch self {
        case .transparent: return 0x00FFFFFF
        case .white: return 0xFFFFFFFF
        case .black: return 0xFF000000
        case .gray: return 0xFF7F7F7F
        case .red: return 0xFFC80000
        case .green: return 0xFF00C800
        case .blue: return 0xFF0000C8
        case .yellow: return 0xFFEEDC00
        case .magenta: return 0xFFD60080
        case .cyan: return 0xFF009FDA
        }
    }

    var isTransparent: Bool { self == .transparent }

    var swiftUIColor: Color {
        let rgb = argb & 0x00FFFFFF
        let alpha = Double((argb >> 24) & 0xFF) / 255.0
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

enum SlideshowInterval: String, StringRepresentableEnum, CaseIterable {
    case short
    case medium
    case long
    case extraLong

    var seconds: Double {
        switch self {
        case .short: return 3
        case .medium: return 5
        case .long: return 8
        case .extraLong: return 10
        }
    }

    var displayName: String {
        switch self {
        case .short: return String(format: userPreferencesLocalized("slideshow_seconds"), 3)
        case .medium: return String(format: userPreferencesLocalized("slideshow_seconds"), 5)
        case .long: return String(format: userPreferencesLocalized("slideshow_seconds"), 8)
        case .extraLong: return String(format: userPreferencesLocalized("slideshow_seconds"), 10)
        }
    }
}

enum LiveTvChannelOrder: String, StringRepresentableEnum, CaseIterable {
    case channelNumber
    case lastPlayed

    var displayName: String {
        switch self {
        case .channelNumber: return userPreferencesLocalized("channel_number")
        case .lastPlayed: return userPreferencesLocalized("last_played")
        }
    }
}

enum MaxVideoResolution: String, StringRepresentableEnum, CaseIterable {
    case auto
    case res480p
    case res720p
    case res1080p
    case res2160p

    var displayName: String {
        switch self {
        case .auto: return userPreferencesLocalized("option_auto")
        case .res480p: return "480p"
        case .res720p: return "720p"
        case .res1080p: return "1080p"
        case .res2160p: return "4K"
        }
    }
}

enum PlaybackQualityProfile: String, StringRepresentableEnum, CaseIterable {
    case auto
    case compatibility
    case highQuality

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .compatibility: return "Compatibility"
        case .highQuality: return "High Quality"
        }
    }

    static func recommended(for generation: VideoCapabilityDetector.AppleTVGeneration) -> PlaybackQualityProfile {
        switch generation {
        case .k4Gen3:
            return .highQuality
        case .hd, .k4Gen1, .k4Gen2, .unknown:
            return .compatibility
        }
    }

    static func autoSummaryDisplayName(for generation: VideoCapabilityDetector.AppleTVGeneration) -> String {
        let recommendedProfile = recommended(for: generation)
        return "Auto (\(recommendedProfile.displayName) recommended)"
    }

    func pickerDisplayName(for generation: VideoCapabilityDetector.AppleTVGeneration) -> String {
        if self == PlaybackQualityProfile.recommended(for: generation) {
            return "\(displayName) (Recommended)"
        }
        return displayName
    }
}

enum SeasonalSurprise: String, StringRepresentableEnum, CaseIterable {
    case none
    case winter
    case spring
    case summer
    case halloween
    case fall

    var displayName: String {
        switch self {
        case .none: return userPreferencesLocalized("none")
        case .winter: return userPreferencesLocalized("season_winter")
        case .spring: return userPreferencesLocalized("season_spring")
        case .summer: return userPreferencesLocalized("season_summer")
        case .halloween: return userPreferencesLocalized("season_halloween")
        case .fall: return userPreferencesLocalized("season_fall")
        }
    }
}
