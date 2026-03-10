import Foundation

enum SeerrFetchLimit: String, StringRepresentableEnum, CaseIterable {
    case small
    case medium
    case large

    var limit: Int {
        switch self {
        case .small: return 25
        case .medium: return 50
        case .large: return 75
        }
    }

    var displayName: String {
        switch self {
        case .small: return "25"
        case .medium: return "50"
        case .large: return "75"
        }
    }
}

enum SeerrRowType: String, Codable, CaseIterable {
    case recentRequests = "recent_requests"
    case trending
    case popularMovies = "popular_movies"
    case movieGenres = "movie_genres"
    case upcomingMovies = "upcoming_movies"
    case studios
    case popularSeries = "popular_series"
    case seriesGenres = "series_genres"
    case upcomingSeries = "upcoming_series"
    case networks

    var displayName: String {
        switch self {
        case .recentRequests: return "Recent Requests"
        case .trending: return "Trending"
        case .popularMovies: return "Popular Movies"
        case .movieGenres: return "Movie Genres"
        case .upcomingMovies: return "Upcoming Movies"
        case .studios: return "Studios"
        case .popularSeries: return "Popular Series"
        case .seriesGenres: return "Series Genres"
        case .upcomingSeries: return "Upcoming Series"
        case .networks: return "Networks"
        }
    }
}

struct SeerrRowConfig: Codable {
    let type: SeerrRowType
    var enabled: Bool
    var order: Int

    static func defaults() -> [SeerrRowConfig] {
        SeerrRowType.allCases.enumerated().map { index, type in
            SeerrRowConfig(type: type, enabled: true, order: index)
        }
    }
}

final class SeerrPreferences {
    private var store: PreferenceStore

    static let enabled = Preference(key: "seerr_enabled", defaultValue: false)
    static let serverUrl = Preference(key: "seerr_server_url", defaultValue: "")
    static let password = Preference(key: "seerr_password", defaultValue: "")
    static let authMethod = Preference(key: "seerr_auth_method", defaultValue: "")
    static let localEmail = Preference(key: "seerr_local_email", defaultValue: "")
    static let localPassword = Preference(key: "seerr_local_password", defaultValue: "")
    static let apiKey = Preference(key: "seerr_api_key", defaultValue: "")
    static let lastJellyfinUser = Preference(key: "seerr_last_jellyfin_user", defaultValue: "")
    static let autoGenerateApiKey = Preference(key: "seerr_auto_generate_api_key", defaultValue: true)
    static let lastVerifiedTime = Preference(key: "seerr_last_verified", defaultValue: "")
    static let lastConnectionSuccess = Preference(key: "seerr_last_connection_success", defaultValue: false)

    static let moonfinMode = Preference(key: "seerr_moonfin_mode", defaultValue: false)
    static let moonfinDisplayName = Preference(key: "seerr_moonfin_display_name", defaultValue: "")
    static let moonfinVariant = Preference(key: "seerr_moonfin_variant", defaultValue: "jellyseerr")
    static let moonfinJellyseerrUserId = Preference(key: "seerr_moonfin_user_id", defaultValue: "")

    static let showInNavigation = Preference(key: "seerr_show_in_navigation", defaultValue: true)
    static let showInToolbar = Preference(key: "seerr_show_in_toolbar", defaultValue: true)
    static let showRequestStatus = Preference(key: "seerr_show_request_status", defaultValue: true)
    static let fetchLimit = Preference(key: "seerr_fetch_limit", defaultValue: SeerrFetchLimit.medium)
    static let blockNsfw = Preference(key: "seerr_block_nsfw", defaultValue: true)
    static let rowsConfigJson = Preference(key: "seerr_rows_config", defaultValue: "")

