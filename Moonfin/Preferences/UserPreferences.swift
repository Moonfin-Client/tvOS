import Foundation

final class UserPreferences {
    private var store: PreferenceStore

    // MARK: - Playback

    static let maxBitrate = Preference(key: "playback_max_bitrate", defaultValue: 0)
    static let maxResolution = Preference(key: "playback_max_resolution", defaultValue: "")
    static let nextUpBehavior = Preference(key: "playback_next_up_behavior", defaultValue: NextUpBehavior.extended)
    static let resumeSubtractDuration = Preference(key: "playback_resume_subtract", defaultValue: "")
    static let audioBehavior = Preference(key: "playback_audio_behavior", defaultValue: AudioBehavior.defaultTrack)

    // MARK: - Navigation

    static let navbarPosition = Preference(key: "navbar_position", defaultValue: NavbarPosition.top)

    // MARK: - Home

    static let homeSections = Preference(key: "home_active_sections", defaultValue: "")
    static let homePosterSize = Preference(key: "home_poster_size", defaultValue: PosterSize.medium)
    static let homeRowsImageType = Preference(key: "home_rows_image_type", defaultValue: ImageDisplayType.poster)

    // MARK: - Screensaver

    static let screensaverTimeout = Preference(key: "screensaver_timeout", defaultValue: 5)
    static let screensaverMode = Preference(key: "screensaver_mode", defaultValue: ScreensaverMode.logo)

    // MARK: - Customization

    static let clockBehavior = Preference(key: "clock_behavior", defaultValue: ClockBehavior.always)
    static let watchedIndicator = Preference(key: "watched_indicator", defaultValue: WatchedIndicatorBehavior.always)

    // MARK: - Backdrop

    static let backdropEnabled = Preference(key: "backdrop_enabled", defaultValue: true)
    static let detailsBackgroundBlur = Preference(key: "details_background_blur", defaultValue: 10)
    static let browsingBackgroundBlur = Preference(key: "browsing_background_blur", defaultValue: 10)

    // MARK: - Telemetry

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
}

enum AudioBehavior: String, StringRepresentableEnum, CaseIterable {
    case defaultTrack
    case previouslySelected
}

enum NavbarPosition: String, StringRepresentableEnum, CaseIterable {
    case top
    case left
}

enum PosterSize: String, StringRepresentableEnum, CaseIterable {
    case small
    case medium
    case large
}

enum ImageDisplayType: String, StringRepresentableEnum, CaseIterable {
    case poster
    case thumb
    case banner
}

enum ScreensaverMode: String, StringRepresentableEnum, CaseIterable {
    case logo
    case showcase
    case nowPlaying
}

enum ClockBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case inNavOnly
    case never
}

enum WatchedIndicatorBehavior: String, StringRepresentableEnum, CaseIterable {
    case always
    case never
    case hideAfterWatched
}
