import SwiftUI
import Combine

struct MediaBadge: Identifiable, Equatable {
    let id = UUID()
    let label: String
}

@MainActor
final class ItemDetailViewModel: ObservableObject {
    private static let parentCollectionMediaTypes: [ItemType] = [.movie, .series, .video, .trailer]

    // Core
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var item: ServerItem?

    // People
    @Published private(set) var cast: [ServerPerson] = []
    @Published private(set) var directors: [ServerPerson] = []
    @Published private(set) var writers: [ServerPerson] = []

    // Metadata
    @Published private(set) var badges: [MediaBadge] = []
    @Published private(set) var ratings: [(String, Float)] = []

    // Content lists
    @Published private(set) var seasons: [ServerItem] = []
    @Published private(set) var episodes: [ServerItem] = []
    @Published private(set) var similar: [ServerItem] = []
    @Published private(set) var nextUp: [ServerItem] = []
    @Published private(set) var collectionItems: [ServerItem] = []
    @Published private(set) var parentCollectionName: String?
    @Published private(set) var parentCollectionItems: [ServerItem] = []
    @Published private(set) var tracks: [ServerItem] = []
    @Published private(set) var albums: [ServerItem] = []
    @Published private(set) var specialFeatures: [ServerItem] = []
    @Published private(set) var filmography: [ServerItem] = []
    @Published private(set) var instantMixItems: [ServerItem] = []

    // User actions
    @Published private(set) var isFavorite: Bool = false
    @Published private(set) var isPlayed: Bool = false

    @Published private(set) var showRatingLabels: Bool = false
    @Published private(set) var enableEpisodeRatings: Bool = false

    let backgroundService = BackgroundService()
    let themeMusicPlayer = ThemeMusicPlayer()

    private let container: AppContainer
    private let itemId: String
    private let serverId: String?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastEnableAdditionalRatings: Bool = true
    private var lastEnableEpisodeRatings: Bool = false

