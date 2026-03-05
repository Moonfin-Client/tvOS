import Foundation

final class UserPreferences {
    private var store: PreferenceStore

    static let maxBitrate = Preference(key: "playback_max_bitrate", defaultValue: 0)
    static let maxResolution = Preference(key: "playback_max_resolution", defaultValue: "")
    static let nextUpBehavior = Preference(key: "playback_next_up_behavior", defaultValue: NextUpBehavior.extended)
    static let resumeSubtractDuration = Preference(key: "playback_resume_subtract", defaultValue: "")
    static let audioBehavior = Preference(key: "playback_audio_behavior", defaultValue: AudioBehavior.defaultTrack)

    static let navbarPosition = Preference(key: "navbar_position", defaultValue: NavbarPosition.top)
    static let shuffleContentType = Preference(key: "shuffle_content_type", defaultValue: ShuffleContentType.both)

    static let homeSections = Preference(key: "home_active_sections", defaultValue: "")
    static let homePosterSize = Preference(key: "home_poster_size", defaultValue: PosterSize.medium)
    static let homeRowsImageType = Preference(key: "home_rows_image_type", defaultValue: ImageDisplayType.poster)

    static let screensaverTimeout = Preference(key: "screensaver_timeout", defaultValue: 5)
    static let screensaverMode = Preference(key: "screensaver_mode", defaultValue: ScreensaverMode.logo)

    static let clockBehavior = Preference(key: "clock_behavior", defaultValue: ClockBehavior.always)
    static let watchedIndicator = Preference(key: "watched_indicator", defaultValue: WatchedIndicatorBehavior.always)

    static let backdropEnabled = Preference(key: "backdrop_enabled", defaultValue: true)
    static let detailsBackgroundBlur = Preference(key: "details_background_blur", defaultValue: 10)
    static let browsingBackgroundBlur = Preference(key: "browsing_background_blur", defaultValue: 10)

    static let telemetryEnabled = Preference(key: "telemetry_enabled", defaultValue: false)

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
    case small
    case medium
    case large

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

enum ImageDisplayType: String, StringRepresentableEnum, CaseIterable {
    case poster
    case thumb
    case banner

    var displayName: String {
        switch self {
        case .poster: return "Poster"
        case .thumb: return "Thumbnail"
        case .banner: return "Banner"
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
        case .showcase: return "Showcase"
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
