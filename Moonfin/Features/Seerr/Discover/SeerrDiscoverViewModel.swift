import Foundation
import Combine
import os

struct SeerrDiscoverRow: Identifiable {
    let id: String
    let title: String
    let rowType: SeerrRowType
    var items: [SeerrDiscoverItemDto]
    var genres: [SeerrGenreDto]
    var studios: [SeerrStudioDto]
    var networks: [SeerrNetworkDto]
    var isLoading: Bool
    var currentPage: Int
    var totalPages: Int
    var hasMore: Bool { currentPage < totalPages }
    var isEmpty: Bool { items.isEmpty && genres.isEmpty && studios.isEmpty && networks.isEmpty && !isLoading }

    init(id: String, title: String, rowType: SeerrRowType, items: [SeerrDiscoverItemDto] = [],
         genres: [SeerrGenreDto] = [], studios: [SeerrStudioDto] = [], networks: [SeerrNetworkDto] = [],
         isLoading: Bool = true, currentPage: Int = 1, totalPages: Int = 1) {
        self.id = id
        self.title = title
        self.rowType = rowType
        self.items = items
        self.genres = genres
        self.studios = studios
        self.networks = networks
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
    private var recentRequestsHydrationTask: Task<Void, Never>?
    private var recentRequestsHydrationVersion: Int = 0
    private var blockNsfw = true

    static let popularNetworks: [SeerrNetworkDto] = [
        SeerrNetworkDto(id: 213, name: "Netflix", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/wwemzKWzjKYJFfCeiB57q3r4Bcm.png", originCountry: nil),
        SeerrNetworkDto(id: 2739, name: "Disney+", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png", originCountry: nil),
        SeerrNetworkDto(id: 1024, name: "Prime Video", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png", originCountry: nil),
        SeerrNetworkDto(id: 2552, name: "Apple TV+", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/4KAy34EHvRM25Ih8wb82AuGU7zJ.png", originCountry: nil),
        SeerrNetworkDto(id: 453, name: "Hulu", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/pqUTCleNUiTLAVlelGxUgWn1ELh.png", originCountry: nil),
        SeerrNetworkDto(id: 49, name: "HBO", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/tuomPhY2UtuPTqqFnKMVHvSb724.png", originCountry: nil),
        SeerrNetworkDto(id: 4353, name: "Discovery+", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png", originCountry: nil),
        SeerrNetworkDto(id: 2, name: "ABC", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/ndAvF4JLsliGreX87jAc9GdjmJY.png", originCountry: nil),
        SeerrNetworkDto(id: 19, name: "FOX", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/1DSpHrWyOORkL9N2QHX7Adt31mQ.png", originCountry: nil),
        SeerrNetworkDto(id: 359, name: "Cinemax", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/6mSHSquNpfLgDdv6VnOOvC5Uz2h.png", originCountry: nil),
        SeerrNetworkDto(id: 174, name: "AMC", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/pmvRmATOCaDykE6JrVoeYxlFHw3.png", originCountry: nil),
        SeerrNetworkDto(id: 67, name: "Showtime", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/Allse9kbjiP6ExaQrnSpIhkurEi.png", originCountry: nil),
        SeerrNetworkDto(id: 318, name: "Starz", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/8GJjw3HHsAJYwIWKIPBPfqMxlEa.png", originCountry: nil),
        SeerrNetworkDto(id: 71, name: "The CW", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/ge9hzeaU7nMtQ4PjkFlc68dGAJ9.png", originCountry: nil),
        SeerrNetworkDto(id: 6, name: "NBC", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/o3OedEP0f9mfZr33jz2BfXOUK5.png", originCountry: nil),
        SeerrNetworkDto(id: 16, name: "CBS", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/nm8d7P7MJNiBLdgIzUK0gkuEA4r.png", originCountry: nil),
        SeerrNetworkDto(id: 4330, name: "Paramount+", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/fi83B1oztoS47xxcemFdPMhIzK.png", originCountry: nil),
        SeerrNetworkDto(id: 4, name: "BBC One", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/mVn7xESaTNmjBUyUtGNvDQd3CT1.png", originCountry: nil),
        SeerrNetworkDto(id: 56, name: "Cartoon Network", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/c5OC6oVCg6QP4eqzW6XIq17CQjI.png", originCountry: nil),
        SeerrNetworkDto(id: 80, name: "Adult Swim", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/9AKyspxVzywuaMuZ1Bvilu8sXly.png", originCountry: nil),
        SeerrNetworkDto(id: 13, name: "Nickelodeon", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/ikZXxg6GnwpzqiZbRPhJGaZapqB.png", originCountry: nil),
        SeerrNetworkDto(id: 3353, name: "Peacock", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/gIAcGTjKKr0KOHL5s4O36roJ8p7.png", originCountry: nil),
    ]

    static let popularStudios: [SeerrStudioDto] = [
        SeerrStudioDto(id: 2, name: "Disney", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/wdrCwmRnLFJhEoH8GSfymY85KHT.png"),
        SeerrStudioDto(id: 127928, name: "20th Century Studios", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/h0rjX5vjW5r8yEnUBStFarjcLT4.png"),
        SeerrStudioDto(id: 34, name: "Sony Pictures", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/GagSvqWlyPdkFHMfQ3pNq6ix9P.png"),
        SeerrStudioDto(id: 174, name: "Warner Bros. Pictures", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/ky0xOc5OrhzkZ1N6KyUxacfQsCk.png"),
        SeerrStudioDto(id: 33, name: "Universal", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/8lvHyhjr8oUKOOy2dKXoALWKdp0.png"),
        SeerrStudioDto(id: 4, name: "Paramount", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/fycMZt242LVjagMByZOLUGbCvv3.png"),
        SeerrStudioDto(id: 3, name: "Pixar", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/1TjvGVDMYsj6JBxOAkUHpPEwLf7.png"),
        SeerrStudioDto(id: 521, name: "DreamWorks", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/kP7t6RwGz2AvvTkvnI1uteEwHet.png"),
        SeerrStudioDto(id: 420, name: "Marvel Studios", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/hUzeosd33nzE5MCNsZxCGEKTXaQ.png"),
        SeerrStudioDto(id: 9993, name: "DC", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/2Tc1P3Ac8M479naPp1kYT3izLS5.png"),
        SeerrStudioDto(id: 41077, name: "A24", logoPath: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,bababa)/1ZXsGaFPgrgS6ZZGS37AqD5uU12.png"),
    ]

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
                let requestItems = response.results.compactMap { request -> SeerrDiscoverItemDto? in
                    guard let media = request.media, let tmdbId = media.tmdbId else { return nil }
                    return SeerrDiscoverItemDto.fromRequest(tmdbId: tmdbId, mediaType: request.type, request: request)
                }
                let filteredItems = filterItems(requestItems)
                updateRequestsRow(type, items: filteredItems)
                recentRequestsHydrationVersion += 1
                let hydrationVersion = recentRequestsHydrationVersion
                recentRequestsHydrationTask?.cancel()
                recentRequestsHydrationTask = Task {
                    await hydrateRequestsRow(type, items: filteredItems, version: hydrationVersion)
                }
            case .trending:
                let page = try await seerrRepository.getTrending(limit: limit, offset: 0)
                updateRow(type, page: page)
            case .popularMovies:
                let page = try await seerrRepository.getTopMovies(limit: limit, offset: 0)
                updateRow(type, page: page)
            case .popularSeries:
                let page = try await seerrRepository.getTopTv(limit: limit, offset: 0)
                updateRow(type, page: page)
            case .upcomingMovies:
                let page = try await seerrRepository.getUpcomingMovies()
                updateRow(type, page: page)
            case .upcomingSeries:
                let page = try await seerrRepository.getUpcomingTv()
                updateRow(type, page: page)
            case .movieGenres:
                let genres = try await seerrRepository.getGenreSliderMovies()
                updateGenreRow(type, genres: genres)
            case .seriesGenres:
                let genres = try await seerrRepository.getGenreSliderTv()
                updateGenreRow(type, genres: genres)
            case .studios:
                updateStudiosRow(type)
            case .networks:
                updateNetworksRow(type)
            }
        } catch {
            logger.warning("Failed to load \(type.rawValue): \(error.localizedDescription)")
            updateRowLoaded(type)
        }
    }

    private func updateRow(_ type: SeerrRowType, page: SeerrDiscoverPageDto) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].items = filterItems(page.results)
        rows[index].currentPage = page.page
        rows[index].totalPages = page.totalPages
        rows[index].isLoading = false
    }

    private func updateRequestsRow(_ type: SeerrRowType, items: [SeerrDiscoverItemDto]) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].items = items
        rows[index].isLoading = false
    }

    private func hydrateRequestsRow(_ type: SeerrRowType, items: [SeerrDiscoverItemDto], version: Int) async {
        var movieDetailsCache: [Int: SeerrMovieDetailsDto] = [:]
        var tvDetailsCache: [Int: SeerrTvDetailsDto] = [:]
        var hydratedItems: [SeerrDiscoverItemDto] = []
        hydratedItems.reserveCapacity(items.count)

        for item in items {
            guard !Task.isCancelled else { return }

            let tmdbId = item.id
            guard tmdbId > 0 else {
                hydratedItems.append(item)
                continue
            }

            if item.posterPath != nil && item.backdropPath != nil && item.voteAverage != nil {
                hydratedItems.append(item)
                continue
            }

            do {
                if item.mediaType == "tv" {
                    let details: SeerrTvDetailsDto
                    if let cached = tvDetailsCache[tmdbId] {
                        details = cached
                    } else {
                        let fetched = try await seerrRepository.getTvDetails(tmdbId: tmdbId)
                        tvDetailsCache[tmdbId] = fetched
                        details = fetched
                    }

                    hydratedItems.append(
                        SeerrDiscoverItemDto(
                            id: item.id,
                            mediaType: item.mediaType,
                            title: item.title,
                            name: item.name ?? details.name ?? details.title,
                            posterPath: details.posterPath ?? item.posterPath,
                            backdropPath: details.backdropPath ?? item.backdropPath,
                            overview: details.overview ?? item.overview,
                            releaseDate: item.releaseDate,
                            firstAirDate: item.firstAirDate,
                            genreIds: item.genreIds,
                            voteAverage: details.voteAverage ?? item.voteAverage,
                            adult: item.adult,
                            mediaInfo: item.mediaInfo,
                            requestStatus: item.requestStatus
                        )
                    )
                } else {
                    let details: SeerrMovieDetailsDto
                    if let cached = movieDetailsCache[tmdbId] {
                        details = cached
                    } else {
                        let fetched = try await seerrRepository.getMovieDetails(tmdbId: tmdbId)
                        movieDetailsCache[tmdbId] = fetched
                        details = fetched
                    }

                    hydratedItems.append(
                        SeerrDiscoverItemDto(
                            id: item.id,
                            mediaType: item.mediaType,
                            title: item.title ?? details.title,
                            name: item.name,
                            posterPath: details.posterPath ?? item.posterPath,
                            backdropPath: details.backdropPath ?? item.backdropPath,
                            overview: details.overview ?? item.overview,
                            releaseDate: item.releaseDate,
                            firstAirDate: item.firstAirDate,
                            genreIds: item.genreIds,
                            voteAverage: details.voteAverage ?? item.voteAverage,
                            adult: item.adult,
                            mediaInfo: item.mediaInfo,
                            requestStatus: item.requestStatus
                        )
                    )
                }
            } catch {
                hydratedItems.append(item)
            }
        }

        guard !Task.isCancelled else { return }
        guard version == recentRequestsHydrationVersion else { return }
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].items = hydratedItems
    }

    private func updateGenreRow(_ type: SeerrRowType, genres: [SeerrGenreDto]) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].genres = genres
        rows[index].isLoading = false
    }

    private func updateStudiosRow(_ type: SeerrRowType) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].studios = Self.popularStudios
        rows[index].isLoading = false
    }

    private func updateNetworksRow(_ type: SeerrRowType) {
        guard let index = rows.firstIndex(where: { $0.rowType == type }) else { return }
        rows[index].networks = Self.popularNetworks
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
