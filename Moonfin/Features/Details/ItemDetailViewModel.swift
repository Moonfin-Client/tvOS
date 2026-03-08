import SwiftUI
import Combine

struct MediaBadge: Identifiable {
    let id = UUID()
    let label: String
}

struct ItemDetailUiState {
    var isLoading: Bool = true
    var item: ServerItem?
    var cast: [ServerPerson] = []
    var directors: [ServerPerson] = []
    var writers: [ServerPerson] = []
    var badges: [MediaBadge] = []
    var ratings: [(String, Float)] = []
    var seasons: [ServerItem] = []
    var episodes: [ServerItem] = []
    var similar: [ServerItem] = []
    var nextUp: [ServerItem] = []
    var collectionItems: [ServerItem] = []
    var tracks: [ServerItem] = []
    var albums: [ServerItem] = []
    var specialFeatures: [ServerItem] = []
    var filmography: [ServerItem] = []
    var instantMixItems: [ServerItem] = []
    var isFavorite: Bool = false
    var isPlayed: Bool = false
}

@MainActor
final class ItemDetailViewModel: ObservableObject {
    @Published private(set) var state = ItemDetailUiState()

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let itemId: String
    private let serverId: String?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, itemId: String, serverId: String?) {
        self.container = container
        self.itemId = itemId
        self.serverId = serverId
        backgroundService.configure(preferences: container.userPreferences)

        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    var canResume: Bool {
        (state.item?.userData?.playbackPositionTicks ?? 0) > 0
    }

    var nextEpisode: ServerItem? {
        guard let item = state.item,
              let currentIndex = item.indexNumber else { return nil }
        return state.episodes.first { ($0.indexNumber ?? 0) > currentIndex }
    }

    var resumePositionText: String? {
        guard let ticks = state.item?.userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return RuntimeFormatter.format(ticks: ticks)
    }

    private static let endsAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var endsAtText: String? {
        guard let ticks = state.item?.runTimeTicks, ticks > 0 else { return nil }
        let endDate = Date().addingTimeInterval(TimeInterval(ticks) / 10_000_000.0)
        return "Ends at \(Self.endsAtFormatter.string(from: endDate))"
    }

    func loadItem() {
        loadTask?.cancel()
        loadTask = Task {
            state = ItemDetailUiState(isLoading: true)

            guard let client else {
                state = ItemDetailUiState(isLoading: false)
                return
            }

            do {
                let item = try await client.userLibraryApi.getItem(itemId: itemId)

                let people = item.people ?? []
                let badges = buildMediaBadges(for: item)

                state = ItemDetailUiState(
                    isLoading: false,
                    item: item,
                    cast: people.filter { $0.type == .actor || $0.type == .guestStar },
                    directors: people.filter { $0.type == .director },
                    writers: people.filter { $0.type == .writer },
                    badges: badges,
                    isFavorite: item.userData?.isFavorite ?? false,
                    isPlayed: item.userData?.played ?? false
                )

                updateBackdrop(for: item)

                async let ratingsTask: () = loadRatings(for: item)
                async let additionalTask: () = loadAdditionalData(for: item, client: client)
                _ = await (ratingsTask, additionalTask)
            } catch {
                state = ItemDetailUiState(isLoading: false)
            }
        }
    }

    func toggleFavorite() {
        guard let client, let userId = client.userId else { return }
        let newValue = !state.isFavorite
        state.isFavorite = newValue

        Task {
            do {
                if newValue {
                    _ = try await client.userLibraryApi.markFavorite(itemId: itemId, userId: userId)
                } else {
                    _ = try await client.userLibraryApi.unmarkFavorite(itemId: itemId, userId: userId)
                }
            } catch {
                state.isFavorite = !newValue
            }
        }
    }

    func toggleWatched() {
        guard let client, let userId = client.userId else { return }
        let newValue = !state.isPlayed
        state.isPlayed = newValue

        Task {
            do {
                if newValue {
                    _ = try await client.userLibraryApi.markPlayed(itemId: itemId, userId: userId)
                } else {
                    _ = try await client.userLibraryApi.unmarkPlayed(itemId: itemId, userId: userId)
                }
            } catch {
                state.isPlayed = !newValue
            }
        }
    }

    private func updateBackdrop(for item: ServerItem) {
        guard let client else { return }

        var backdropUrls: [String] = []

        if let tags = item.backdropImageTags, !tags.isEmpty {
            for tag in tags {
                backdropUrls.append(client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .backdrop,
                    maxWidth: 1920,
                    maxHeight: nil,
                    tag: tag
                ))
            }
        } else if let parentId = item.parentBackdropItemId,
                  let tags = item.parentBackdropImageTags, !tags.isEmpty {
            for tag in tags {
                backdropUrls.append(client.imageApi.getItemImageUrl(
                    itemId: parentId,
                    imageType: .backdrop,
                    maxWidth: 1920,
                    maxHeight: nil,
                    tag: tag
                ))
            }
        }

        if backdropUrls.isEmpty, let primaryTag = item.imageTags?["Primary"] {
            backdropUrls.append(client.imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .primary,
                maxWidth: 1920,
                maxHeight: nil,
                tag: primaryTag
            ))
        }

        if !backdropUrls.isEmpty {
            backgroundService.setBackground(urls: backdropUrls, context: .details)
        }
    }

    func logoUrl(for item: ServerItem) -> String? {
        guard let client, let tag = item.imageTags?["Logo"] else { return nil }
        return client.imageApi.getItemImageUrl(
            itemId: item.id,
            imageType: .logo,
            maxWidth: 500,
            maxHeight: nil,
            tag: tag
        )
    }

    func posterUrl(for item: ServerItem) -> String? {
        guard let client, let tag = item.imageTags?["Primary"] else { return nil }
        return client.imageApi.getItemImageUrl(
            itemId: item.id,
            imageType: .primary,
            maxWidth: 400,
            maxHeight: nil,
            tag: tag
        )
    }

    func imageUrl(for person: ServerPerson) -> String? {
        guard let client, let id = person.id else { return nil }
        return client.imageApi.getItemImageUrl(
            itemId: id,
            imageType: .primary,
            maxWidth: 200,
            maxHeight: nil,
            tag: person.primaryImageTag
        )
    }

    func imageUrl(for item: ServerItem, imageType: ImageType = .primary, maxWidth: Int = 400) -> String? {
        guard let client else { return nil }
        let resolvedType: ImageType
        let tag: String?
        switch imageType {
        case .primary:
            tag = item.imageTags?["Primary"]
            resolvedType = .primary
        case .backdrop:
            tag = item.backdropImageTags?.first
            resolvedType = .backdrop
        case .thumb:
            if let t = item.imageTags?["Thumb"] {
                tag = t
                resolvedType = .thumb
            } else if let t = item.imageTags?["Primary"] {
                tag = t
                resolvedType = .primary
            } else if let t = item.backdropImageTags?.first {
                tag = t
                resolvedType = .backdrop
            } else {
                tag = nil
                resolvedType = .thumb
            }
        default:
            tag = nil
            resolvedType = imageType
        }
        return client.imageApi.getItemImageUrl(
            itemId: item.id,
            imageType: resolvedType,
            maxWidth: maxWidth,
            maxHeight: nil,
            tag: tag
        )
    }

    private func loadAdditionalData(for item: ServerItem, client: MediaServerClient) async {
        guard let userId = client.userId else { return }

        switch item.type {
        case .series:
            async let seasonsTask: () = loadSeasons(seriesId: item.id, userId: userId, client: client)
            async let nextUpTask: () = loadNextUp(seriesId: item.id, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (seasonsTask, nextUpTask, similarTask)

        case .season:
            guard let seriesId = item.seriesId else { return }
            async let episodesTask: () = loadEpisodes(seriesId: seriesId, seasonId: item.id, userId: userId, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (episodesTask, similarTask)

        case .episode:
            let seriesId = item.seriesId ?? ""
            let seasonId = item.seasonId ?? item.parentId ?? ""
            if !seriesId.isEmpty && !seasonId.isEmpty {
                async let episodesTask: () = loadEpisodes(seriesId: seriesId, seasonId: seasonId, userId: userId, client: client)
                async let similarTask: () = loadSimilar(itemId: item.id, client: client)
                _ = await (episodesTask, similarTask)
            } else {
                await loadSimilar(itemId: item.id, client: client)
            }

        case .boxSet:
            await loadCollectionItems(itemId: item.id, client: client)

        case .person:
            await loadFilmography(personId: item.id, client: client)

        case .musicArtist:
            async let albumsTask: () = loadArtistAlbums(artistId: item.id, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (albumsTask, similarTask)

        case .musicAlbum, .playlist:
            async let tracksTask: () = loadTracks(albumId: item.id, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (tracksTask, similarTask)

        case .movie, .video:
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            async let specialTask: () = loadSpecialFeatures(itemId: item.id, client: client)
            _ = await (similarTask, specialTask)

        default:
            await loadSimilar(itemId: item.id, client: client)
        }
    }

    private func loadSeasons(seriesId: String, userId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getSeasons(seriesId: seriesId, userId: userId)
            state.seasons = result.items
        } catch { }
    }

    private func loadEpisodes(seriesId: String, seasonId: String, userId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getEpisodes(seriesId: seriesId, seasonId: seasonId, userId: userId)
            state.episodes = result.items
        } catch { }
    }

    private func loadNextUp(seriesId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getNextUp(
                request: GetNextUpRequest(seriesId: seriesId, fields: [.overview], limit: 1)
            )
            state.nextUp = result.items
        } catch { }
    }

    private func loadSimilar(itemId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getSimilarItems(itemId: itemId, limit: 16)
            state.similar = result.items
        } catch { }
    }

    private func loadFilmography(personId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.movie, .series],
                    sortBy: [.premiereDate],
                    sortOrder: .descending,
                    limit: 100,
                    personIds: [personId],
                    enableUserData: true
                )
            )
            state.filmography = result.items

            let backdropUrls = result.items.compactMap { item -> String? in
                guard let tag = item.backdropImageTags?.first else { return nil }
                return client.imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .backdrop,
                    maxWidth: 1920,
                    maxHeight: nil,
                    tag: tag
                )
            }
            if !backdropUrls.isEmpty {
                backgroundService.setBackground(urls: Array(backdropUrls.prefix(10)), context: .details)
            }
        } catch { }
    }

    private func loadCollectionItems(itemId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getItems(
                request: GetItemsRequest(parentId: itemId)
            )
            state.collectionItems = result.items
        } catch { }
    }

    private func loadTracks(albumId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getItems(
                request: GetItemsRequest(parentId: albumId)
            )
            state.tracks = result.items
        } catch { }
    }

    private func loadArtistAlbums(artistId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.musicAlbum],
                    sortBy: [.premiereDate],
                    sortOrder: .descending,
                    artistIds: [artistId],
                    enableUserData: true
                )
            )
            state.albums = result.items
        } catch { }
    }

    func loadInstantMix() async {
        guard let item = state.item, let client else { return }
        do {
            let result = try await client.instantMixApi.getInstantMix(
                itemId: item.id,
                userId: client.userId,
                limit: 50
            )
            state.instantMixItems = result.items
        } catch { }
    }

    private func loadSpecialFeatures(itemId: String, client: MediaServerClient) async {
        do {
            let items = try await client.userLibraryApi.getSpecialFeatures(itemId: itemId)
            state.specialFeatures = items
        } catch { }
    }

    private func buildMediaBadges(for item: ServerItem) -> [MediaBadge] {
        var badges: [MediaBadge] = []

        if let streams = item.mediaStreams ?? item.mediaSources?.first?.mediaStreams {
            if let video = streams.first(where: { $0.type == .video }) {
                if let w = video.width, let h = video.height,
                   let res = ResolutionHelper.resolutionName(width: w, height: h) {
                    badges.append(MediaBadge(label: res))
                }
                if let codec = video.codec, !codec.isEmpty {
                    badges.append(MediaBadge(label: codec.uppercased()))
                }
            }
            if let audio = streams.first(where: { $0.type == .audio }) {
                if let codec = audio.codec, !codec.isEmpty {
                    badges.append(MediaBadge(label: codec.uppercased()))
                }
                if let channels = audio.channels {
                    badges.append(MediaBadge(label: Self.audioChannelLabel(channels: channels)))
                }
            }
        }

        if let container = item.container, !container.isEmpty {
            badges.append(MediaBadge(label: container.uppercased()))
        }

        return badges
    }

    func cleanup() {
        loadTask?.cancel()
        backgroundService.clearBackground()
    }

    private func loadRatings(for item: ServerItem) async {
        let communityRating = item.communityRating
        let criticRating = item.criticRating
        let tmdbId = item.providerIds?["Tmdb"]
        let enableAdditional = container.userPreferences[UserPreferences.enableAdditionalRatings]

        var result: [(String, Float)] = []

        if let community = communityRating, community > 0 {
            result.append(("stars", Float(community)))
        }

        if enableAdditional, let tmdbId {
            let apiRatings = await container.mdbListRepository.getRatings(tmdbId: tmdbId, type: item.type)
            if let apiRatings {
                for (source, value) in apiRatings {
                    if source == "tomatoes" && criticRating != nil { continue }
                    let normalized = RatingSource(rawValue: source)?.normalize(value) ?? (value / 100.0)
                    result.append((source, normalized))
                }
            }
        }

        if !result.contains(where: { $0.0 == "tomatoes" }),
           let critic = criticRating, critic > 0 {
            let normalized = RatingSource.tomatoes.normalize(Float(critic))
            result.append(("tomatoes", normalized))
        }

        state.ratings = result
    }

    private static func audioChannelLabel(channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }
}
