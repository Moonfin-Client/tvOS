import Foundation
import Combine
import os

enum SeerrMediaDetailsState {
    case loading
    case loaded
    case error(String)
}

struct SeerrMediaStatus {
    let text: String
    let color: StatusColor
    let icon: String

    private static func l(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    enum StatusColor {
        case green, yellow, red, blue, gray, orange
    }

    static let unknown = SeerrMediaStatus(text: l("seerr_status_not_requested"), color: .gray, icon: "questionmark.circle")
}

struct SeerrAdvancedOptions {
    var serverId: Int?
    var profileId: Int?
    var rootFolderId: Int?
}

@MainActor
final class SeerrMediaDetailsViewModel: ObservableObject {
    @Published var state: SeerrMediaDetailsState = .loading
    @Published var movieDetails: SeerrMovieDetailsDto?
    @Published var tvDetails: SeerrTvDetailsDto?
    @Published var similar: [SeerrDiscoverItemDto] = []
    @Published var recommendations: [SeerrDiscoverItemDto] = []
    @Published var currentUser: SeerrUserDto?
    @Published var mediaStatus = SeerrMediaStatus.unknown
    @Published var isRequesting = false
    @Published var requestError: String?
    @Published var showSeasonPicker = false
    @Published var showAdvancedOptions = false
    @Published var showQualityPicker = false
    @Published var selectedSeasons: Set<Int> = []
    @Published var pendingIs4k = false
    @Published var serverDetails: SeerrServiceServerDetailsDto?
    @Published var advancedOptions = SeerrAdvancedOptions()
    @Published var jellyfinItemId: String?

    let item: SeerrDiscoverItemDto
    let seerrRepository: SeerrRepositoryProtocol

    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "SeerrMediaDetails")

    var isMovie: Bool { item.mediaType == "movie" }
    var isTv: Bool { item.mediaType == "tv" }

    var displayTitle: String {
        if isMovie { return movieDetails?.title ?? item.displayTitle }
        return tvDetails?.displayTitle ?? item.displayTitle
    }

    var titleWithYear: String {
        if let year = year {
            return "\(displayTitle) (\(year))"
        }
        return displayTitle
    }

    var metadataChips: [String] {
        var parts: [String] = []
        if let runtime = runtimeText { parts.append(runtime) }
        let genreNames = genres.map(\.name)
        parts.append(contentsOf: genreNames)
        if parts.isEmpty, let year = year { parts.append(year) }
        return parts
    }

    var tagline: String? {
        isMovie ? movieDetails?.tagline : tvDetails?.tagline
    }

    var overview: String? {
        isMovie ? movieDetails?.overview : tvDetails?.overview
    }

    var posterUrl: String? {
        let path = isMovie ? movieDetails?.posterPath : tvDetails?.posterPath
        return (path ?? item.posterPath).map { SeerrImageUrl.poster($0) }
    }

    var backdropUrl: String? {
        let path = isMovie ? movieDetails?.backdropPath : tvDetails?.backdropPath
        return (path ?? item.backdropPath).map { SeerrImageUrl.backdrop($0) }
    }

    var genres: [SeerrGenreDto] {
        isMovie ? (movieDetails?.genres ?? []) : (tvDetails?.genres ?? [])
    }

    var cast: [SeerrCastMemberDto] {
        let credits = isMovie ? movieDetails?.credits : tvDetails?.credits
        return Array((credits?.cast ?? []).prefix(15))
    }

    var crew: [SeerrCrewMemberDto] {
        let credits = isMovie ? movieDetails?.credits : tvDetails?.credits
        return credits?.crew ?? []
    }

    var keywords: [SeerrKeywordDto] {
        isMovie ? (movieDetails?.keywords ?? []) : (tvDetails?.keywords ?? [])
    }

    var networks: [SeerrNetworkDto] {
        tvDetails?.networks ?? []
    }

    private var relatedVideos: [SeerrRelatedVideoDto] {
        isMovie ? (movieDetails?.relatedVideos ?? []) : (tvDetails?.relatedVideos ?? [])
    }

    var hasTrailer: Bool {
        trailerYouTubeKey != nil || trailerUrl != nil
    }

    private var preferredTrailer: SeerrRelatedVideoDto? {
        let trailers = relatedVideos.filter { $0.type?.lowercased() == "trailer" }
        let candidates = trailers.isEmpty ? relatedVideos : trailers

        return candidates.max { lhs, rhs in
            (lhs.size ?? 0) < (rhs.size ?? 0)
        }
    }

