import Foundation

private func homeRowLocalized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

private func homeRowLocalized(_ keys: [String]) -> String {
    for key in keys {
        let localized = homeRowLocalized(key)
        if localized != key {
            return localized
        }
    }
    return keys.last ?? ""
}

enum HomeSectionKind: String, Codable {
    case builtin
    case pluginDynamic

    static func fromSerialized(_ value: String?) -> HomeSectionKind {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .builtin
        }

        switch raw {
        case "builtin":
            return .builtin
        case "pluginDynamic", "plugin_dynamic", "plugin":
            return .pluginDynamic
        default:
            return .builtin
        }
    }
}

enum HomeSectionPluginSource: String, Codable, CaseIterable {
    case hss
    case kefinTweaks
    case collections
    case genres

    static func fromSerialized(_ value: String?) -> HomeSectionPluginSource {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .hss
        }
        return HomeSectionPluginSource(rawValue: raw) ?? .hss
    }
}

struct HomeSectionConfig: Codable, Hashable, Identifiable {
    var type: HomeSectionType
    var enabled: Bool
    var order: Int
    var kind: HomeSectionKind
    var serverId: String?
    var pluginSection: String?
    var pluginAdditionalData: String?
    var pluginDisplayText: String?
    var pluginSource: HomeSectionPluginSource

    var id: String { stableId }
    var isBuiltin: Bool { kind == .builtin }
    var isPluginDynamic: Bool { kind == .pluginDynamic }

    var stableId: String {
        if isPluginDynamic {
            return "pluginDynamic:\(pluginSource.rawValue):\(serverId ?? ""):\(pluginSection ?? ""):\(pluginAdditionalData ?? "")"
        }
        return "builtin:\(type.serverName)"
    }

    static func builtin(type: HomeSectionType, enabled: Bool, order: Int) -> HomeSectionConfig {
        HomeSectionConfig(
            type: type,
            enabled: enabled,
            order: order,
            kind: .builtin,
            serverId: nil,
            pluginSection: nil,
            pluginAdditionalData: nil,
            pluginDisplayText: nil,
            pluginSource: .hss
        )
    }

    static func pluginDynamic(
        type: HomeSectionType = .none,
        enabled: Bool,
        order: Int,
        serverId: String?,
        pluginSection: String?,
        pluginAdditionalData: String?,
        pluginDisplayText: String?,
        pluginSource: HomeSectionPluginSource
    ) -> HomeSectionConfig {
        HomeSectionConfig(
            type: type,
            enabled: enabled,
            order: order,
            kind: .pluginDynamic,
            serverId: serverId,
            pluginSection: pluginSection,
            pluginAdditionalData: pluginAdditionalData,
            pluginDisplayText: pluginDisplayText,
            pluginSource: pluginSource
        )
    }

    static func defaultConfigs() -> [HomeSectionConfig] {
        HomeSectionType.defaults.enumerated().map { idx, value in
            HomeSectionConfig.builtin(type: value.type, enabled: value.enabled, order: idx)
        }
    }