    static let hdMovieProfileId = Preference(key: "seerr_hd_movie_profile_id", defaultValue: "")
    static let fourKMovieProfileId = Preference(key: "seerr_4k_movie_profile_id", defaultValue: "")
    static let hdTvProfileId = Preference(key: "seerr_hd_tv_profile_id", defaultValue: "")
    static let fourKTvProfileId = Preference(key: "seerr_4k_tv_profile_id", defaultValue: "")
    static let hdMovieRootFolderId = Preference(key: "seerr_hd_movie_root_folder_id", defaultValue: "")
    static let fourKMovieRootFolderId = Preference(key: "seerr_4k_movie_root_folder_id", defaultValue: "")
    static let hdTvRootFolderId = Preference(key: "seerr_hd_tv_root_folder_id", defaultValue: "")
    static let fourKTvRootFolderId = Preference(key: "seerr_4k_tv_root_folder_id", defaultValue: "")
    static let hdMovieServerId = Preference(key: "seerr_hd_movie_server_id", defaultValue: "")
    static let fourKMovieServerId = Preference(key: "seerr_4k_movie_server_id", defaultValue: "")
    static let hdTvServerId = Preference(key: "seerr_hd_tv_server_id", defaultValue: "")
    static let fourKTvServerId = Preference(key: "seerr_4k_tv_server_id", defaultValue: "")

    private static let migrationDoneKey = "seerr_migration_v1_done"

    init(store: PreferenceStore) {
        self.store = store
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { store[preference] }
        set { store[preference] = newValue }
    }

    // MARK: - Row Configuration

    var rowsConfig: [SeerrRowConfig] {
        get {
            let json = store[Self.rowsConfigJson]
            guard !json.isEmpty, let data = json.data(using: .utf8) else {
                return SeerrRowConfig.defaults()
            }
            return (try? JSONDecoder().decode([SeerrRowConfig].self, from: data)) ?? SeerrRowConfig.defaults()
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            store[Self.rowsConfigJson] = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var activeRows: [SeerrRowType] {
        rowsConfig
            .filter(\.enabled)
            .sorted { $0.order < $1.order }
            .map(\.type)
    }

    // MARK: - Per-User Factory

    static func forUser(_ userId: String) -> SeerrPreferences {
        let defaults = UserDefaults(suiteName: "seerr_prefs_\(userId)") ?? .standard
        let store = UserDefaultsPreferenceStore(defaults: defaults)
        let prefs = SeerrPreferences(store: store)
        migrateGlobalToUser(prefs, defaults: defaults)
        return prefs
    }

    private static func migrateGlobalToUser(_ userPrefs: SeerrPreferences, defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationDoneKey) else { return }

        let globalDefaults = UserDefaults.standard
        let globalServerUrl = globalDefaults.string(forKey: Self.serverUrl.key) ?? ""
        let globalEnabled = globalDefaults.bool(forKey: Self.enabled.key)

        guard !globalServerUrl.isEmpty || globalEnabled else {
            defaults.set(true, forKey: migrationDoneKey)
            return
        }

        let existingUrl: String = userPrefs[Self.serverUrl]
        guard existingUrl.isEmpty else {
            defaults.set(true, forKey: migrationDoneKey)
            return
        }

        let keysToMigrate: [String] = [
            Self.enabled.key, Self.serverUrl.key, Self.password.key,
            Self.authMethod.key, Self.localEmail.key, Self.localPassword.key,
            Self.apiKey.key, Self.lastConnectionSuccess.key,
            Self.showInNavigation.key, Self.showInToolbar.key,
            Self.showRequestStatus.key, Self.blockNsfw.key,
            Self.rowsConfigJson.key, Self.fetchLimit.key,
            Self.hdMovieProfileId.key, Self.fourKMovieProfileId.key,
            Self.hdTvProfileId.key, Self.fourKTvProfileId.key,
            Self.hdMovieRootFolderId.key, Self.fourKMovieRootFolderId.key,
            Self.hdTvRootFolderId.key, Self.fourKTvRootFolderId.key,
            Self.hdMovieServerId.key, Self.fourKMovieServerId.key,
            Self.hdTvServerId.key, Self.fourKTvServerId.key,
        ]

        for key in keysToMigrate {
            if let value = globalDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationDoneKey)
    }
}