    var trailerYouTubeKey: String? {
        if let trailer = preferredTrailer,
           trailer.site?.lowercased() == "youtube" {
            if let key = trailer.key, !key.isEmpty {
                return key
            }

            if let url = trailer.url {
                return TrailerPlaybackHelper.extractYouTubeVideoId(from: url)
            }
        }

        for video in relatedVideos where video.site?.lowercased() == "youtube" {
            if let key = video.key, !key.isEmpty {
                return key
            }

            if let url = video.url,
               let extracted = TrailerPlaybackHelper.extractYouTubeVideoId(from: url) {
                return extracted
            }
        }

        return nil
    }

    var trailerUrl: String? {
        if let trailer = preferredTrailer,
           let url = trailer.url,
           !url.isEmpty {
            return url
        }

        return relatedVideos.lazy.compactMap(\.url).first { !$0.isEmpty }
    }

    private var isAvailable: Bool {
        let status = mediaInfo?.status ?? SeerrMediaInfoDto.statusUnknown
        return status == SeerrMediaInfoDto.statusAvailable || status == SeerrMediaInfoDto.statusPartiallyAvailable
    }

    var mediaInfo: SeerrMediaInfoDto? {
        isMovie ? movieDetails?.mediaInfo : tvDetails?.mediaInfo
    }

    var voteAverage: Double? {
        isMovie ? movieDetails?.voteAverage : tvDetails?.voteAverage
    }