    static func decodeJsonString(_ raw: String) -> [HomeSectionConfig]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([HomeSectionConfig].self, from: data)
        else {
            return nil
        }
        return normalized(decoded)
    }

    static func fromLegacyCsv(_ raw: String) -> [HomeSectionConfig] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return defaultConfigs()
        }

        var seen = Set<HomeSectionType>()
        let enabledTypes = trimmed
            .split(separator: ",")
            .compactMap { token -> HomeSectionType? in
                let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
                return HomeSectionType(rawValue: value) ?? HomeSectionType.from(serverName: value)
            }
            .filter { $0 != .none }
            .filter { seen.insert($0).inserted }

        guard !enabledTypes.isEmpty else {
            return defaultConfigs()
        }

        var configs: [HomeSectionConfig] = enabledTypes.enumerated().map { idx, type in
            HomeSectionConfig.builtin(type: type, enabled: true, order: idx)
        }

        let enabledSet = Set(enabledTypes)
        for type in HomeSectionType.allCases where type != .none && type != .mediaBar {
            guard !enabledSet.contains(type) else { continue }
            configs.append(HomeSectionConfig.builtin(type: type, enabled: false, order: configs.count))
        }

        return normalized(configs)
    }

    static func fromStorageString(_ raw: String) -> [HomeSectionConfig] {
        if let decoded = decodeJsonString(raw) {
            return decoded
        }
        return fromLegacyCsv(raw)
    }

    static func toStorageString(_ configs: [HomeSectionConfig]) -> String {
        let sorted = normalized(configs)
        guard let data = try? JSONEncoder().encode(sorted),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    static func normalized(_ configs: [HomeSectionConfig]) -> [HomeSectionConfig] {
        let sorted = configs.sorted {
            if $0.order == $1.order {
                return $0.stableId < $1.stableId
            }
            return $0.order < $1.order
        }

        var seen = Set<String>()
        var result: [HomeSectionConfig] = []
        result.reserveCapacity(sorted.count)
        for config in sorted {
            guard seen.insert(config.stableId).inserted else { continue }
            var normalized = config
            normalized.order = result.count
            if normalized.isBuiltin {
                normalized.serverId = nil
                normalized.pluginSection = nil
                normalized.pluginAdditionalData = nil
                normalized.pluginDisplayText = nil
            }
            result.append(normalized)
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case enabled
        case order
        case kind
        case serverId
        case pluginSection
        case pluginAdditionalData
        case pluginDisplayText
        case pluginSource
    }

    init(
        type: HomeSectionType,
        enabled: Bool,
        order: Int,
        kind: HomeSectionKind,
        serverId: String?,
        pluginSection: String?,
        pluginAdditionalData: String?,
        pluginDisplayText: String?,
        pluginSource: HomeSectionPluginSource
    ) {
        self.type = type
        self.enabled = enabled
        self.order = order
        self.kind = kind
        self.serverId = serverId
        self.pluginSection = pluginSection
        self.pluginAdditionalData = pluginAdditionalData
        self.pluginDisplayText = pluginDisplayText
        self.pluginSource = pluginSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decodeIfPresent(HomeSectionType.self, forKey: .type) ?? .none
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0

        if let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind) {
            kind = HomeSectionKind.fromSerialized(kindRaw)
        } else {
            kind = .builtin
        }

        serverId = try container.decodeIfPresent(String.self, forKey: .serverId)
        pluginSection = try container.decodeIfPresent(String.self, forKey: .pluginSection)
        pluginAdditionalData = try container.decodeIfPresent(String.self, forKey: .pluginAdditionalData)
        pluginDisplayText = try container.decodeIfPresent(String.self, forKey: .pluginDisplayText)

        if let sourceRaw = try container.decodeIfPresent(String.self, forKey: .pluginSource) {
            pluginSource = HomeSectionPluginSource.fromSerialized(sourceRaw)
        } else {
            pluginSource = .hss
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(order, forKey: .order)
        try container.encode(kind.rawValue, forKey: .kind)

        if isPluginDynamic {
            try container.encodeIfPresent(serverId, forKey: .serverId)
            try container.encodeIfPresent(pluginSection, forKey: .pluginSection)
            try container.encodeIfPresent(pluginAdditionalData, forKey: .pluginAdditionalData)
            try container.encodeIfPresent(pluginDisplayText, forKey: .pluginDisplayText)
            try container.encode(pluginSource.rawValue, forKey: .pluginSource)
        }
    }
}

enum HomeSectionType: String, CaseIterable, Codable {
    case resume
    case resumeBook
    case nextUp
    case latestMedia
    case activeRecordings
    case recentlyReleased
    case favorites
    case favoriteMovies
    case favoriteSeries
    case favoriteEpisodes
    case favoritePeople
    case favoriteArtists
    case favoriteMusicVideos
    case favoriteAlbums
    case favoriteSongs
    case collections
    case genres
    case myMedia
    case myMediaSmall
    case resumeAudio
    case playlists
    case liveTv
    case mediaBar
    case none

    var displayName: String {
        switch self {
        case .resume:
            return homeRowLocalized(["lbl_continue_watching", "continue_watching"])
        case .resumeBook:
            return homeRowLocalized(["continue_reading", "Continue Reading"])
        case .nextUp:
            return homeRowLocalized(["lbl_next_up", "next_up"])
        case .latestMedia:
            return homeRowLocalized(["lbl_latest", "latest_media"])
        case .activeRecordings:
            return homeRowLocalized(["active_recordings", "Active Recordings"])
        case .recentlyReleased:
            return homeRowLocalized(["recently_released", "Recently Released"])
        case .favorites:
            return homeRowLocalized(["favorites", "Favorites"])
        case .favoriteMovies:
            return homeRowLocalized(["favorite_movies", "Favorite Movies"])
        case .favoriteSeries:
            return homeRowLocalized(["favorite_series", "Favorite Series"])
        case .favoriteEpisodes:
            return homeRowLocalized(["favorite_episodes", "Favorite Episodes"])
        case .favoritePeople:
            return homeRowLocalized(["favorite_people", "Favorite People"])
        case .favoriteArtists:
            return homeRowLocalized(["favorite_artists", "Favorite Artists"])
        case .favoriteMusicVideos:
            return homeRowLocalized(["favorite_music_videos", "Favorite Music Videos"])
        case .favoriteAlbums:
            return homeRowLocalized(["favorite_albums", "Favorite Albums"])
        case .favoriteSongs:
            return homeRowLocalized(["favorite_songs", "Favorite Songs"])
        case .collections:
            return homeRowLocalized(["collections", "Collections"])
        case .genres:
            return homeRowLocalized(["genres", "Genres"])
        case .myMedia:
            return homeRowLocalized(["lbl_my_media", "my_media"])
        case .myMediaSmall:
            return homeRowLocalized(["my_media_small", "lbl_my_media", "my_media"])
        case .resumeAudio:
            return homeRowLocalized(["continue_listening", "lbl_continue_listening"])
        case .playlists:
            return homeRowLocalized(["lbl_playlists", "playlists"])
        case .liveTv:
            return homeRowLocalized(["lbl_live_tv", "live_tv"])
        case .mediaBar:
            return homeRowLocalized(["media_bar", "Media Bar"])
        case .none:
            return homeRowLocalized(["lbl_none", "none"])
        }
    }

    var icon: String {
        switch self {
        case .resume: return "play.circle"
        case .resumeBook: return "book"
        case .nextUp: return "arrow.right.circle"
        case .latestMedia: return "sparkles"
        case .activeRecordings: return "record.circle"
        case .recentlyReleased: return "calendar.badge.clock"
        case .favorites: return "heart.fill"
        case .favoriteMovies: return "film"
        case .favoriteSeries: return "tv"
        case .favoriteEpisodes: return "tv.and.mediabox"
        case .favoritePeople: return "person.2.fill"
        case .favoriteArtists: return "music.mic"
        case .favoriteMusicVideos: return "music.note.tv"
        case .favoriteAlbums: return "opticaldisc"
        case .favoriteSongs: return "music.note"
        case .collections: return "square.stack.3d.up"
        case .genres: return "theatermasks"
        case .myMedia: return "rectangle.grid.1x2"
        case .myMediaSmall: return "list.bullet.rectangle"
        case .resumeAudio: return "headphones"
        case .playlists: return "music.note.list"
        case .liveTv: return "tv"
        case .mediaBar: return "rectangle.tophalf.inset.filled"
        case .none: return "minus.circle"
        }
    }

    /// The serialized name used by the Moonfin plugin server (matches AndroidTV convention).
    var serverName: String {
        switch self {
        case .resume: return "resume"
        case .resumeBook: return "resumebook"
        case .nextUp: return "nextup"
        case .latestMedia: return "latestmedia"
        case .activeRecordings: return "activerecordings"
        case .recentlyReleased: return "recentlyreleased"
        case .favorites: return "favorites"
        case .favoriteMovies: return "favoritemovies"
        case .favoriteSeries: return "favoriteseries"
        case .favoriteEpisodes: return "favoriteepisodes"
        case .favoritePeople: return "favoritepeople"
        case .favoriteArtists: return "favoriteartists"
        case .favoriteMusicVideos: return "favoritemusicvideos"
        case .favoriteAlbums: return "favoritealbums"
        case .favoriteSongs: return "favoritesongs"
        case .collections: return "collections"
        case .genres: return "genres"
        case .myMedia: return "smalllibrarytiles"
        case .myMediaSmall: return "librarybuttons"
        case .resumeAudio: return "resumeaudio"
        case .playlists: return "playlists"
        case .liveTv: return "livetv"
        case .mediaBar: return "mediabar"
        case .none: return "none"
        }
    }

    static func from(serverName: String) -> HomeSectionType? {
        let trimmed = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        switch lowered {
        case "watchlist":
            return .playlists
        case "continuereading", "resumebooks":
            return .resumeBook
        case "recordings":
            return .activeRecordings
        case "recentlyreleasedmovies", "recentlyreleasedepisodes":
            return .recentlyReleased
        case "favoriteitems":
            return .favorites
        case "favoriteepisode":
            return .favoriteEpisodes
        case "favoriteperson":
            return .favoritePeople
        case "favoriteartist":
            return .favoriteArtists
        case "favoritemusicvideo":
            return .favoriteMusicVideos
        case "favoritealbum":
            return .favoriteAlbums
        case "favoritesong":
            return .favoriteSongs
        default:
            break
        }

        return HomeSectionType.allCases.first { $0.serverName == lowered }
            ?? HomeSectionType(rawValue: trimmed)
    }

    static let defaults: [(type: HomeSectionType, enabled: Bool)] = [
        (.resume, true),
        (.nextUp, true),
        (.liveTv, true),
        (.latestMedia, true),
        (.recentlyReleased, false),
        (.favorites, false),
        (.favoriteMovies, false),
        (.favoriteSeries, false),
        (.favoriteEpisodes, false),
        (.favoritePeople, false),
        (.favoriteArtists, false),
        (.favoriteMusicVideos, false),
        (.favoriteAlbums, false),
        (.favoriteSongs, false),
        (.collections, false),
        (.genres, false),
        (.activeRecordings, false),
        (.resumeBook, false),
        (.myMedia, false),
        (.myMediaSmall, false),
        (.resumeAudio, false),
        (.playlists, false),
    ]
}

enum HomeRowType: Equatable {
    case continueWatching
    case resumeBook
    case nextUp
    case latestMedia(libraryId: String)
    case activeRecordings
    case recentlyReleased
    case favorites
    case favoriteMovies
    case favoriteSeries
    case favoriteEpisodes
    case favoritePeople
    case favoriteArtists
    case favoriteMusicVideos
    case favoriteAlbums
    case favoriteSongs
    case collections
    case genres
    case myMedia
    case myMediaSmall
    case resumeAudio
    case playlists
    case liveTvButtons
    case liveTvOnNow
    case liveTvComingUp
    case mediaBar
    case none

    var aspectRatio: CGFloat {
        switch self {
        case .continueWatching, .resumeBook, .nextUp, .liveTvOnNow, .liveTvComingUp, .mediaBar:
            return 16.0 / 9.0
        case .liveTvButtons:
            return 2.0 / 1.0
        case .resumeAudio, .myMediaSmall:
            return 1.0
        default:
            return 2.0 / 3.0
        }
    }

    var cardWidth: CGFloat {
        switch self {
        case .continueWatching, .resumeBook, .nextUp, .liveTvOnNow, .liveTvComingUp, .mediaBar:
            return 280
        case .myMedia:
            return 240
        case .liveTvButtons:
            return 220
        case .resumeAudio:
            return 180
        case .myMediaSmall:
            return 120
        default:
            return 150
        }
    }
}

struct HomeRow: Identifiable {
    let id: String
    let title: String
    var items: [ServerItem]
    let rowType: HomeRowType
    let isMusicLibraryRow: Bool
    var isLoading: Bool
    var totalItemCount: Int
    var isEmpty: Bool { items.isEmpty && !isLoading }

    init(id: String, title: String, items: [ServerItem] = [], rowType: HomeRowType, isMusicLibraryRow: Bool = false, isLoading: Bool = true, totalItemCount: Int = 0) {
        self.id = id
        self.title = title
        self.items = items
        self.rowType = rowType
        self.isMusicLibraryRow = isMusicLibraryRow
        self.isLoading = isLoading
        self.totalItemCount = totalItemCount
    }
}
