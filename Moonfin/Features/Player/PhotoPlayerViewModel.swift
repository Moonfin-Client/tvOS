import SwiftUI

@MainActor
final class PhotoPlayerViewModel: ObservableObject {
    @Published var photos: [ServerItem] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var overlayVisible: Bool = true
    @Published var isLoading: Bool = true

    private let container: AppContainer
    private let initialItemId: String
    private let autoPlay: Bool
    private let sortByParam: String?
    private let sortOrderParam: String?

    private var hideTask: Task<Void, Never>?
    private var slideshowTask: Task<Void, Never>?
    private let overlayTimeout: TimeInterval = 5

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private var slideshowInterval: SlideshowInterval {
        container.userPreferences[UserPreferences.photoSlideshowInterval]
    }

    var currentPhoto: ServerItem? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var currentImageUrl: String? {
        guard let photo = currentPhoto, let client else { return nil }
        let tag = photo.imageTags?["Primary"]
        return client.imageApi.getItemImageUrl(
            itemId: photo.id,
            imageType: .primary,
            maxWidth: 3840,
            maxHeight: 2160,
            tag: tag
        )
    }

    var positionText: String {
        guard !photos.isEmpty else { return "" }
        return "\(currentIndex + 1) / \(photos.count)"
    }

    var photoTitle: String {
        currentPhoto?.name ?? ""
    }

    init(container: AppContainer, itemId: String, autoPlay: Bool, sortBy: String?, sortOrder: String?) {
        self.container = container
        self.initialItemId = itemId
        self.autoPlay = autoPlay
        self.sortByParam = sortBy
        self.sortOrderParam = sortOrder
    }

    func load() async {
        guard let client else { return }
        isLoading = true

        do {
            let item = try await client.userLibraryApi.getItem(itemId: initialItemId)
            let parentId = item.parentId ?? ""
            let sortBy: [ItemSortBy] = {
                if let raw = sortByParam, let val = ItemSortBy(rawValue: raw) { return [val] }
                return [.sortName]
            }()
            let sortOrder: SortOrder = {
                if let raw = sortOrderParam, let val = SortOrder(rawValue: raw) { return val }
                return .ascending
            }()

            let request = GetItemsRequest(
                parentId: parentId,
                includeItemTypes: [.photo],
                sortBy: sortBy,
                sortOrder: sortOrder,
                enableImages: true
            )
            let result = try await client.itemsApi.getItems(request: request)
            photos = result.items

            if let idx = photos.firstIndex(where: { $0.id == initialItemId }) {
                currentIndex = idx
            }

            isLoading = false

            if autoPlay {
                startSlideshow()
            } else {
                resetHideTimer()
            }
        } catch {
            isLoading = false
        }
    }

    func goToNext() {
        guard !photos.isEmpty else { return }
        currentIndex = (currentIndex + 1) % photos.count
        if overlayVisible { resetHideTimer() }
    }

    func goToPrevious() {
        guard !photos.isEmpty else { return }
        currentIndex = (currentIndex - 1 + photos.count) % photos.count
        if overlayVisible { resetHideTimer() }
    }

    func togglePlayPause() {
        if isPlaying {
            pauseSlideshow()
        } else {
            startSlideshow()
        }
        showOverlay()
    }

    func showOverlay() {
        overlayVisible = true
        resetHideTimer()
    }

    func cleanup() {
        slideshowTask?.cancel()
        hideTask?.cancel()
    }

    private func startSlideshow() {
        isPlaying = true
        slideshowTask?.cancel()
        slideshowTask = Task {
            while !Task.isCancelled {
                let interval = slideshowInterval.seconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                goToNext()
            }
        }
    }

    private func pauseSlideshow() {
        isPlaying = false
        slideshowTask?.cancel()
        slideshowTask = nil
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(overlayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }
}
