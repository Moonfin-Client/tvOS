import Foundation
import Combine
import os

struct SeerrDiscoverRow: Identifiable {
    let id: String
    let title: String
    let rowType: SeerrRowType
    var items: [SeerrDiscoverItemDto]
    var genres: [SeerrGenreDto]
    var isLoading: Bool
    var currentPage: Int
    var totalPages: Int
    var hasMore: Bool { currentPage < totalPages }
    var isEmpty: Bool { items.isEmpty && genres.isEmpty && !isLoading }

    init(id: String, title: String, rowType: SeerrRowType, items: [SeerrDiscoverItemDto] = [],
         genres: [SeerrGenreDto] = [], isLoading: Bool = true, currentPage: Int = 1, totalPages: Int = 1) {
        self.id = id
        self.title = title
        self.rowType = rowType
        self.items = items
        self.genres = genres
        self.isLoading = isLoading
        self.currentPage = currentPage
        self.totalPages = totalPages
    }
}

struct SeerrSelectedItemState: Equatable {
    let title: String
    let year: String
    let overview: String
    let mediaType: String
    let voteAverage: Double

    static let empty = SeerrSelectedItemState(title: "", year: "", overview: "", mediaType: "", voteAverage: 0)
}

struct SeerrSettingsState {
    var isEnabled: Bool = false
    var serverUrl: String = ""
    var fetchLimit: SeerrFetchLimit = .medium
    var blockNsfw: Bool = true
    var isConnected: Bool = false
    var jellyfinUsername: String = ""
    var connectionStatus: String = ""
    var isConnecting: Bool = false
}

@MainActor
final class SeerrDiscoverViewModel: ObservableObject {
    @Published var rows: [SeerrDiscoverRow] = []
    @Published var selectedItem = SeerrSelectedItemState.empty
    @Published var currentBackdropUrl: String?
    @Published var isInitialLoad = true
    @Published var settingsState = SeerrSettingsState()

    private let seerrRepository: SeerrRepositoryProtocol
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SeerrDiscover")
    private var focusDebounceTask: Task<Void, Never>?
    private var backdropDebounceTask: Task<Void, Never>?
    private var loadingMoreTypes: Set<SeerrRowType> = []
    private var blockNsfw = true

    private static let nsfwKeywords = [
        "\\bsex\\b", "sexual", "\\bporn\\b", "erotic", "\\bnude\\b", "nudity",
        "\\bxxx\\b", "adult film", "prostitute", "stripper", "\\bescort\\b",
        "seduction", "\\baffair\\b", "threesome", "\\borgy\\b", "kinky",
        "fetish", "\\bbdsm\\b", "dominatrix"
    ]

    init(seerrRepository: SeerrRepositoryProtocol) {
        self.seerrRepository = seerrRepository
    }

    func loadContent() {
        guard isInitialLoad else { return }

        let prefs = seerrRepository.getPreferences()
        blockNsfw = prefs?[SeerrPreferences.blockNsfw] ?? true
        let fetchLimit = (prefs?[SeerrPreferences.fetchLimit] ?? .medium).limit
        let activeRows = prefs?.activeRows ?? SeerrRowType.allCases

        rows = activeRows.map { type in
            SeerrDiscoverRow(id: type.rawValue, title: type.displayName, rowType: type)
        }

        loadSettings()

        Task {
            await withTaskGroup(of: Void.self) { group in
                for rowType in activeRows {
                    group.addTask { [weak self] in
                        await self?.loadRow(rowType, limit: fetchLimit)
                    }
                }
            }
            isInitialLoad = false
        }
    }

    func refreshRequests() {
        guard !isInitialLoad else { return }
        let prefs = seerrRepository.getPreferences()
        let fetchLimit = (prefs?[SeerrPreferences.fetchLimit] ?? .medium).limit
        Task {
            await loadRow(.recentRequests, limit: fetchLimit)
        }
    }

