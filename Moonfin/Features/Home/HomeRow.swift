import Foundation

enum HomeSectionType: String, CaseIterable, Codable {
    case resume
    case nextUp
    case latestMedia
    case myMedia
    case myMediaSmall
    case resumeAudio
    case playlists
    case liveTv
    case none

    var displayName: String {
        switch self {
        case .resume: return "Continue Watching"
        case .nextUp: return "Next Up"
        case .latestMedia: return "Latest Media"
        case .myMedia: return "My Media"
        case .myMediaSmall: return "My Media (small)"
        case .resumeAudio: return "Continue Listening"
        case .playlists: return "Playlists"
        case .liveTv: return "Live TV"
        case .none: return "None"
        }
    }

    var icon: String {
        switch self {
        case .resume: return "play.circle"
        case .nextUp: return "arrow.right.circle"
        case .latestMedia: return "sparkles"
        case .myMedia: return "rectangle.grid.1x2"
        case .myMediaSmall: return "list.bullet.rectangle"
        case .resumeAudio: return "headphones"
        case .playlists: return "music.note.list"
        case .liveTv: return "tv"
        case .none: return "minus.circle"
        }
    }

    /// The serialized name used by the Moonfin plugin server (matches AndroidTV convention).
    var serverName: String {
        switch self {
        case .resume: return "resume"
        case .nextUp: return "nextup"
        case .latestMedia: return "latestmedia"
        case .myMedia: return "smalllibrarytiles"
        case .myMediaSmall: return "librarybuttons"
        case .resumeAudio: return "resumeaudio"
        case .playlists: return "playlists"
        case .liveTv: return "livetv"
        case .none: return "none"
        }
    }

    static func from(serverName: String) -> HomeSectionType? {
        HomeSectionType.allCases.first { $0.serverName == serverName.lowercased() }
            ?? HomeSectionType(rawValue: serverName)
    }

    static let defaults: [(type: HomeSectionType, enabled: Bool)] = [
        (.resume, true),
        (.nextUp, true),
        (.liveTv, true),
        (.latestMedia, true),
        (.myMedia, false),
        (.myMediaSmall, false),
        (.resumeAudio, false),
        (.playlists, false),
    ]
}

enum HomeRowType: Equatable {
    case continueWatching
    case nextUp
    case latestMedia(libraryId: String)
    case myMedia
    case myMediaSmall
    case resumeAudio
    case playlists
    case liveTvButtons
    case liveTvOnNow
    case liveTvComingUp

    var aspectRatio: CGFloat {
        switch self {
        case .continueWatching, .nextUp, .liveTvOnNow, .liveTvComingUp:
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
        case .continueWatching, .nextUp, .liveTvOnNow, .liveTvComingUp:
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
    var isLoading: Bool
    var totalItemCount: Int
    var isEmpty: Bool { items.isEmpty && !isLoading }

    init(id: String, title: String, items: [ServerItem] = [], rowType: HomeRowType, isLoading: Bool = true, totalItemCount: Int = 0) {
        self.id = id
        self.title = title
        self.items = items
        self.rowType = rowType
        self.isLoading = isLoading
        self.totalItemCount = totalItemCount
    }
}
