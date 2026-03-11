import Foundation
import os

enum SeerrBrowseSortOption: String, CaseIterable {
    case popularity = "popularity.desc"
    case rating = "vote_average.desc"
    case releaseDate = "primary_release_date.desc"
    case title = "original_title.asc"
    case revenue = "revenue.desc"

    var displayName: String {
        switch self {
        case .popularity: return "Popularity"
        case .rating: return "Rating"
        case .releaseDate: return "Release Date"
        case .title: return "Title"
        case .revenue: return "Revenue"
        }
    }
}

enum SeerrBrowseFilter: CaseIterable {
    case all
    case available
    case requested

    var displayName: String {
        switch self {
        case .all: return "Show All"
        case .available: return "Available Only"
        case .requested: return "Requested Only"
        }
    }
}

@MainActor
final class SeerrBrowseByViewModel: ObservableObject {
    @Published var items: [SeerrDiscoverItemDto] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var sortOption: SeerrBrowseSortOption = .popularity
    @Published var activeFilter: SeerrBrowseFilter = .all
    @Published var showSortPicker = false
    @Published var showFilterPicker = false

    let filterName: String

    private let filterId: Int
    private let mediaType: String
    private let filterType: String
    private let seerrRepository: SeerrRepositoryProtocol
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SeerrBrowseBy")

    private var currentPage = 1
    private var totalPages = 1
    private var totalResults = 0
    private var allFetchedItems: [SeerrDiscoverItemDto] = []

    private var hasMorePages: Bool { currentPage < totalPages }

    var resultCountText: String {
        "\(items.count) of \(totalResults)"
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

    private func fetchPage(page: Int) async {
        do {
            let result: SeerrDiscoverPageDto

            switch filterType.lowercased() {
            case "genre":
                if mediaType == "movie" {
                    result = try await seerrRepository.discoverMovies(
                        page: page, sortBy: sortOption.rawValue, genre: filterId)
                } else {
                    result = try await seerrRepository.discoverTv(
                        page: page, sortBy: sortOption.rawValue, genre: filterId)
                }
            case "network":
                result = try await seerrRepository.discoverTv(
                    page: page, sortBy: sortOption.rawValue, network: filterId)
            case "studio":
                result = try await seerrRepository.discoverMovies(
                    page: page, sortBy: sortOption.rawValue, studio: filterId)
            case "keyword":
                if mediaType == "movie" {
                    result = try await seerrRepository.discoverMovies(
                        page: page, sortBy: sortOption.rawValue, keywords: filterId)
                } else {
                    result = try await seerrRepository.discoverTv(
                        page: page, sortBy: sortOption.rawValue, keywords: filterId)
                }
            default:
                logger.error("Unknown filter type: \(self.filterType)")
                return
            }

            currentPage = result.page
            totalPages = result.totalPages
            totalResults = result.totalResults
            allFetchedItems.append(contentsOf: result.results)
            applyFilter()
        } catch {
            logger.error("Failed to fetch browse content: \(error.localizedDescription)")
        }
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
    }
}
