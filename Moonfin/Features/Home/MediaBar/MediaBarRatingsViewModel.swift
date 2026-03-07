import SwiftUI

@MainActor
final class MediaBarRatingsViewModel: ObservableObject {
    @Published private(set) var ratings: [(String, Float)] = []
    @Published private(set) var isLoading = false

    private let mdbListRepository: MdbListRepository
    private let userPreferences: UserPreferences
    private var currentItemId: String?
    private var loadTask: Task<Void, Never>?

    var enableAdditionalRatings: Bool {
        userPreferences[UserPreferences.enableAdditionalRatings]
    }

    init(mdbListRepository: MdbListRepository, userPreferences: UserPreferences) {
        self.mdbListRepository = mdbListRepository
        self.userPreferences = userPreferences
    }

    func loadRatings(for item: MediaBarSlideItem) {
        guard currentItemId != item.id else { return }
        currentItemId = item.id

        guard enableAdditionalRatings, let tmdbId = item.tmdbId else {
            ratings = buildFallbackRatings(item: item)
            return
        }

        isLoading = true
        loadTask?.cancel()
        let itemId = item.id
        loadTask = Task {
            let apiRatings = await mdbListRepository.getRatings(
                tmdbId: tmdbId,
                type: item.itemType
            )
            guard !Task.isCancelled, currentItemId == itemId else { return }

            var result: [(String, Float)] = []

            if let community = item.communityRating, community > 0 {
                result.append(("stars", Float(community)))
            }

            if let apiRatings {
                for (source, value) in apiRatings {
                    if source == "tomatoes" && item.criticRating != nil { continue }
                    result.append((source, value))
                }
            }

            if !result.contains(where: { $0.0 == "tomatoes" }) {
                if let critic = item.criticRating, critic > 0 {
                    result.append(("tomatoes", Float(critic)))
                }
            }

            self.ratings = result
            self.isLoading = false
        }
    }

    func reset() {
        currentItemId = nil
        ratings = []
        isLoading = false
    }

    private func buildFallbackRatings(item: MediaBarSlideItem) -> [(String, Float)] {
        var result: [(String, Float)] = []
        if let community = item.communityRating, community > 0 {
            result.append(("stars", Float(community)))
        }
        if let critic = item.criticRating, critic > 0 {
            result.append(("tomatoes", Float(critic)))
        }
        return result
    }
}
