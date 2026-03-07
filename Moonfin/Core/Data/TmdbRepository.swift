import Foundation

@MainActor
final class TmdbRepository {
    private let resolveClient: () -> HttpClient?
    private var episodeCache: [String: Float] = [:]
    private var seasonCache: [String: [Int: Float]] = [:]
    private var seriesTmdbIdCache: [String: String?] = [:]
    private var pendingEpisodeRequests: [String: Task<Float?, Never>] = [:]
    private var pendingSeasonRequests: [String: Task<[Int: Float]?, Never>] = [:]

    init(resolveClient: @escaping () -> HttpClient?) {
        self.resolveClient = resolveClient
    }

    func getEpisodeRating(item: ServerItem) async -> Float? {
        guard item.type == .episode else { return nil }
        guard let seriesId = item.seriesId else { return nil }

        let tmdbId = await getSeriesTmdbId(seriesId: seriesId)
        guard let tmdbId else { return nil }

        guard let season = item.parentIndexNumber, let episode = item.indexNumber else { return nil }

        let cacheKey = "\(tmdbId):\(season):\(episode)"

        if let cached = episodeCache[cacheKey] {
            return cached
        }

        if let pending = pendingEpisodeRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<Float?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchEpisodeRating(tmdbId: tmdbId, season: season, episode: episode, cacheKey: cacheKey)
        }
        pendingEpisodeRequests[cacheKey] = task
        let result = await task.value
        pendingEpisodeRequests.removeValue(forKey: cacheKey)
        return result
    }

    func getSeasonRatings(seriesTmdbId: String, seasonNumber: Int) async -> [Int: Float]? {
        let cacheKey = "\(seriesTmdbId):\(seasonNumber)"

        if let cached = seasonCache[cacheKey] {
            return cached
        }

        if let pending = pendingSeasonRequests[cacheKey] {
            return await pending.value
        }

        let task = Task<[Int: Float]?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.fetchSeasonRatings(tmdbId: seriesTmdbId, season: seasonNumber, cacheKey: cacheKey)
        }
        pendingSeasonRequests[cacheKey] = task
        let result = await task.value
        pendingSeasonRequests.removeValue(forKey: cacheKey)
        return result
    }

    private func fetchEpisodeRating(tmdbId: String, season: Int, episode: Int, cacheKey: String) async -> Float? {
        guard let httpClient = resolveClient(), httpClient.isUsable else { return nil }

        do {
            let response: TmdbEpisodeResponse = try await httpClient.request(
                "/Moonfin/Tmdb/EpisodeRating",
                queryItems: [
                    URLQueryItem(name: "tmdbId", value: tmdbId),
                    URLQueryItem(name: "season", value: String(season)),
                    URLQueryItem(name: "episode", value: String(episode))
                ]
            )

            guard response.success, response.error == nil else { return nil }

            if let rating = response.voteAverage, rating > 0 {
                episodeCache[cacheKey] = rating
                return rating
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchSeasonRatings(tmdbId: String, season: Int, cacheKey: String) async -> [Int: Float]? {
        guard let httpClient = resolveClient(), httpClient.isUsable else { return nil }

        do {
            let response: TmdbSeasonResponse = try await httpClient.request(
                "/Moonfin/Tmdb/SeasonRatings",
                queryItems: [
                    URLQueryItem(name: "tmdbId", value: tmdbId),
                    URLQueryItem(name: "season", value: String(season))
                ]
            )

            guard response.success, response.error == nil else { return nil }

            var ratingsMap: [Int: Float] = [:]
            for ep in response.episodes ?? [] {
                if let epNum = ep.episodeNumber, let rating = ep.voteAverage, rating > 0 {
                    ratingsMap[epNum] = rating
                    episodeCache["\(tmdbId):\(season):\(epNum)"] = rating
                }
            }

            if !ratingsMap.isEmpty {
                seasonCache[cacheKey] = ratingsMap
            }
            return ratingsMap
        } catch {
            return nil
        }
    }

    private func getSeriesTmdbId(seriesId: String) async -> String? {
        if let cached = seriesTmdbIdCache[seriesId] {
            return cached
        }

        guard let httpClient = resolveClient(), httpClient.isUsable else { return nil }
        guard let userId = httpClient.userId else { return nil }

        do {
            let item: ServerItem = try await httpClient.request(
                "/Users/\(userId)/Items/\(seriesId)",
                queryItems: [
                    URLQueryItem(name: "Fields", value: "ProviderIds")
                ]
            )
            let tmdbId = item.providerIds?["Tmdb"]
            seriesTmdbIdCache[seriesId] = tmdbId
            return tmdbId
        } catch {
            return nil
        }
    }

    func clearCache() {
        episodeCache.removeAll()
        seasonCache.removeAll()
        seriesTmdbIdCache.removeAll()
        for (_, task) in pendingEpisodeRequests { task.cancel() }
        pendingEpisodeRequests.removeAll()
        for (_, task) in pendingSeasonRequests { task.cancel() }
        pendingSeasonRequests.removeAll()
    }
}
