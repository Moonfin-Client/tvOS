import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var selectedItemState: SelectedItemState = .empty

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private var selectionDebounceTask: Task<Void, Never>?
    private var backdropDebounceTask: Task<Void, Never>?

    private static let selectionDebounceMs: UInt64 = 150_000_000
    private static let backdropDebounceMs: UInt64 = 200_000_000

    init(container: AppContainer) {
        self.container = container
    }

    var imageApi: ServerImageApi? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server).imageApi
    }

    func onItemFocused(_ item: ServerItem?) {
        guard let item else {
            selectionDebounceTask?.cancel()
            backdropDebounceTask?.cancel()
            selectedItemState = .empty
            backgroundService.clearBackground()
            return
        }

        selectionDebounceTask?.cancel()
        selectionDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.selectionDebounceMs)
            guard !Task.isCancelled else { return }
            selectedItemState = buildSelectedState(for: item)
        }

        backdropDebounceTask?.cancel()
        backdropDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.backdropDebounceMs)
            guard !Task.isCancelled else { return }
            let urls = backdropUrls(for: item)
            backgroundService.setBackground(urls: urls)
        }
    }

    private func buildSelectedState(for item: ServerItem) -> SelectedItemState {
        let logoUrl = logoImageUrl(for: item)
        let backdropUrl = backdropUrls(for: item).first

        return SelectedItemState(
            title: item.name,
            summary: item.overview ?? "",
            item: item,
            logoUrl: logoUrl,
            backdropUrl: backdropUrl
        )
    }

    private func backdropUrls(for item: ServerItem) -> [String] {
        guard let imageApi else { return [] }
        var urls: [String] = []

        if let tags = item.backdropImageTags, !tags.isEmpty {
            for tag in tags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: item.id,
                    imageType: .backdrop,
                    maxWidth: 1920,
                    maxHeight: nil,
                    tag: tag
                ))
            }
        }

        if urls.isEmpty, let parentTags = item.parentBackdropImageTags,
           let parentId = item.parentBackdropItemId, !parentTags.isEmpty {
            for tag in parentTags {
                urls.append(imageApi.getItemImageUrl(
                    itemId: parentId,
                    imageType: .backdrop,
                    maxWidth: 1920,
                    maxHeight: nil,
                    tag: tag
                ))
            }
        }

        if urls.isEmpty, let seriesId = item.seriesId {
            urls.append(imageApi.getItemImageUrl(
                itemId: seriesId,
                imageType: .backdrop,
                maxWidth: 1920,
                maxHeight: nil,
                tag: nil
            ))
        }

        return urls
    }

    private func logoImageUrl(for item: ServerItem) -> String? {
        guard let imageApi else { return nil }
        if let logoTag = item.imageTags?["Logo"] {
            return imageApi.getItemImageUrl(
                itemId: item.id,
                imageType: .logo,
                maxWidth: 400,
                maxHeight: nil,
                tag: logoTag
            )
        }
        if let seriesId = item.seriesId {
            return imageApi.getItemImageUrl(
                itemId: seriesId,
                imageType: .logo,
                maxWidth: 400,
                maxHeight: nil,
                tag: nil
            )
        }
        return nil
    }
}
