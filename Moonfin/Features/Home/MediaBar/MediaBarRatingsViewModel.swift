import SwiftUI
import Combine

@MainActor
final class MediaBarRatingsViewModel: ObservableObject {
    @Published private(set) var ratings: [(String, Float)] = []
    @Published private(set) var isLoading = false
    @Published private(set) var enableAdditionalRatings: Bool = true

    private let mdbListRepository: MdbListRepository
    private let tmdbRepository: TmdbRepository
    private let userPreferences: UserPreferences
    private var currentItemId: String?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(mdbListRepository: MdbListRepository, tmdbRepository: TmdbRepository, userPreferences: UserPreferences) {
        self.mdbListRepository = mdbListRepository
        self.tmdbRepository = tmdbRepository
        self.userPreferences = userPreferences
        self.enableAdditionalRatings = userPreferences[UserPreferences.enableAdditionalRatings]
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
        enableAdditionalRatings = userPreferences[UserPreferences.enableAdditionalRatings]
    }

    func loadRatings(for item: MediaBarSlideItem) {
        currentItemId = item.id

        let communityRating = item.communityRating
        let criticRating = item.criticRating
        let enabledSourcesOrder = RatingSource.canonicalEnabledSourceOrder(userPreferences[UserPreferences.enabledRatings])
        let fallbackRatings = buildFallbackRatings(
            communityRating: communityRating,
            criticRating: criticRating,
            enabledSourcesOrdered: enabledSourcesOrder,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: false,
            enableEpisodeRatings: false,
            hasEpisodeRating: false
        )

        guard enableAdditionalRatings, let tmdbId = item.tmdbId else {
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
            ratings = fallbackRatings
            return
        }

        ratings = fallbackRatings
        fetchAndApplyRatings(
            itemId: item.id,
            tmdbId: tmdbId,
            type: item.itemType,
            communityRating: communityRating,
            criticRating: criticRating,
            enabledSourcesOrdered: enabledSourcesOrder
        )
    }