    init(container: AppContainer, itemId: String, serverId: String?) {
        self.container = container
        self.itemId = itemId
        self.serverId = serverId
        self.showRatingLabels = container.userPreferences[UserPreferences.showRatingLabels]
        self.enableEpisodeRatings = container.userPreferences[UserPreferences.enableEpisodeRatings]
        self.lastEnableAdditionalRatings = container.userPreferences[UserPreferences.enableAdditionalRatings]
        self.lastEnableEpisodeRatings = container.userPreferences[UserPreferences.enableEpisodeRatings]
        backgroundService.configure(preferences: container.userPreferences)

        // Throttle background service updates to max 1 per 300ms to avoid
        // re-rendering the entire view on every backdrop cycle tick.
        backgroundService.objectWillChange
            .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Theme music changes are infrequent - no throttle needed.
        themeMusicPlayer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        observePreferenceChanges()
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPreferences()
            }
            .store(in: &cancellables)
    }

    private func refreshPreferences() {
        let prefs = container.userPreferences
        showRatingLabels = prefs[UserPreferences.showRatingLabels]
        let newEnableEpisode = prefs[UserPreferences.enableEpisodeRatings]
        enableEpisodeRatings = newEnableEpisode

        if newEnableEpisode != lastEnableEpisodeRatings {
            lastEnableEpisodeRatings = newEnableEpisode
            if let item {
                Task { await loadRatings(for: item) }
            }
        }

        let newEnableAdditional = prefs[UserPreferences.enableAdditionalRatings]
        if newEnableAdditional != lastEnableAdditionalRatings {
            lastEnableAdditionalRatings = newEnableAdditional
            if let item {
                Task { await loadRatings(for: item) }
            }
        }
    }

    private var client: MediaServerClient? {
        if let serverId,
           let parsedId = UUID.from(rawId: serverId),
           let server = container.serverRepository.storedServers.value.first(where: { $0.id == parsedId }) {
            return container.serverClientFactory.client(for: server)
        }

        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    var canResume: Bool {
        (item?.userData?.playbackPositionTicks ?? 0) > 0
    }

    var canManagePlaylistTracks: Bool {
        item?.type == .playlist && !tracks.isEmpty
    }

    var nextEpisode: ServerItem? {
        guard let item,
              let currentIndex = item.indexNumber else { return nil }
        return episodes.first { ($0.indexNumber ?? 0) > currentIndex }
    }

    var resumePositionText: String? {
        guard let ticks = item?.userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return RuntimeFormatter.format(ticks: ticks)
    }

    private static let endsAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var endsAtText: String? {
        guard let ticks = item?.runTimeTicks, ticks > 0 else { return nil }
        let endDate = Date().addingTimeInterval(TimeInterval(ticks) / 10_000_000.0)
        return "Ends at \(Self.endsAtFormatter.string(from: endDate))"
    }

    private func resetState() {
        isLoading = true
        item = nil
        cast = []; directors = []; writers = []
        badges = []; ratings = []
        seasons = []; episodes = []; similar = []
        nextUp = []; collectionItems = []; tracks = []
        albums = []; specialFeatures = []; filmography = []
        parentCollectionName = nil; parentCollectionItems = []
        instantMixItems = []
        isFavorite = false; isPlayed = false
    }

    func loadItem() {
        loadTask?.cancel()
        loadTask = Task {
            resetState()

            guard let client else {
                isLoading = false
                return
            }

            do {
                let fetchedItem = try await client.userLibraryApi.getItem(itemId: itemId)

                let people = fetchedItem.people ?? []
                let computedBadges = buildMediaBadges(for: fetchedItem)

                self.item = fetchedItem
                self.cast = people.filter { $0.type == .actor || $0.type == .guestStar }
                self.directors = people.filter { $0.type == .director }
                self.writers = people.filter { $0.type == .writer }
                self.badges = computedBadges
                self.isFavorite = fetchedItem.userData?.isFavorite ?? false
                self.isPlayed = fetchedItem.userData?.played ?? false
                self.isLoading = false

                updateBackdrop(for: fetchedItem)
                themeMusicPlayer.playThemeMusic(for: fetchedItem, client: client, preferences: container.userPreferences)
                container.spotlightIndexer.indexItems([fetchedItem])

                async let ratingsTask: () = loadRatings(for: fetchedItem)
                async let additionalTask: () = loadAdditionalData(for: fetchedItem, client: client)
                _ = await (ratingsTask, additionalTask)
            } catch {
                isLoading = false
            }
        }
    }

    func toggleFavorite() {
        let newValue = !isFavorite
        isFavorite = newValue

        Task {
            do {
                _ = try await container.itemMutationService.setFavorite(itemId: itemId, isFavorite: newValue)
            } catch {
                isFavorite = !newValue
            }
        }
    }

    func toggleWatched() {
        let newValue = !isPlayed
        isPlayed = newValue

        Task {
            do {
                _ = try await container.itemMutationService.setPlayed(itemId: itemId, isPlayed: newValue)
            } catch {
                isPlayed = !newValue
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
            async let episodeSpecialTask: () = loadSpecialFeatures(itemId: item.id, client: client)
            if !seriesId.isEmpty && !seasonId.isEmpty {
                async let episodesTask: () = loadEpisodes(seriesId: seriesId, seasonId: seasonId, userId: userId, client: client)
                async let similarTask: () = loadSimilar(itemId: item.id, client: client)
                _ = await (episodesTask, similarTask, episodeSpecialTask)
            } else {
                async let similarTask: () = loadSimilar(itemId: item.id, client: client)
                _ = await (similarTask, episodeSpecialTask)
            }

        case .boxSet:
            await loadCollectionItems(itemId: item.id, client: client)

        case .person:
            await loadFilmography(personId: item.id, client: client)

        case .musicArtist, .albumArtist:
            async let albumsTask: () = loadArtistAlbums(artistId: item.id, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (albumsTask, similarTask)

        case .musicAlbum, .playlist:
            async let tracksTask: () = loadTracks(albumId: item.id, client: client)
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            _ = await (tracksTask, similarTask)

        case .movie:
            async let similarTask: () = loadSimilar(itemId: item.id, client: client)
            async let specialTask: () = loadSpecialFeatures(itemId: item.id, client: client)
            async let collectionTask: () = loadParentCollection(itemId: item.id, client: client)
            _ = await (similarTask, specialTask, collectionTask)

        case .trailer, .video:
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
            seasons = result.items
        } catch { }
    }

    private func loadEpisodes(seriesId: String, seasonId: String, userId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getEpisodes(seriesId: seriesId, seasonId: seasonId, userId: userId)
            episodes = result.items
        } catch { }
    }

    private func loadNextUp(seriesId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getNextUp(
                request: GetNextUpRequest(seriesId: seriesId, fields: [.overview], limit: 1)
            )
            nextUp = result.items
        } catch { }
    }

    private func loadSimilar(itemId: String, client: MediaServerClient) async {
        do {
            let result = try await client.itemsApi.getSimilarItems(itemId: itemId, limit: 16)
            similar = result.items
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
                    limit: 50,
                    personIds: [personId],
                    enableUserData: true
                )
            )
            filmography = result.items

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
                request: GetItemsRequest(
                    parentId: itemId,
                    limit: 120,
                    enableUserData: true
                )
            )
            collectionItems = result.items
        } catch { }
    }

    private func loadTracks(albumId: String, client: MediaServerClient) async {
        do {
            let result: ItemsResult
            if item?.type == .playlist {
                result = try await client.itemsApi.getPlaylistItems(itemId: albumId, userId: client.userId)
            } else {
                result = try await client.itemsApi.getItems(
                    request: GetItemsRequest(
                        parentId: albumId,
                        includeItemTypes: [ItemType.audio],
                        sortBy: [.indexNumber]
                    )
                )
            }
            tracks = result.items.filter { $0.type == ItemType.audio }
        } catch { }
    }

    func removeTrackFromPlaylist(_ track: ServerItem) async {
        guard let item, item.type == .playlist,
              let client else { return }

        let entryId = track.playlistItemId ?? track.id

        let previousTracks = tracks
        tracks = tracks.filter { ($0.playlistItemId ?? $0.id) != entryId }

        do {
            try await client.playlistApi.removeFromPlaylist(playlistId: item.id, entryIds: [entryId])
            await loadTracks(albumId: item.id, client: client)
        } catch {
            tracks = previousTracks
        }
    }

    func movePlaylistItem(fromIndex: Int, toIndex: Int) async {
        guard let item, item.type == .playlist,
              fromIndex != toIndex,
              fromIndex >= 0, fromIndex < tracks.count,
              toIndex >= 0, toIndex < tracks.count,
              let client else { return }

        let playlistEntryId = tracks[fromIndex].playlistItemId
        let itemId = tracks[fromIndex].id

        var reordered = tracks
        let moved = reordered.remove(at: fromIndex)
        reordered.insert(moved, at: toIndex)
        tracks = reordered

        do {
            if let playlistEntryId {
                do {
                    try await client.playlistApi.moveItem(playlistId: item.id, itemId: playlistEntryId, newIndex: toIndex)
                } catch {
                    try await client.playlistApi.moveItem(playlistId: item.id, itemId: itemId, newIndex: toIndex)
                }
            } else {
                try await client.playlistApi.moveItem(playlistId: item.id, itemId: itemId, newIndex: toIndex)
            }

            do {
                let refreshed = try await client.itemsApi.getPlaylistItems(itemId: item.id, userId: client.userId)
                let refreshedTracks = refreshed.items.filter { $0.type == ItemType.audio }

                tracks = refreshedTracks
            } catch { }
        } catch { }
    }

    func deleteCurrentPlaylist() async -> Bool {
        guard let item, item.type == .playlist, (item.canDelete ?? false), let client else {
            return false
        }

        do {
            try await client.userLibraryApi.deleteItem(itemId: item.id)
            return true
        } catch {
            return false
        }
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
            albums = result.items
        } catch { }
    }

    func loadInstantMix() async {
        guard let item, let client else { return }
        do {
            let result = try await client.instantMixApi.getInstantMix(
                itemId: item.id,
                userId: client.userId,
                limit: 50
            )
            instantMixItems = result.items
        } catch { }
    }

    func chapterImageUrl(for chapter: ServerChapter) -> String? {
        guard let item,
              let chapters = item.chapters,
              let tag = chapter.imageTag,
              let index = chapters.firstIndex(where: { $0.startPositionTicks == chapter.startPositionTicks }),
              let client else { return nil }

        return client.imageApi.getChapterImageUrl(
            itemId: item.id,
            chapterIndex: index,
            maxWidth: 480,
            tag: tag
        )
    }

    private func loadSpecialFeatures(itemId: String, client: MediaServerClient) async {
        do {
            let items = try await client.userLibraryApi.getSpecialFeatures(itemId: itemId)
            specialFeatures = items
        } catch { }
    }

    private func loadParentCollection(itemId: String, client: MediaServerClient) async {
        do {
            let collapsed = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.movie, .series, .boxSet],
                    ids: [itemId],
                    collapseBoxSetItems: true
                )
            )
            if let boxSet = collapsed.items.first(where: { $0.type == ItemType.boxSet }) {
                let members = try await client.itemsApi.getItems(
                    request: GetItemsRequest(
                        parentId: boxSet.id,
                        includeItemTypes: Self.parentCollectionMediaTypes,
                        sortBy: [.premiereDate, .sortName],
                        sortOrder: .ascending,
                        limit: 120,
                        enableUserData: true
                    )
                )
                parentCollectionName = boxSet.name
                parentCollectionItems = members.items
                return
            }

            let candidateBoxSets = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    recursive: true,
                    includeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    fields: [.childCount],
                    limit: 75
                )
            )

            for boxSet in candidateBoxSets.items where (boxSet.childCount ?? 0) > 0 {
                let members = try await client.itemsApi.getItems(
                    request: GetItemsRequest(
                        parentId: boxSet.id,
                        includeItemTypes: Self.parentCollectionMediaTypes,
                        limit: 1,
                        ids: [itemId]
                    )
                )
                if !members.items.isEmpty {
                    let sortedMembers = try await client.itemsApi.getItems(
                        request: GetItemsRequest(
                            parentId: boxSet.id,
                            includeItemTypes: Self.parentCollectionMediaTypes,
                            sortBy: [.premiereDate, .sortName],
                            sortOrder: .ascending,
                            limit: 120,
                            enableUserData: true
                        )
                    )
                    parentCollectionName = boxSet.name
                    parentCollectionItems = sortedMembers.items
                    return
                }
            }
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
        themeMusicPlayer.fadeOutAndStop()
        backgroundService.clearBackground()
    }

    private func loadRatings(for item: ServerItem) async {
        let communityRating = item.communityRating
        let criticRating = item.criticRating
        let tmdbId = item.providerIds?["Tmdb"]
        let enableAdditional = container.userPreferences[UserPreferences.enableAdditionalRatings]
        let enableEpisodeRatings = container.userPreferences[UserPreferences.enableEpisodeRatings]
        let isEpisode = item.type == .episode

        var result: [(String, Float)] = []
        func appendUnique(_ source: String, _ value: Float) {
            if !result.contains(where: { $0.0 == source }) {
                result.append((source, value))
            }
        }
        var episodeRating: Float?

        if enableEpisodeRatings && isEpisode {
            episodeRating = await container.tmdbRepository.getEpisodeRating(item: item)
        }

        if let community = communityRating, community > 0 {
            appendUnique("stars", Float(community))
        }

        if enableAdditional, let tmdbId {
            let apiRatings = await container.mdbListRepository.getRatings(tmdbId: tmdbId, type: item.type)
            if let apiRatings {
                for (source, value) in apiRatings {
                    if source == "tomatoes" && criticRating != nil { continue }
                    if source == "tmdb" && isEpisode && enableEpisodeRatings && episodeRating != nil { continue }
                    let normalized = RatingSource(rawValue: source)?.normalize(value) ?? (value / 100.0)
                    appendUnique(source, normalized)
                }
            }
        }

        if let critic = criticRating, critic > 0 {
            let normalized = RatingSource.tomatoes.normalize(Float(critic))
            appendUnique("tomatoes", normalized)
        }

        if let episodeRating, episodeRating > 0 {
            appendUnique("tmdb_episode", episodeRating / 10.0)
        }

        ratings = result
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
