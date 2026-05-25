import Foundation

@MainActor
final class MdbListRepository {
    private let resolveClient: () -> HttpClient?
    private var ratingsCache: [String: [(String, Float)]] = [:]
    private var pendingRequests: [String: Task<[(String, Float)]?, Never>] = [:]

    init(resolveClient: @escaping () -> HttpClient?) {
        self.resolveClient = resolveClient
    }

    func getRatings(item: ServerItem) async -> [(String, Float)]? {
        guard let tmdbId = item.providerIds?["Tmdb"] else { return nil }
        return await getRatings(tmdbId: tmdbId, type: item.type)
    }

    func getRatings(tmdbId: String, type: ItemType) async -> [(String, Float)]? {
        let typeStr: String
        switch type {
        case .movie: typeStr = "movie"
        case .series, .episode, .season: typeStr = "show"
        default: typeStr = "movie"
        }

        let cacheKey = "\(typeStr):\(tmdbId)"

        if let cached = ratingsCache[cacheKey] {
            return cached
        }

        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<[(String, Float)]?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchRatings(type: typeStr, tmdbId: tmdbId, cacheKey: cacheKey)
        }
        pendingRequests[cacheKey] = task
        let result = await task.value
        pendingRequests.removeValue(forKey: cacheKey)
        return result
    }

    private func fetchRatings(type: String, tmdbId: String, cacheKey: String) async -> [(String, Float)]? {
        guard let httpClient = resolveClient(), httpClient.isUsable else { return nil }

        do {
            let response: MdbListResponse = try await httpClient.request(
                "/Moonfin/MdbList/Ratings",
                queryItems: [
                    URLQueryItem(name: "type", value: type),
                    URLQueryItem(name: "tmdbId", value: tmdbId)
                ]
            )

            guard response.success, response.error == nil else { return nil }

            var ratingsList: [(String, Float)] = []
            var seenSources = Set<String>()
            for rating in response.ratings ?? [] {
                guard let rawSource = rating.source else { continue }
                let source = RatingSource.canonicalSourceRawValue(rawSource)
                guard !source.isEmpty else { continue }
                let value: Float?
                if source == "metacriticuser" {
                    value = (rating.score ?? rating.value).flatMap { $0 > 0 ? $0 : nil }
                } else {
                    value = (rating.value ?? rating.score).flatMap { $0 > 0 ? $0 : nil }
                }
                if let value, seenSources.insert(source).inserted {
                    ratingsList.append((source, value))
                }
            }

            ratingsCache[cacheKey] = ratingsList
            return ratingsList
        } catch {
            return nil
        }
    }

    func clearCache() {
        ratingsCache.removeAll()
        for (_, task) in pendingRequests { task.cancel() }
        pendingRequests.removeAll()
    }
}
