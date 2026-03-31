import SwiftUI
import Combine

@MainActor
final class MediaBarRatingsViewModel: ObservableObject {
    @Published private(set) var ratings: [(String, Float)] = []
    @Published private(set) var isLoading = false
    @Published private(set) var enableAdditionalRatings: Bool = true

    private let mdbListRepository: MdbListRepository
    private let userPreferences: UserPreferences
    private var currentItemId: String?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(mdbListRepository: MdbListRepository, userPreferences: UserPreferences) {
        self.mdbListRepository = mdbListRepository
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

        guard enableAdditionalRatings, let tmdbId else {
            ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
            return
        }

        fetchAndApplyRatings(itemId: item.id, tmdbId: tmdbId, type: item.type, communityRating: communityRating, criticRating: criticRating)
    }

    private func fetchAndApplyRatings(itemId: String, tmdbId: String, type: ItemType, communityRating: Double?, criticRating: Double?) {
        ratings = buildFallbackRatings(communityRating: communityRating, criticRating: criticRating)
        isLoading = true
        loadTask?.cancel()
        loadTask = Task {
            defer { if currentItemId == itemId { isLoading = false } }

            let apiRatings = await mdbListRepository.getRatings(tmdbId: tmdbId, type: type)
            guard !Task.isCancelled, currentItemId == itemId else { return }

            var result: [(String, Float)] = []

            if let community = communityRating, community > 0 {
                result.append(("stars", Float(community)))
            }

            if let apiRatings {
                for (source, value) in apiRatings {
                    if source == "tomatoes" && criticRating != nil { continue }
                    let normalized = RatingSource(rawValue: source)?.normalize(value) ?? (value / 100.0)
                    result.append((source, normalized))
                }
            }

            if !result.contains(where: { $0.0 == "tomatoes" }),
               let critic = criticRating, critic > 0 {
                result.append(("tomatoes", RatingSource.tomatoes.normalize(Float(critic))))
            }

            self.ratings = result
        }
    }

    func reset() {
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
