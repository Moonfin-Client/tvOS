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
        guard currentItemId != item.id else { return }
        currentItemId = item.id

        let communityRating = item.communityRating
        let criticRating = item.criticRating

        guard enableAdditionalRatings, let tmdbId = item.tmdbId else {
            ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
            return
        }

        fetchAndApplyRatings(itemId: item.id, tmdbId: tmdbId, type: item.itemType, communityRating: communityRating, criticRating: criticRating)
    }

    func loadRatings(for item: ServerItem) {
        guard currentItemId != item.id else { return }
        currentItemId = item.id

        let tmdbId = item.providerIds?["Tmdb"]
        let communityRating = item.communityRating
        let criticRating = item.criticRating
        let episodeRatingsEnabled = userPreferences[UserPreferences.enableEpisodeRatings]
        let shouldFetchEpisodeRating = episodeRatingsEnabled && item.type == .episode
        let shouldFetchAdditionalRatings = enableAdditionalRatings && tmdbId != nil

        guard shouldFetchAdditionalRatings || shouldFetchEpisodeRating else {
            ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
            return
        }

        ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
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

            self.ratings = buildRatings(
                communityRating: communityRating,
                criticRating: criticRating,
                apiRatings: apiRatings,
                isEpisode: item.type == .episode,
                episodeRating: episodeRating,
                episodeRatingsEnabled: episodeRatingsEnabled
            )
        }
    }

    private func fetchAndApplyRatings(itemId: String, tmdbId: String, type: ItemType, communityRating: Double?, criticRating: Double?) {
        ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            defer { if currentItemId == itemId { isLoading = false } }

            let apiRatings = await mdbListRepository.getRatings(tmdbId: tmdbId, type: type)
            guard !Task.isCancelled, currentItemId == itemId else { return }

            self.ratings = buildRatings(
                communityRating: communityRating,
                criticRating: criticRating,
                apiRatings: apiRatings,
                isEpisode: false,
                episodeRating: nil,
                episodeRatingsEnabled: false
            )
        }
    }

    private func buildRatings(
        communityRating: Double?,
        criticRating: Double?,
        apiRatings: [(String, Float)]?,
        isEpisode: Bool,
        episodeRating: Float?,
        episodeRatingsEnabled: Bool
    ) -> [(String, Float)] {
        var result: [(String, Float)] = []
        func appendUnique(_ source: String, _ value: Float) {
            if !result.contains(where: { $0.0 == source }) {
                result.append((source, value))
            }
        }

        if let community = communityRating, community > 0 {
            appendUnique("stars", Float(community))
        }

        if let apiRatings {
            for (source, value) in apiRatings {
                if source == "tomatoes" && criticRating != nil { continue }
                if source == "tmdb" && isEpisode && episodeRatingsEnabled && episodeRating != nil { continue }
                let normalized = RatingSource(rawValue: source)?.normalize(value) ?? (value / 100.0)
                appendUnique(source, normalized)
            }
        }

        if let critic = criticRating, critic > 0 {
            appendUnique("tomatoes", RatingSource.tomatoes.normalize(Float(critic)))
        }

        if let episodeRating, episodeRating > 0 {
            appendUnique("tmdb_episode", episodeRating / 10.0)
        }

        return result
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        currentItemId = nil
        ratings = []
        isLoading = false
    }

    private func buildFallbackRatings(communityRating: Double?, criticRating: Double?) -> [(String, Float)] {
        var result: [(String, Float)] = []
        if let community = communityRating, community > 0 {
            result.append(("stars", Float(community)))
        }
        if let critic = criticRating, critic > 0 {
            result.append(("tomatoes", RatingSource.tomatoes.normalize(Float(critic))))
        }
        return result
    }

}
