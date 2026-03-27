import Foundation
import Combine

@MainActor
final class ParentalControlsRepository: ObservableObject {
    @Published private(set) var blockedRatings: Set<String> = []

    private let sessionRepository: SessionRepositoryProtocol
    private let multiServerRepository: MultiServerRepositoryProtocol

    private var cachedAvailableRatings: [String]?
    private var currentLoadedUserId: UUID?
    private var cancellables = Set<AnyCancellable>()

    private static let prefsPrefix = "parental_controls_"
    private static let blockedKey = "blocked_ratings"
    private static let cachedRatingsKey = "cached_ratings"
    private static let cacheTimestampKey = "cache_timestamp"
    private static let cacheVersionKey = "cache_version"
    private static let cacheVersion = 2
    private static let cacheDuration: TimeInterval = 24 * 60 * 60

    init(
        sessionRepository: SessionRepositoryProtocol,
        multiServerRepository: MultiServerRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.multiServerRepository = multiServerRepository

        sessionRepository.currentSession
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                guard let self, session.userId != self.currentLoadedUserId else { return }
                self.currentLoadedUserId = session.userId
                self.loadBlockedRatings()
            }
            .store(in: &cancellables)

        loadBlockedRatings()
    }

    var isEnabled: Bool { !getBlockedRatingsResolved().isEmpty }

    func getBlockedRatings() -> Set<String> { getBlockedRatingsResolved() }

    func setBlockedRatings(_ ratings: Set<String>) {
        guard let userId = currentUserId else { return }
        let defaults = defaultsForUser(userId)
        if let data = try? JSONEncoder().encode(ratings) {
            defaults.set(data, forKey: Self.blockedKey)
        }
        blockedRatings = ratings
    }

    func reloadBlockedRatings() {
        loadBlockedRatings()
    }

    func shouldFilterItem(_ item: ServerItem) -> Bool {
        isRatingBlocked(item.officialRating)
    }

    func isRatingBlocked(_ rating: String?) -> Bool {
        guard let rating, !rating.isEmpty else { return false }
        return getBlockedRatingsResolved().contains(rating)
    }

    func filterItems(_ items: [ServerItem]) -> [ServerItem] {
        let blocked = getBlockedRatingsResolved()
        guard !blocked.isEmpty else { return items }
        return items.filter { item in
            guard let rating = item.officialRating, !rating.isEmpty else { return true }
            return !blocked.contains(rating)
        }
    }

    func getAvailableRatings() async -> [String] {
        if let cached = cachedAvailableRatings, !cached.isEmpty { return cached }

        if let userId = currentUserId,
           let diskCached = loadCachedRatings(userId: userId),
           !diskCached.isEmpty {
            cachedAvailableRatings = diskCached
            return diskCached
        }

        let sessions = await multiServerRepository.getLoggedInServers()
        var allRatings = Set<String>()

        for session in sessions {
            let ratings = await fetchRatingsFromServer(session.client)
            allRatings.formUnion(ratings)
        }

        let sorted = allRatings.sorted(by: RatingComparator.compare)

        if let userId = currentUserId, !sorted.isEmpty {
            saveCachedRatings(userId: userId, ratings: sorted)
        }
        cachedAvailableRatings = sorted.isEmpty ? nil : sorted
        return sorted
    }

    func clearCache() {
        cachedAvailableRatings = nil
        guard let userId = currentUserId else { return }
        let defaults = defaultsForUser(userId)
        defaults.removeObject(forKey: Self.cachedRatingsKey)
        defaults.removeObject(forKey: Self.cacheTimestampKey)
        defaults.removeObject(forKey: Self.cacheVersionKey)
    }

    private var currentUserId: UUID? {
        sessionRepository.currentSession.value?.userId
    }

    private func defaultsForUser(_ userId: UUID) -> UserDefaults {
        UserDefaults(suiteName: "\(Self.prefsPrefix)\(userId.uuidString)") ?? .standard
    }

    private func loadBlockedRatings() {
        guard let userId = currentUserId else { return }
        let defaults = defaultsForUser(userId)
        guard let data = defaults.data(forKey: Self.blockedKey),
              let ratings = try? JSONDecoder().decode(Set<String>.self, from: data)
        else {
            blockedRatings = []
            return
        }
        blockedRatings = ratings
    }

    private func getBlockedRatingsResolved() -> Set<String> {
        if !blockedRatings.isEmpty { return blockedRatings }
        guard let userId = currentUserId else { return [] }
        let defaults = defaultsForUser(userId)
        guard let data = defaults.data(forKey: Self.blockedKey),
              let ratings = try? JSONDecoder().decode(Set<String>.self, from: data),
              !ratings.isEmpty
        else { return [] }
        blockedRatings = ratings
        currentLoadedUserId = userId
        return ratings
    }

    private func loadCachedRatings(userId: UUID) -> [String]? {
        let defaults = defaultsForUser(userId)
        let version = defaults.integer(forKey: Self.cacheVersionKey)
        guard version == Self.cacheVersion else { return nil }
        let timestamp = defaults.double(forKey: Self.cacheTimestampKey)
        guard timestamp > 0 else { return nil }
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < Self.cacheDuration else { return nil }
        guard let data = defaults.data(forKey: Self.cachedRatingsKey),
              let ratings = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return ratings
    }

    private func saveCachedRatings(userId: UUID, ratings: [String]) {
        let defaults = defaultsForUser(userId)
        if let data = try? JSONEncoder().encode(ratings) {
            defaults.set(data, forKey: Self.cachedRatingsKey)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.cacheTimestampKey)
            defaults.set(Self.cacheVersion, forKey: Self.cacheVersionKey)
        }
    }

    private func fetchRatingsFromServer(_ client: MediaServerClient) async -> [String] {
        do {
            let globalRatings = try await fetchRatingsForView(client: client, parentId: nil)
            if !globalRatings.isEmpty {
                return Array(globalRatings)
            }

            guard let userId = client.userId else { return [] }
            let views = try await client.userViewsApi.getUserViews(userId: userId)
            var ratings = Set<String>()
            for view in views {
                do {
                    let viewRatings = try await fetchRatingsForView(client: client, parentId: view.id)
                    ratings.formUnion(viewRatings)
                } catch {
                    continue
                }
            }

            return Array(ratings)
        } catch {
            return []
        }
    }

    private func fetchRatingsForView(client: MediaServerClient, parentId: String?) async throws -> Set<String> {
        let pageSize = 500
        var startIndex = 0
        var safetyPages = 0
        let maxPages = 40
        var ratings = Set<String>()

        while safetyPages < maxPages {
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: [.movie, .series, .season, .episode, .video, .musicVideo, .book, .audio, .boxSet],
                fields: [.officialRating],
                limit: pageSize,
                startIndex: startIndex,
                enableImages: false,
                enableTotalRecordCount: true
            ))

            for item in result.items {
                let normalized = item.officialRating?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                if let normalized, !normalized.isEmpty {
                    ratings.insert(normalized)
                }
            }

            let fetchedCount = result.items.count
            startIndex += fetchedCount
            safetyPages += 1

            if fetchedCount == 0 || fetchedCount < pageSize {
                break
            }
            if result.totalRecordCount > 0 && startIndex >= result.totalRecordCount {
                break
            }
        }

        return ratings
    }
}

enum RatingComparator {
    private static let ratingOrder: [String] = [
        "G", "PG", "PG-13", "R", "NC-17", "NR", "Unrated",
        "TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "TV-PG", "TV-14", "TV-MA",
        "U", "12", "12A", "15", "18", "R18",
        "All", "6", "9", "16"
    ]

    static func compare(_ a: String, _ b: String) -> Bool {
        let indexA = ratingOrder.firstIndex(of: a)
        let indexB = ratingOrder.firstIndex(of: b)

        switch (indexA, indexB) {
        case let (ia?, ib?): return ia < ib
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}