    private func loadRow(_ type: SeerrRowType, limit: Int) async {
        do {
            switch type {
            case .recentRequests:
                let response = try await seerrRepository.getRequests(filter: nil, requestedBy: nil, limit: limit, offset: 0)
                await updateRequestsRow(type, requests: response.results)
            case .trending:
                let page = try await seerrRepository.getTrending(limit: limit, offset: 0)
                await updateRow(type, page: page)
            case .popularMovies:
                let page = try await seerrRepository.getTopMovies(limit: limit, offset: 0)
                await updateRow(type, page: page)
            case .popularSeries:
                let page = try await seerrRepository.getTopTv(limit: limit, offset: 0)
                await updateRow(type, page: page)
            case .upcomingMovies:
                let page = try await seerrRepository.getUpcomingMovies()
                await updateRow(type, page: page)
            case .upcomingSeries:
                let page = try await seerrRepository.getUpcomingTv()
                await updateRow(type, page: page)
            case .movieGenres:
                let genres = try await seerrRepository.getGenreSliderMovies()
                await updateGenreRow(type, genres: genres)
            case .seriesGenres:
                let genres = try await seerrRepository.getGenreSliderTv()
                await updateGenreRow(type, genres: genres)
            case .studios, .networks:
                await updateRowLoaded(type)
            }
        } catch {
            logger.warning("Failed to load \(type.rawValue): \(error.localizedDescription)")
            await updateRowLoaded(type)
        }
    }

