import SwiftUI
import Combine

@MainActor
final class MediaBarViewModel: ObservableObject {
    @Published private(set) var state: MediaBarState = .loading
    @Published private(set) var currentIndex: Int = 0
    private(set) var isFocused: Bool = false
    private var isPaused: Bool = false

    private let container: AppContainer
    private var autoAdvanceTimer: AnyCancellable?
    private var loadTask: Task<Void, Never>?

    static let autoAdvanceInterval: TimeInterval = 7
    static let fetchFields: [ItemField] = [.overview, .genres, .primaryImageAspectRatio]

    var currentItem: MediaBarSlideItem? {
        guard case .ready(let items) = state, !items.isEmpty else { return nil }
        return items[currentIndex]
    }

    var isEnabled: Bool {
        container.userPreferences[UserPreferences.mediaBarEnabled]
    }

    init(container: AppContainer) {
        self.container = container
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    func load(userViews: [ServerItem] = []) {
        guard isEnabled else {
            state = .disabled
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            state = .loading
            do {
                let items = try await fetchItems(userViews: userViews)
                guard !Task.isCancelled else { return }
                if items.isEmpty {
                    state = .disabled
                } else {
                    state = .ready(items)
                    currentIndex = 0
                    startAutoAdvance()
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(error.localizedDescription)
            }
        }
    }

    func goToNext() {
        guard case .ready(let items) = state, !items.isEmpty else { return }
        currentIndex = (currentIndex + 1) % items.count
        restartAutoAdvance()
    }

    func goToPrevious() {
        guard case .ready(let items) = state, !items.isEmpty else { return }
        currentIndex = (currentIndex - 1 + items.count) % items.count
        restartAutoAdvance()
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused
        isPaused = focused
        if focused {
            stopAutoAdvance()
        } else {
            startAutoAdvance()
        }
    }

    func cleanup() {
        loadTask?.cancel()
        stopAutoAdvance()
    }

    private func fetchItems(userViews: [ServerItem]) async throws -> [MediaBarSlideItem] {
        guard let client else { return [] }

        let prefs = container.userPreferences
        let contentType = prefs[UserPreferences.mediaBarContentType]
        let maxItems = prefs[UserPreferences.mediaBarItemCount].count

        let targetLibraries = userViews.filter { view in
            guard let ct = view.collectionType?.lowercased() else { return false }
            return contentType.collectionTypes.contains(ct)
        }

        var allItems: [ServerItem] = []

        let fetchLimit = maxItems * 3

        if targetLibraries.isEmpty {
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                recursive: true,
                includeItemTypes: contentType.itemTypes,
                excludeItemTypes: [.boxSet],
                sortBy: [.random],
                fields: Self.fetchFields,
                limit: fetchLimit,
                enableImages: true,
                imageTypeLimit: 1
            ))
            allItems = result.items
        } else {
            for library in targetLibraries {
                guard !Task.isCancelled else { return [] }
                do {
                    let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                        parentId: library.id,
                        recursive: true,
                        includeItemTypes: contentType.itemTypes,
                        excludeItemTypes: [.boxSet],
                        sortBy: [.random],
                        fields: Self.fetchFields,
                        limit: fetchLimit,
                        enableImages: true,
                        imageTypeLimit: 1
                    ))
                    allItems.append(contentsOf: result.items)
                } catch {
                    continue
                }
            }
        }

        let filtered = allItems.filter { item in
            item.backdropImageTags?.isEmpty == false
                || item.parentBackdropImageTags?.isEmpty == false
        }

        let shuffled = filtered.shuffled()
        let capped = Array(shuffled.prefix(maxItems))

        return capped.map { mapToSlideItem($0, client: client) }
    }

    private func mapToSlideItem(_ item: ServerItem, client: MediaServerClient) -> MediaBarSlideItem {
        let imageApi = client.imageApi

        var backdropUrl: String?
        if let tags = item.backdropImageTags, let tag = tags.first {
            backdropUrl = imageApi.getItemImageUrl(
                itemId: item.id, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: tag
            )
        } else if let parentTags = item.parentBackdropImageTags,
                  let parentId = item.parentBackdropItemId,
                  let tag = parentTags.first {
            backdropUrl = imageApi.getItemImageUrl(
                itemId: parentId, imageType: .backdrop,
                maxWidth: 1920, maxHeight: nil, tag: tag
            )
        }

        var logoUrl: String?
        if let logoTag = item.imageTags?["Logo"] {
            logoUrl = imageApi.getItemImageUrl(
                itemId: item.id, imageType: .logo,
                maxWidth: 400, maxHeight: nil, tag: logoTag
            )
        }

        var runtime: String?
        if let ticks = item.runTimeTicks, ticks > 0 {
            runtime = RuntimeFormatter.format(ticks: ticks)
        }

        return MediaBarSlideItem(
            id: item.id,
            serverId: item.serverId,
            title: item.name,
            overview: item.overview,
            backdropUrl: backdropUrl,
            logoUrl: logoUrl,
            year: item.productionYear,
            genres: item.genres ?? [],
            runtime: runtime,
            officialRating: item.officialRating,
            communityRating: item.communityRating,
            criticRating: item.criticRating,
            itemType: item.type
        )
    }

    private func startAutoAdvance() {
        guard !isPaused else { return }
        guard case .ready(let items) = state, items.count > 1 else { return }
        stopAutoAdvance()
        autoAdvanceTimer = Timer.publish(every: Self.autoAdvanceInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.goToNext()
            }
    }

    private func stopAutoAdvance() {
        autoAdvanceTimer?.cancel()
        autoAdvanceTimer = nil
    }

    private func restartAutoAdvance() {
        stopAutoAdvance()
        startAutoAdvance()
    }
}
