import Foundation

enum SeerrBrowseSortOption: String, CaseIterable {
    case popularity = "popularity.desc"
    case rating = "vote_average.desc"
    case releaseDate = "primary_release_date.desc"
    case title = "original_title.asc"
    case revenue = "revenue.desc"

    var displayName: String {
        switch self {
        case .popularity: return Strings.seerrSortPopularity
        case .rating: return Strings.rating
        case .releaseDate: return Strings.seerrSortReleaseDate
        case .title: return Strings.name
        case .revenue: return Strings.seerrRevenue
        }
    }
}

enum SeerrBrowseFilter: CaseIterable {
    case all
    case available
    case requested

    var displayName: String {
        switch self {
        case .all: return Strings.seerrFilterShowAll
        case .available: return Strings.seerrFilterAvailableOnly
        case .requested: return Strings.seerrFilterRequestedOnly
        }
    }

    var shortDisplayName: String {
        switch self {
        case .all: return Strings.allItems
        case .available: return Strings.seerrFilterAvailable
        case .requested: return Strings.seerrFilterRequested
        }
    }
}

@MainActor
final class SeerrBrowseByViewModel: ObservableObject {
    @Published var items: [SeerrDiscoverItemDto] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var focusedItem: SeerrDiscoverItemDto?
    @Published var sortOption: SeerrBrowseSortOption = .popularity
    @Published var activeFilter: SeerrBrowseFilter = .all
    @Published var posterSize: PosterSize = .medium

    let filterName: String

    private let filterId: Int
    private let mediaType: String
    private let filterType: String
    private let seerrRepository: SeerrRepositoryProtocol

    private var currentPage = 1
    private var totalPages = 1
    private var totalResults = 0
    private var allFetchedItems: [SeerrDiscoverItemDto] = []

    private var hasMorePages: Bool { currentPage < totalPages }

    var resultCountText: String {
        Strings.seerrCountOf(items.count, totalResults)
    }

    var totalItemsCount: Int {
        totalResults
    }

    var backdropUrl: String? {
        guard let path = focusedItem?.backdropPath else { return nil }
        return SeerrImageUrl.backdrop(path)
    }

    var cardDimensions: (width: CGFloat, height: CGFloat) {
        switch posterSize {
        case .smallest: return (120, 180)
        case .small: return (150, 225)
        case .medium: return (180, 270)
        case .large: return (220, 330)
        case .xLarge: return (270, 405)
        }
    }

    var statusText: String {
        var parts = [Strings.seerrShowing]
        parts.append(activeFilter.shortDisplayName)
        parts.append(Strings.seerrFromFilterName(filterName))
        parts.append(Strings.seerrSortedBy(sortOption.displayName))
        return parts.joined(separator: " ")
    }

    init(filterId: Int, filterName: String, mediaType: String, filterType: String,
         seerrRepository: SeerrRepositoryProtocol) {
        self.filterId = filterId
        self.filterName = filterName
        self.mediaType = mediaType
        self.filterType = filterType
        self.seerrRepository = seerrRepository
    }

    func loadInitial() {
        guard !isLoading else { return }
        isLoading = true
        currentPage = 1
        allFetchedItems = []
        items = []

        Task {
            await fetchPage(page: 1)
            isLoading = false
        }
    }

    func loadMore() {
        guard !isLoadingMore, hasMorePages else { return }
        isLoadingMore = true

        Task {
            await fetchPage(page: currentPage + 1)
            isLoadingMore = false
        }
    }

    func changeSortOption(_ option: SeerrBrowseSortOption) {
        guard option != sortOption else { return }
        sortOption = option
        loadInitial()
    }

    func changeFilter(_ filter: SeerrBrowseFilter) {
        guard filter != activeFilter else { return }
        activeFilter = filter
        applyFilter()
    }

    func itemJson(_ item: SeerrDiscoverItemDto) -> String? {
        guard let data = try? JSONEncoder().encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setFocusedItem(_ item: SeerrDiscoverItemDto) {
        focusedItem = item
    }

    func setPosterSize(_ size: PosterSize) {
        posterSize = size
    }

    func buildMetadata(for item: SeerrDiscoverItemDto) -> String {
        var parts: [String] = []
        if let year = releaseYear(for: item) {
            parts.append(year)
        }
        if let mediaType = item.mediaType {
            parts.append(mediaType == "tv" ? Strings.series : Strings.seerrMovie)
        }
        if let voteAverage = item.voteAverage, voteAverage > 0 {
            parts.append(" \(String(format: "%.1f", voteAverage))")
        }
        return parts.joined(separator: "  ")
    }

    private func fetchPage(page: Int) async {
        do {
            let result: SeerrDiscoverPageDto

            switch filterType.lowercased() {
            case "genre":
                if mediaType == "movie" {
                    result = try await seerrRepository.discoverMovies(
                        page: page, sortBy: sortOption.rawValue, genre: filterId, studio: nil, keywords: nil, language: "en")
                } else {
                    result = try await seerrRepository.discoverTv(
                        page: page, sortBy: sortOption.rawValue, genre: filterId, network: nil, keywords: nil, language: "en")
                }
            case "network":
                result = try await seerrRepository.discoverTv(
                    page: page, sortBy: sortOption.rawValue, genre: nil, network: filterId, keywords: nil, language: "en")
            case "studio":
                result = try await seerrRepository.discoverMovies(
                    page: page, sortBy: sortOption.rawValue, genre: nil, studio: filterId, keywords: nil, language: "en")
            case "keyword":
                if mediaType == "movie" {
                    result = try await seerrRepository.discoverMovies(
                        page: page, sortBy: sortOption.rawValue, genre: nil, studio: nil, keywords: filterId, language: "en")
                } else {
                    result = try await seerrRepository.discoverTv(
                        page: page, sortBy: sortOption.rawValue, genre: nil, network: nil, keywords: filterId, language: "en")
                }
            default:
                return
            }

            currentPage = result.page
            totalPages = result.totalPages
            totalResults = result.totalResults
            allFetchedItems.append(contentsOf: result.results)
            applyFilter()
        } catch {}
    }

    private func applyFilter() {
        switch activeFilter {
        case .all:
            items = allFetchedItems
        case .available:
            items = allFetchedItems.filter {
                $0.mediaInfo?.status == SeerrMediaInfoDto.statusPartiallyAvailable ||
                $0.mediaInfo?.status == SeerrMediaInfoDto.statusAvailable
            }
        case .requested:
            items = allFetchedItems.filter {
                $0.mediaInfo?.status == SeerrMediaInfoDto.statusPending ||
                $0.mediaInfo?.status == SeerrMediaInfoDto.statusProcessing
            }
        }

        if let focusedItem, items.contains(where: { $0.id == focusedItem.id }) {
            return
        }

        focusedItem = items.first
    }

    private func releaseYear(for item: SeerrDiscoverItemDto) -> String? {
        let rawDate = item.releaseDate ?? item.firstAirDate
        guard let rawDate else { return nil }
        return String(rawDate.prefix(4))
    }
}
