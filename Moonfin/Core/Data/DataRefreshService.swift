import Foundation

@MainActor
final class DataRefreshService {
    private(set) var lastPlayback: Date?
    private(set) var lastMoviePlayback: Date?
    private(set) var lastTvPlayback: Date?
    private(set) var lastLibraryChange: Date?
    private(set) var lastFavoriteUpdate: Date?

    func timestamp(for trigger: ChangeTriggerType) -> Date? {
        switch trigger {
        case .libraryUpdated: return lastLibraryChange
        case .moviePlayback: return lastMoviePlayback
        case .tvPlayback: return lastTvPlayback
        case .musicPlayback: return lastPlayback
        case .favoriteUpdate: return lastFavoriteUpdate
        }
    }

    func recordPlayback() {
        lastPlayback = Date()
    }

    func recordMoviePlayback() {
        lastMoviePlayback = Date()
        recordPlayback()
    }

    func recordTvPlayback() {
        lastTvPlayback = Date()
        recordPlayback()
    }

    func recordLibraryChange() {
        lastLibraryChange = Date()
    }

    func recordFavoriteUpdate() {
        lastFavoriteUpdate = Date()
    }
}
