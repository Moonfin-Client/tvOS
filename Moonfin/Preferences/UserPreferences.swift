import Foundation
import SwiftUI

final class UserPreferences {
    private var store: PreferenceStore

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
    static let playerZoomMode = Preference(key: "playback_zoom_mode", defaultValue: ZoomMode.fit)
    static let audioNightMode = Preference(key: "playback_audio_night_mode", defaultValue: false)
    static let liveTvDirectPlay = Preference(key: "playback_livetv_direct_play", defaultValue: true)
    static let videoStartDelay = Preference(key: "playback_video_start_delay", defaultValue: 0)

    static let navbarPosition = Preference(key: "navbar_position", defaultValue: NavbarPosition.top)
    static let shuffleContentType = Preference(key: "shuffle_content_type", defaultValue: ShuffleContentType.both)

    static let homeSections = Preference(key: "home_active_sections", defaultValue: "")
    static let homePosterSize = Preference(key: "home_poster_size", defaultValue: PosterSize.medium)
    static let homeRowsImageType = Preference(key: "home_rows_image_type", defaultValue: ImageDisplayType.poster)

    static let screensaverEnabled = Preference(key: "screensaver_enabled", defaultValue: true)
    static let screensaverTimeout = Preference(key: "screensaver_timeout", defaultValue: 5)
    static let screensaverMode = Preference(key: "screensaver_mode", defaultValue: ScreensaverMode.showcase)
    static let screensaverDimmingLevel = Preference(key: "screensaver_dimming_level", defaultValue: 0)
    static let screensaverShowClock = Preference(key: "screensaver_show_clock", defaultValue: true)

    static let clockBehavior = Preference(key: "clock_behavior", defaultValue: ClockBehavior.always)
    static let watchedIndicator = Preference(key: "watched_indicator", defaultValue: WatchedIndicatorBehavior.always)

    static let mediaBarEnabled = Preference(key: "media_bar_enabled", defaultValue: true)
    static let mediaBarContentType = Preference(key: "media_bar_content_type", defaultValue: MediaBarContentType.both)
    static let mediaBarItemCount = Preference(key: "media_bar_item_count", defaultValue: MediaBarItemCount.ten)
    static let mediaBarOverlayOpacity = Preference(key: "media_bar_overlay_opacity", defaultValue: 50)
    static let mediaBarOverlayColor = Preference(key: "media_bar_overlay_color", defaultValue: MediaBarOverlayColor.gray)

    static let enableAdditionalRatings = Preference(key: "enable_additional_ratings", defaultValue: false)
    static let enableEpisodeRatings = Preference(key: "enable_episode_ratings", defaultValue: false)
    static let showRatingLabels = Preference(key: "show_rating_labels", defaultValue: true)

    static let backdropEnabled = Preference(key: "backdrop_enabled", defaultValue: true)
    static let detailsBackgroundBlur = Preference(key: "details_background_blur", defaultValue: 10)
    static let browsingBackgroundBlur = Preference(key: "browsing_background_blur", defaultValue: 10)

    static let seasonalSurprise = Preference(key: "seasonal_surprise", defaultValue: SeasonalSurprise.none)

    static let mergeContinueWatchingNextUp = Preference(key: "merge_continue_next_up", defaultValue: false)
    static let enableFolderView = Preference(key: "enable_folder_view", defaultValue: false)
    static let mediaBarTrailerPreview = Preference(key: "media_bar_trailer_preview", defaultValue: true)
    static let episodePreviewEnabled = Preference(key: "episode_preview_enabled", defaultValue: true)
    static let previewAudioEnabled = Preference(key: "preview_audio_enabled", defaultValue: true)

    static let pluginSyncEnabled = Preference(key: "plugin_sync_enabled", defaultValue: false)

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

    static let stillWatchingThreshold = Preference(key: "still_watching_threshold", defaultValue: 3)

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

    static let syncPlayEnabled = Preference(key: "syncplay_enabled", defaultValue: false)
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

    static let showShuffleButton = Preference(key: "navbar_show_shuffle", defaultValue: true)
    static let showGenresButton = Preference(key: "navbar_show_genres", defaultValue: true)
    static let showFavoritesButton = Preference(key: "navbar_show_favorites", defaultValue: true)
    static let showLibrariesInToolbar = Preference(key: "navbar_show_libraries", defaultValue: true)

    init(store: PreferenceStore) {
        self.store = store
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { store[preference] }
        set { store[preference] = newValue }
    }
}

enum NextUpBehavior: String, StringRepresentableEnum, CaseIterable {
    case extended
    case minimal
    case disabled

    var displayName: String {
        switch self {
        case .extended: return "Extended"
        case .minimal: return "Minimal"
        case .disabled: return "Disabled"
        }
    }
}

enum AudioBehavior: String, StringRepresentableEnum, CaseIterable {
    case defaultTrack
    case previouslySelected

    var displayName: String {
        switch self {
        case .defaultTrack: return "Default Track"
        case .previouslySelected: return "Previously Selected"
        }
    }
}

enum AudioOutput: String, StringRepresentableEnum, CaseIterable {
    case directStream
    case downmixToStereo

    var displayName: String {
        switch self {
        case .directStream: return "Direct Stream"
        case .downmixToStereo: return "Downmix to Stereo"
        }
    }
}

enum NavbarPosition: String, StringRepresentableEnum, CaseIterable {
    case top
    case left

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .left: return "Left"
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
        case .movies: return "Movies"
        case .tvShows: return "TV Shows"
        case .both: return "Both"
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
        case .smallest: return "Smallest"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xLarge: return "X-Large"
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
        case .poster: return "Poster"
        case .thumb: return "Thumbnail"
        case .banner: return "Banner"
        case .square: return "Square"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .poster: return 2.0 / 3.0
        case .thumb: return 16.0 / 9.0
        case .banner: return 16.0 / 3.0
        case .square: return 1.0
        }
    }
}

enum ScreensaverMode: String, StringRepresentableEnum, CaseIterable {
    case logo
    case showcase
    case nowPlaying

    var displayName: String {
        switch self {
        case .logo: return "Logo"
        case .showcase: return "Library Showcase"
        case .nowPlaying: return "Now Playing"
        }
    }
}

enum ClockBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case inNavOnly
    case never

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .inNavOnly: return "Navigation Only"
        case .never: return "Never"
        }
    }
}

enum WatchedIndicatorBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case never
    case hideAfterWatched

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .never: return "Never"
        case .hideAfterWatched: return "Hide After Watched"
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
        case .transparent: return "None"
        case .white: return "White"
        case .black: return "Black"
        case .gray: return "Gray"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .magenta: return "Magenta"
        case .cyan: return "Cyan"
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
        case .short: return "3 seconds"
        case .medium: return "5 seconds"
        case .long: return "8 seconds"
        case .extraLong: return "10 seconds"
        }
    }
}

enum LiveTvChannelOrder: String, StringRepresentableEnum, CaseIterable {
    case channelNumber
    case lastPlayed

    var displayName: String {
        switch self {
        case .channelNumber: return "Channel Number"
        case .lastPlayed: return "Last Played"
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
        case .auto: return "Auto"
        case .res480p: return "480p"
        case .res720p: return "720p"
        case .res1080p: return "1080p"
        case .res2160p: return "4K"
        }
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
        case .none: return "None"
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .halloween: return "Halloween"
        case .fall: return "Fall"
        }
    }
}
