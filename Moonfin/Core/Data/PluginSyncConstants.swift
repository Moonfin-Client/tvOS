import Foundation

enum SyncType {
    case boolean
    case int
    case string
    case `enum`
}

struct SyncablePreference {
    let key: String
    let type: SyncType
    let serverKey: String
    let defaultValue: Any
}

enum PluginSyncConstants {
    static let snapshotKey = "moonfin_sync_snapshot"
    static let snapshotVersionKey = "_snapshot_version"
    static let snapshotVersion = 2
    static let clientId = "moonfin-appletv"
    static let pingPath = "/Moonfin/Ping"
    static let settingsPath = "/Moonfin/Settings"
    static let debounceMs: UInt64 = 500

    static let syncablePreferences: [SyncablePreference] = [
        // Navbar
        SyncablePreference(key: "navbar_position", type: .enum, serverKey: "navbarPosition", defaultValue: "top"),
        SyncablePreference(key: "shuffle_content_type", type: .enum, serverKey: "shuffleContentType", defaultValue: "both"),

        // Media Bar
        SyncablePreference(key: "media_bar_enabled", type: .boolean, serverKey: "mediaBarEnabled", defaultValue: true),
        SyncablePreference(key: "media_bar_content_type", type: .enum, serverKey: "mediaBarContentType", defaultValue: "both"),
        SyncablePreference(key: "media_bar_item_count", type: .enum, serverKey: "mediaBarItemCount", defaultValue: "ten"),
        SyncablePreference(key: "media_bar_overlay_opacity", type: .int, serverKey: "mediaBarOpacity", defaultValue: 50),
        SyncablePreference(key: "media_bar_overlay_color", type: .enum, serverKey: "mediaBarOverlayColor", defaultValue: "gray"),

        // Display
        SyncablePreference(key: "backdrop_enabled", type: .boolean, serverKey: "backdropEnabled", defaultValue: true),
        SyncablePreference(key: "details_background_blur", type: .int, serverKey: "detailsScreenBlur", defaultValue: 10),
        SyncablePreference(key: "browsing_background_blur", type: .int, serverKey: "browsingBlur", defaultValue: 10),
        SyncablePreference(key: "home_rows_image_type", type: .enum, serverKey: "homeRowsImageType", defaultValue: "poster"),

        // Ratings
        SyncablePreference(key: "enable_additional_ratings", type: .boolean, serverKey: "mdblistEnabled", defaultValue: false),
        SyncablePreference(key: "enable_episode_ratings", type: .boolean, serverKey: "tmdbEpisodeRatingsEnabled", defaultValue: false),

        // Clock & Indicators
        SyncablePreference(key: "clock_behavior", type: .enum, serverKey: "clockBehavior", defaultValue: "always"),
        SyncablePreference(key: "watched_indicator", type: .enum, serverKey: "watchedIndicator", defaultValue: "always"),

        // Screensaver
        SyncablePreference(key: "screensaver_mode", type: .enum, serverKey: "screensaverMode", defaultValue: "logo"),
        SyncablePreference(key: "screensaver_timeout", type: .int, serverKey: "screensaverTimeout", defaultValue: 5),
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