    var year: String? {
        let date = isMovie ? movieDetails?.releaseDate : tvDetails?.firstAirDate
        guard let date, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    var runtimeText: String? {
        guard let runtime = movieDetails?.runtime, runtime > 0 else { return nil }
        let hours = runtime / 60
        let mins = runtime % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    var statusText: String? {
        isMovie ? movieDetails?.status : tvDetails?.status
    }

    var budgetText: String? {
        guard let budget = movieDetails?.budget, budget > 0 else { return nil }
        return formatCurrency(budget)
    }

    var revenueText: String? {
        guard let revenue = movieDetails?.revenue, revenue > 0 else { return nil }
        return formatCurrency(revenue)
    }

    var seasonCount: Int {
        tvDetails?.numberOfSeasons ?? 0
    }

    var episodeCount: Int? {
        tvDetails?.numberOfEpisodes
    }

    var canRequestHd: Bool {
        guard let user = currentUser else { return false }
        let status = mediaInfo?.status ?? SeerrMediaInfoDto.statusUnknown
        let hasDeclinedOnly = hasOnlyDeclinedRequests(is4k: false)
        let canRequest = status == SeerrMediaInfoDto.statusUnknown || hasDeclinedOnly
        if isMovie { return canRequest && user.hasPermission(SeerrUserDto.permissionRequestMovie) }
        return canRequest && user.hasPermission(SeerrUserDto.permissionRequestTv)
    }

    var canRequest4k: Bool {
        guard let user = currentUser else { return false }
        let status4k = mediaInfo?.status4k ?? SeerrMediaInfoDto.statusUnknown
        let hasDeclinedOnly = hasOnlyDeclinedRequests(is4k: true)
        let canRequest = status4k == SeerrMediaInfoDto.statusUnknown || hasDeclinedOnly
        if isMovie { return canRequest && user.canRequest4kMovies() }
        return canRequest && user.canRequest4kTv()
    }

    var hasPendingRequests: Bool {
        mediaInfo?.requests?.contains { $0.status == SeerrRequestDto.statusPending } ?? false
    }

    var showPlayButton: Bool {
        isAvailable
    }

    var director: String? {
        crew.first(where: { $0.job?.lowercased() == "director" })?.name
    }

    init(item: SeerrDiscoverItemDto, seerrRepository: SeerrRepositoryProtocol) {
        self.item = item
        self.seerrRepository = seerrRepository
    }

    func loadDetails() {
        guard case .loading = state else { return }

        Task {
            do {
                async let userTask: SeerrUserDto? = try? seerrRepository.getCurrentUser()
                if isMovie {
                    let details = try await seerrRepository.getMovieDetails(tmdbId: item.id)
                    movieDetails = details
                } else {
                    let details = try await seerrRepository.getTvDetails(tmdbId: item.id)
                    tvDetails = details
                }
                currentUser = await userTask
                updateMediaStatus()
                state = .loaded

                lookupJellyfinItem()
                loadRelatedContent()
            } catch {
                logger.error("Failed to load details: \(error.localizedDescription)")
                state = .error(error.localizedDescription)
            }
        }
    }

    private func loadRelatedContent() {
        Task {
            async let similarTask: Void = loadSimilar()
            async let recsTask: Void = loadRecommendations()
            _ = await (similarTask, recsTask)
        }
    }

    private func loadSimilar() async {
        do {
            let page: SeerrDiscoverPageDto
            if isMovie {
                page = try await seerrRepository.getSimilarMovies(tmdbId: item.id, page: 1)
            } else {
                page = try await seerrRepository.getSimilarTv(tmdbId: item.id, page: 1)
            }
            similar = page.results
        } catch {
            logger.warning("Failed to load similar: \(error.localizedDescription)")
        }
    }

    private func loadRecommendations() async {
        do {
            let page: SeerrDiscoverPageDto
            if isMovie {
                page = try await seerrRepository.getRecommendationsMovies(tmdbId: item.id, page: 1)
            } else {
                page = try await seerrRepository.getRecommendationsTv(tmdbId: item.id, page: 1)
            }
            recommendations = page.results
        } catch {
            logger.warning("Failed to load recommendations: \(error.localizedDescription)")
        }
    }

    func handleRequestTap() {
        if canRequestHd && canRequest4k {
            showQualityPicker = true
        } else if canRequest4k {
            beginRequest(is4k: true)
        } else {
            beginRequest(is4k: false)
        }
    }

    func qualityOptionLabel(is4k: Bool) -> String {
        let prefix = is4k ? "4K" : "HD"
        let status = is4k ? mediaInfo?.status4k : mediaInfo?.status

        switch status {
        case SeerrMediaInfoDto.statusPending:
            return Strings.seerrQualityPending(prefix)
        case SeerrMediaInfoDto.statusProcessing:
            return Strings.seerrQualityProcessing(prefix)
        case SeerrMediaInfoDto.statusPartiallyAvailable:
            return Strings.seerrRequestMore(prefix)
        case SeerrMediaInfoDto.statusAvailable:
            return Strings.seerrQualityAvailable(prefix)
        case SeerrMediaInfoDto.statusBlacklisted:
            return Strings.seerrQualityBlacklisted(prefix)
        default:
            return Strings.seerrRequest(prefix)
        }
    }

    func beginRequest(is4k: Bool) {
        pendingIs4k = is4k
        showQualityPicker = false

        if currentUser?.hasAdvancedRequestPermission() == true {
            loadServiceServers(is4k: is4k)
        } else if isTv {
            prepareSeasonSelection(is4k: is4k)
        } else {
            submitRequest(is4k: is4k)
        }
    }

    private func loadServiceServers(is4k: Bool) {
        Task {
            do {
                if isMovie {
                    let servers = try await seerrRepository.getRadarrServers()
                    if let defaultServer = servers.first(where: { $0.isDefault && $0.is4k == is4k }) ?? servers.first(where: { $0.is4k == is4k }) {
                        serverDetails = try await seerrRepository.getRadarrServerDetails(serverId: defaultServer.id)
                        advancedOptions.serverId = defaultServer.id
                    }
                } else {
                    let servers = try await seerrRepository.getSonarrServers()
                    if let defaultServer = servers.first(where: { $0.isDefault && $0.is4k == is4k }) ?? servers.first(where: { $0.is4k == is4k }) {
                        serverDetails = try await seerrRepository.getSonarrServerDetails(serverId: defaultServer.id)
                        advancedOptions.serverId = defaultServer.id
                    }
                }
                showAdvancedOptions = true
            } catch {
                logger.warning("Failed to load servers, proceeding without: \(error.localizedDescription)")
                if isTv {
                    prepareSeasonSelection(is4k: is4k)
                } else {
                    submitRequest(is4k: is4k)
                }
            }
        }
    }

    func confirmAdvancedOptions() {
        showAdvancedOptions = false
        if isTv {
            prepareSeasonSelection(is4k: pendingIs4k)
        } else {
            submitRequest(is4k: pendingIs4k)
        }
    }

    private func prepareSeasonSelection(is4k: Bool) {
        guard seasonCount > 0 else {
            submitRequest(is4k: is4k)
            return
        }

        let unavailable = getUnavailableSeasons(is4k: is4k)
        let available = Set((1...seasonCount).filter { !unavailable.contains($0) })
        selectedSeasons = available
        showSeasonPicker = true
    }

    func confirmSeasonSelection() {
        showSeasonPicker = false
        guard !selectedSeasons.isEmpty else { return }
        submitRequest(is4k: pendingIs4k, seasons: .list(Array(selectedSeasons).sorted()))
    }

    func submitRequest(is4k: Bool, seasons: SeerrSeasons? = nil) {
        isRequesting = true
        requestError = nil

        Task {
            do {
                let mediaType = isMovie ? "movie" : "tv"
                _ = try await seerrRepository.createRequest(
                    mediaId: item.id,
                    mediaType: mediaType,
                    seasons: seasons,
                    is4k: is4k,
                    profileId: advancedOptions.profileId,
                    rootFolderId: advancedOptions.rootFolderId,
                    serverId: advancedOptions.serverId
                )
                await refreshDetails()
            } catch {
                requestError = error.localizedDescription
                logger.error("Request failed: \(error.localizedDescription)")
            }
            isRequesting = false
        }
    }

    func cancelPendingRequests() {
        guard let requests = mediaInfo?.requests else { return }
        let pending = requests.filter { $0.status == SeerrRequestDto.statusPending }
        guard !pending.isEmpty else { return }

        isRequesting = true
        Task {
            for request in pending {
                do {
                    try await seerrRepository.deleteRequest(requestId: request.id)
                } catch {
                    logger.error("Failed to cancel request \(request.id): \(error.localizedDescription)")
                }
            }
            await refreshDetails()
            isRequesting = false
        }
    }

    private func refreshDetails() async {
        do {
            if isMovie {
                movieDetails = try await seerrRepository.getMovieDetails(tmdbId: item.id)
            } else {
                tvDetails = try await seerrRepository.getTvDetails(tmdbId: item.id)
            }
            updateMediaStatus()
        } catch {
            logger.error("Failed to refresh: \(error.localizedDescription)")
        }
    }

    private func updateMediaStatus() {
        let status = mediaInfo?.status ?? SeerrMediaInfoDto.statusUnknown
        let status4k = mediaInfo?.status4k ?? SeerrMediaInfoDto.statusUnknown

        let hdStatus = statusLabel(for: status)
        let fourKStatus = statusLabel(for: status4k)

        if status4k != SeerrMediaInfoDto.statusUnknown && status != SeerrMediaInfoDto.statusUnknown {
            let combined = "\(hdStatus.text) · 4K: \(fourKStatus.text)"
            mediaStatus = SeerrMediaStatus(text: combined, color: hdStatus.color, icon: hdStatus.icon)
        } else if status != SeerrMediaInfoDto.statusUnknown {
            mediaStatus = hdStatus
        } else if hasOnlyDeclinedRequests(is4k: false) {
            mediaStatus = SeerrMediaStatus(text: Strings.seerrStatusDeclined, color: .red, icon: "xmark.circle.fill")
        } else {
            mediaStatus = .unknown
        }
    }

    private func statusLabel(for status: Int) -> SeerrMediaStatus {
        switch status {
        case SeerrMediaInfoDto.statusAvailable:
            return SeerrMediaStatus(text: Strings.seerrStatusAvailable, color: .green, icon: "checkmark.circle.fill")
        case SeerrMediaInfoDto.statusPartiallyAvailable:
            return SeerrMediaStatus(text: Strings.seerrStatusPartiallyAvailable, color: .yellow, icon: "circle.lefthalf.filled")
        case SeerrMediaInfoDto.statusPending:
            return SeerrMediaStatus(text: Strings.seerrStatusPending, color: .orange, icon: "clock.fill")
        case SeerrMediaInfoDto.statusProcessing:
            return SeerrMediaStatus(text: Strings.seerrStatusProcessing, color: .blue, icon: "arrow.triangle.2.circlepath")
        case SeerrMediaInfoDto.statusBlacklisted:
            return SeerrMediaStatus(text: Strings.seerrStatusBlacklisted, color: .red, icon: "nosign")
        default:
            return .unknown
        }
    }

    private func hasOnlyDeclinedRequests(is4k: Bool) -> Bool {
        guard let requests = mediaInfo?.requests else { return false }
        let matching = requests.filter { $0.is4k == is4k }
        guard !matching.isEmpty else { return false }
        return matching.allSatisfy { $0.status == SeerrRequestDto.statusDeclined }
    }

    func getUnavailableSeasons(is4k: Bool) -> Set<Int> {
        guard let requests = mediaInfo?.requests else { return [] }
        var unavailable = Set<Int>()
        for request in requests where request.is4k == is4k && request.status != SeerrRequestDto.statusDeclined {
            if let seasons = request.seasons {
                for season in seasons {
                    unavailable.insert(season.seasonNumber)
                }
            }
        }
        return unavailable
    }

    func itemJson(_ item: SeerrDiscoverItemDto) -> String? {
        guard let data = try? JSONEncoder().encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formatCurrency(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private var serverClient: (any MediaServerClient)?

    func setServerClient(_ client: any MediaServerClient) {
        self.serverClient = client
    }

    private func lookupJellyfinItem() {
        guard isAvailable, jellyfinItemId == nil,
              let client = serverClient, let userId = client.userId else { return }
        Task {
            do {
                let types: [ItemType] = isMovie ? [.movie] : [.series]
                let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                    userId: userId,
                    recursive: true,
                    includeItemTypes: types,
                    fields: [.providerIds],
                    searchTerm: displayTitle,
                    limit: 10
                ))
                let tmdbId = String(item.id)
                if let match = result.items.first(where: { $0.providerIds?["Tmdb"] == tmdbId }) {
                    jellyfinItemId = match.id
                } else if let first = result.items.first {
                    jellyfinItemId = first.id
                }
            } catch {
                logger.warning("Jellyfin lookup failed: \(error.localizedDescription)")
            }
        }
    }
}
