import SwiftUI
import Combine

enum ScreensaverContent: Equatable {
    case logo
    case libraryShowcase(item: ServerItem, backdropUrl: String, logoUrl: String?)
    case nowPlaying(item: ServerItem)

    static func == (lhs: ScreensaverContent, rhs: ScreensaverContent) -> Bool {
        switch (lhs, rhs) {
        case (.logo, .logo):
            return true
        case (.libraryShowcase(let a, _, _), .libraryShowcase(let b, _, _)):
            return a.id == b.id
        case (.nowPlaying(let a), .nowPlaying(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

@MainActor
final class ScreensaverViewModel: ObservableObject {

    @Published private(set) var content: ScreensaverContent = .logo

    private let container: AppContainer
    private var showcaseTask: Task<Void, Never>?
    private var observerCancellable: AnyCancellable?

    init(container: AppContainer) {
        self.container = container
    }

    func start() {
        let mode = container.userPreferences[UserPreferences.screensaverMode]
        switch mode {
        case .logo:
            content = .logo
        case .showcase:
            startLibraryShowcase()
        case .nowPlaying:
            startNowPlaying()
        }
    }

    func stop() {
        showcaseTask?.cancel()
        showcaseTask = nil
        observerCancellable?.cancel()
        observerCancellable = nil
        content = .logo
    }

    private func startNowPlaying() {
        if let audio = container.playbackCoordinator.audioManager,
           let item = audio.currentItem {
            content = .nowPlaying(item: item)
            observerCancellable = audio.playbackManager.$queue
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    if let updated = audio.currentItem {
                        self.content = .nowPlaying(item: updated)
                    }
                }
        } else {
            startLibraryShowcase()
        }
    }

    private func startLibraryShowcase() {
        content = .logo
        showcaseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await self.runShowcaseLoop()
        }
    }

    private func runShowcaseLoop() async {
        while !Task.isCancelled {
            let items = await fetchRandomItems()
            if items.isEmpty {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                continue
            }
            for item in items {
                if Task.isCancelled { return }
                guard let showcase = makeShowcase(for: item) else { continue }
                content = showcase
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func fetchRandomItems() async -> [ServerItem] {
        guard let server = container.serverRepository.currentServer.value else { return [] }
        let client = container.serverClientFactory.client(for: server)
        do {
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: [.movie, .series],
                sortBy: [.random],
                limit: 60,
                enableImages: true,
                imageTypeLimit: 1
            ))
            let hasBackdrop = result.items.filter { !($0.backdropImageTags ?? []).isEmpty || !($0.parentBackdropImageTags ?? []).isEmpty }
            return filterByAgeRating(hasBackdrop)
        } catch {
            return []
        }
    }

    private func makeShowcase(for item: ServerItem) -> ScreensaverContent? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        let api = container.serverClientFactory.client(for: server).imageApi

        var backdropUrl: String?
        if let tags = item.backdropImageTags, !tags.isEmpty {
            backdropUrl = api.getItemImageUrl(itemId: item.id, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tags.first)
        } else if let tags = item.parentBackdropImageTags, !tags.isEmpty, let parentId = item.parentBackdropItemId {
            backdropUrl = api.getItemImageUrl(itemId: parentId, imageType: .backdrop, maxWidth: 1920, maxHeight: nil, tag: tags.first)
        }

        guard let url = backdropUrl else { return nil }

        var logoUrl: String?
        if let logoTag = item.imageTags?["Logo"] {
            logoUrl = api.getItemImageUrl(itemId: item.id, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: logoTag)
        } else if let seriesId = item.seriesId {
            logoUrl = api.getItemImageUrl(itemId: seriesId, imageType: .logo, maxWidth: 400, maxHeight: nil, tag: nil)
        }

        return .libraryShowcase(item: item, backdropUrl: url, logoUrl: logoUrl)
    }

    private func filterByAgeRating(_ items: [ServerItem]) -> [ServerItem] {
        let maxAge = container.userPreferences[UserPreferences.screensaverAgeRatingMax]
        guard maxAge >= 0 else { return items }
        let requireRating = container.userPreferences[UserPreferences.screensaverAgeRatingRequired]
        return items.filter { item in
            guard let rating = item.officialRating, !rating.isEmpty else {
                return !requireRating
            }
            guard let age = Self.ratingAgeMap[rating] else {
                return !requireRating
            }
            return age <= maxAge
        }
    }

    private static let ratingAgeMap: [String: Int] = [
        "G": 0, "TV-Y": 0, "TV-G": 0,
        "PG": 10, "TV-Y7": 7, "TV-Y7-FV": 7, "TV-PG": 10,
        "PG-13": 13, "TV-14": 14,
        "R": 17, "TV-MA": 17,
        "NC-17": 18, "NR": 0, "Unrated": 0,
        "U": 0, "12": 12, "12A": 12, "15": 15, "18": 18, "R18": 18,
        "All": 0, "6": 6, "9": 9, "10": 10, "16": 16
    ]
}
