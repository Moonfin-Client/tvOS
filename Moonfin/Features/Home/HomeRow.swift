import Foundation

enum HomeSectionType: String, CaseIterable, Codable {
    case resume
    case nextUp
    case latestMedia
    case libraryTiles
    case resumeAudio
    case playlists
    case liveTv
    case none

    static let defaults: [(type: HomeSectionType, enabled: Bool)] = [
        (.resume, true),
        (.nextUp, true),
        (.liveTv, true),
        (.latestMedia, true),
        (.libraryTiles, false),
        (.resumeAudio, false),
        (.playlists, false),
    ]
}

enum HomeRowType: Equatable {
    case continueWatching
    case nextUp
    case latestMedia(libraryId: String)
    case libraryTiles
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
        case .resumeAudio:
            return 1.0
        default:
            return 2.0 / 3.0
        }
    }

    var cardWidth: CGFloat {
        switch self {
        case .continueWatching, .nextUp, .liveTvOnNow, .liveTvComingUp:
            return 280
        case .liveTvButtons:
            return 220
        case .resumeAudio:
            return 180
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