    private func updateRow(_ type: SeerrRowType, page: SeerrDiscoverPageDto) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].items = filterItems(page.results)
        rows[index].currentPage = page.page
        rows[index].totalPages = page.totalPages
        rows[index].isLoading = false
    }

    private func updateRequestsRow(_ type: SeerrRowType, requests: [SeerrRequestDto]) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].items = requests.compactMap { request -> SeerrDiscoverItemDto? in
            guard let media = request.media, let tmdbId = media.tmdbId else { return nil }
            return SeerrDiscoverItemDto.fromRequest(tmdbId: tmdbId, mediaType: media.mediaType ?? "movie", request: request)
        }
        rows[index].isLoading = false
    }

    private func updateGenreRow(_ type: SeerrRowType, genres: [SeerrGenreDto]) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].genres = genres
        rows[index].isLoading = false
    }

    private func updateRowLoaded(_ type: SeerrRowType) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].isLoading = false
    }

    private func filterItems(_ items: [SeerrDiscoverItemDto]) -> [SeerrDiscoverItemDto] {
        items.filter { item in
            guard !item.isBlacklisted else { return false }
            guard item.mediaType == "movie" || item.mediaType == "tv" else { return false }
            if blockNsfw {
                if item.adult { return false }
                let text = "\(item.displayTitle) \(item.overview ?? "")".lowercased()
                for keyword in Self.nsfwKeywords {
                    if text.range(of: keyword, options: .regularExpression) != nil { return false }
                }
            }
            return true
        }
    }

    func loadMoreIfNeeded(row: SeerrDiscoverRow, currentIndex: Int) {
        guard row.hasMore,
              currentIndex >= row.items.count - 10,
              !loadingMoreTypes.contains(row.rowType) else { return }

        loadingMoreTypes.insert(row.rowType)
        let prefs = seerrRepository.getPreferences()
        let limit = (prefs?[SeerrPreferences.fetchLimit] ?? .medium).limit
        let nextOffset = row.items.count

        Task {
            defer { loadingMoreTypes.remove(row.rowType) }
            do {
                let page: SeerrDiscoverPageDto
                switch row.rowType {
                case .trending:
                    page = try await seerrRepository.getTrending(limit: limit, offset: nextOffset)
                case .popularMovies:
                    page = try await seerrRepository.getTopMovies(limit: limit, offset: nextOffset)
                case .popularSeries:
                    page = try await seerrRepository.getTopTv(limit: limit, offset: nextOffset)
                default:
                    return
                }

                guard let index = rows.firstIndex(where: { $0.rowType == row.rowType }) else { return }
                let newItems = filterItems(page.results)
                rows[index].items.append(contentsOf: newItems)
                rows[index].currentPage = page.page
                rows[index].totalPages = page.totalPages
            } catch {
                logger.warning("Failed to load more \(row.rowType.rawValue): \(error.localizedDescription)")
            }
        }
    }

    func onItemFocused(_ item: SeerrDiscoverItemDto) {
        focusDebounceTask?.cancel()
        focusDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            let year: String
            if let date = item.releaseDate ?? item.firstAirDate, date.count >= 4 {
                year = String(date.prefix(4))
            } else {
                year = ""
            }

            selectedItem = SeerrSelectedItemState(
                title: item.displayTitle,
                year: year,
                overview: item.overview ?? "",
                mediaType: item.mediaType == "tv" ? "Series" : "Movie",
                voteAverage: item.voteAverage ?? 0
            )
        }

        backdropDebounceTask?.cancel()
        backdropDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            if let path = item.backdropPath {
                currentBackdropUrl = SeerrImageUrl.backdrop(path)
            } else if let path = item.posterPath {
                currentBackdropUrl = SeerrImageUrl.poster(path)
            }
        }
    }

    func onGenreFocused(_ genre: SeerrGenreDto, mediaType: String) {
        focusDebounceTask?.cancel()
        focusDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            selectedItem = SeerrSelectedItemState(
                title: genre.name,
                year: "",
                overview: "",
                mediaType: mediaType == "tv" ? "Series Genres" : "Movie Genres",
                voteAverage: 0
            )
        }

        backdropDebounceTask?.cancel()
        backdropDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            if let path = genre.backdrops.first {
                currentBackdropUrl = SeerrImageUrl.genreBackdrop(path)
            }
        }
    }

    func posterUrl(for item: SeerrDiscoverItemDto) -> String? {
        item.posterPath.map { SeerrImageUrl.poster($0) }
    }

    func itemJson(_ item: SeerrDiscoverItemDto) -> String? {
        guard let data = try? JSONEncoder().encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Settings

    func loadSettings() {
        let prefs = seerrRepository.getPreferences()
        settingsState.isEnabled = prefs?[SeerrPreferences.enabled] ?? false
        settingsState.serverUrl = prefs?[SeerrPreferences.serverUrl] ?? ""
        settingsState.fetchLimit = prefs?[SeerrPreferences.fetchLimit] ?? .medium
        settingsState.blockNsfw = prefs?[SeerrPreferences.blockNsfw] ?? true
        settingsState.isConnected = seerrRepository.isAvailable.value
        if let info = seerrRepository.getJellyfinSessionInfo() {
            settingsState.jellyfinUsername = info.username
        }
    }

    func toggleEnabled() {
        settingsState.isEnabled.toggle()
        let prefs = seerrRepository.getPreferences()
        prefs?[SeerrPreferences.enabled] = settingsState.isEnabled
    }

    func cycleFetchLimit() {
        let cases = SeerrFetchLimit.allCases
        let idx = cases.firstIndex(of: settingsState.fetchLimit) ?? 0
        settingsState.fetchLimit = cases[(idx + 1) % cases.count]
        let prefs = seerrRepository.getPreferences()
        prefs?[SeerrPreferences.fetchLimit] = settingsState.fetchLimit
    }

    func toggleNsfw() {
        settingsState.blockNsfw.toggle()
        let prefs = seerrRepository.getPreferences()
        prefs?[SeerrPreferences.blockNsfw] = settingsState.blockNsfw
        blockNsfw = settingsState.blockNsfw
    }

    func updateServerUrl(_ url: String) {
        settingsState.serverUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefs = seerrRepository.getPreferences()
        prefs?[SeerrPreferences.serverUrl] = settingsState.serverUrl
    }

    func connectWithJellyfin(password: String) {
        guard let info = seerrRepository.getJellyfinSessionInfo(),
              !settingsState.serverUrl.isEmpty else {
            settingsState.connectionStatus = "Enter a server URL first"
            return
        }

        settingsState.isConnecting = true
        settingsState.connectionStatus = "Connecting..."

        Task {
            do {
                _ = try await seerrRepository.loginWithJellyfin(
                    username: info.username,
                    password: password,
                    jellyfinUrl: info.serverUrl,
                    seerrUrl: settingsState.serverUrl
                )
                settingsState.isConnected = true
                settingsState.connectionStatus = "Connected"
                settingsState.isEnabled = true
            } catch {
                settingsState.connectionStatus = "Failed: \(error.localizedDescription)"
            }
            settingsState.isConnecting = false
        }
    }

    func testConnection() {
        settingsState.connectionStatus = "Testing..."
        Task {
            let success = await seerrRepository.testConnection()
            settingsState.isConnected = success
            settingsState.connectionStatus = success ? "Connected" : "Connection failed"
        }
    }
}

enum SeerrImageUrl {
    static let tmdbBase = "https://image.tmdb.org/t/p"

    static func poster(_ path: String) -> String { "\(tmdbBase)/w500\(path)" }
    static func backdrop(_ path: String) -> String { "\(tmdbBase)/w1280\(path)" }
    static func genreBackdrop(_ path: String) -> String { "\(tmdbBase)/w780\(path)" }
    static func profile(_ path: String) -> String { "\(tmdbBase)/w185\(path)" }
}