    func loadRatings(for item: ServerItem) {
        currentItemId = item.id

        let tmdbId = item.providerIds?["Tmdb"]
        let communityRating = item.communityRating
        let criticRating = item.criticRating
        let episodeRatingsEnabled = userPreferences[UserPreferences.enableEpisodeRatings]
        let enabledSourcesOrder = RatingSource.canonicalEnabledSourceOrder(userPreferences[UserPreferences.enabledRatings])
        let shouldFetchEpisodeRating = episodeRatingsEnabled && item.type == .episode
        let shouldFetchAdditionalRatings = enableAdditionalRatings && tmdbId != nil

        let fallbackRatings = buildFallbackRatings(
            communityRating: communityRating,
            criticRating: criticRating,
            enabledSourcesOrdered: enabledSourcesOrder,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: item.type == .episode,
            enableEpisodeRatings: episodeRatingsEnabled,
            hasEpisodeRating: false
        )

        guard shouldFetchAdditionalRatings || shouldFetchEpisodeRating else {
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
            ratings = fallbackRatings
            return
        }

        ratings = fallbackRatings
        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            defer { if currentItemId == item.id { isLoading = false } }

            var apiRatings: [(String, Float)]?
            if shouldFetchAdditionalRatings, let tmdbId {
                apiRatings = await mdbListRepository.getRatings(tmdbId: tmdbId, type: item.type)
            }

            var episodeRating: Float?
            if shouldFetchEpisodeRating {
                episodeRating = await tmdbRepository.getEpisodeRating(item: item)
            }

            guard !Task.isCancelled, currentItemId == item.id else { return }

            let resolvedRatings = buildRatings(
                communityRating: communityRating,
                criticRating: criticRating,
                apiRatings: apiRatings,
                isEpisode: item.type == .episode,
                episodeRating: episodeRating,
                episodeRatingsEnabled: episodeRatingsEnabled,
                enabledSourcesOrdered: enabledSourcesOrder,
                enableAdditionalRatings: enableAdditionalRatings
            )
            self.ratings = resolvedRatings.isEmpty
                ? fallbackRatings
                : resolvedRatings
        }
    }

    private func fetchAndApplyRatings(
        itemId: String,
        tmdbId: String,
        type: ItemType,
        communityRating: Double?,
        criticRating: Double?,
        enabledSourcesOrdered: [String]
    ) {
        let fallbackRatings = buildFallbackRatings(
            communityRating: communityRating,
            criticRating: criticRating,
            enabledSourcesOrdered: enabledSourcesOrdered,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: false,
            enableEpisodeRatings: false,
            hasEpisodeRating: false
        )
        ratings = fallbackRatings
        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            defer { if currentItemId == itemId { isLoading = false } }

            let apiRatings = await mdbListRepository.getRatings(tmdbId: tmdbId, type: type)
            guard !Task.isCancelled, currentItemId == itemId else { return }

            let resolvedRatings = buildRatings(
                communityRating: communityRating,
                criticRating: criticRating,
                apiRatings: apiRatings,
                isEpisode: false,
                episodeRating: nil,
                episodeRatingsEnabled: false,
                enabledSourcesOrdered: enabledSourcesOrdered,
                enableAdditionalRatings: enableAdditionalRatings
            )
            self.ratings = resolvedRatings.isEmpty
                ? fallbackRatings
                : resolvedRatings
        }
    }

    private func buildRatings(
        communityRating: Double?,
        criticRating: Double?,
        apiRatings: [(String, Float)]?,
        isEpisode: Bool,
        episodeRating: Float?,
        episodeRatingsEnabled: Bool,
        enabledSourcesOrdered: [String],
        enableAdditionalRatings: Bool
    ) -> [(String, Float)] {
        var result: [(String, Float)] = []
        func appendUnique(_ source: String, _ value: Float) {
            let canonical = RatingSource.canonicalSourceRawValue(source)
            guard !canonical.isEmpty else { return }
            if !result.contains(where: { $0.0 == canonical }) {
                result.append((canonical, value))
            }
        }

        if let community = communityRating, community > 0 {
            appendUnique("stars", Float(community))
        }

        if let apiRatings {
            for (source, value) in apiRatings {
                let canonical = RatingSource.canonicalSourceRawValue(source)
                if canonical == "tomatoes" && criticRating != nil { continue }
                if canonical == "tmdb" && isEpisode && episodeRatingsEnabled && episodeRating != nil { continue }
                if let normalized = RatingSource.normalizedApiRating(source: canonical, rawValue: value) {
                    appendUnique(normalized.source, normalized.normalizedValue)
                }
            }
        }

        if let critic = criticRating, critic > 0 {
            appendUnique("tomatoes", RatingSource.tomatoes.normalize(Float(critic)))
        }

        if let episodeRating, episodeRating > 0 {
            appendUnique("tmdb_episode", episodeRating / 10.0)
        }

        return RatingDisplayPolicy.apply(
            ratings: result,
            enabledSourcesOrdered: enabledSourcesOrdered,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: isEpisode,
            enableEpisodeRatings: episodeRatingsEnabled,
            hasEpisodeRating: episodeRating != nil
        )
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentItemId = nil
        ratings = []
        isLoading = false
    }

    private func buildFallbackRatings(
        communityRating: Double?,
        criticRating: Double?,
        enabledSourcesOrdered: [String],
        enableAdditionalRatings: Bool,
        isEpisode: Bool,
        enableEpisodeRatings: Bool,
        hasEpisodeRating: Bool
    ) -> [(String, Float)] {
        var result: [(String, Float)] = []
        if let community = communityRating, community > 0 {
            result.append((RatingSource.communityRawValue, Float(community)))
        }
        if let critic = criticRating, critic > 0 {
            result.append(("tomatoes", RatingSource.tomatoes.normalize(Float(critic))))
        }
        return RatingDisplayPolicy.apply(
            ratings: result,
            enabledSourcesOrdered: enabledSourcesOrdered,
            enableAdditionalRatings: enableAdditionalRatings,
            isEpisode: isEpisode,
            enableEpisodeRatings: enableEpisodeRatings,
            hasEpisodeRating: hasEpisodeRating
        )
    }

}
