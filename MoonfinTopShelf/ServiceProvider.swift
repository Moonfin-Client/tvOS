import TVServices

private enum TopShelfShared {
    static let appGroupIdentifier = "group.org.moonfin.app"
    static let cacheFileName = "topshelf_cache.json"

    static var cacheFileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        return container
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(cacheFileName)
    }
}

private struct TopShelfCachePayload: Codable {
    struct Section: Codable {
        let id: String
        let title: String
        let items: [Item]
        let landscape: Bool?
    }

    struct Item: Codable {
        let id: String
        let title: String
        let imageURL: String?
        let contentImageURL: String?
        let displayURL: String
        let playURL: String
        let playbackProgress: Double?
    }

    let sections: [Section]
}

final class ServiceProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        completionHandler(buildContent())
    }

    private func buildContent() -> TVTopShelfContent? {
        guard let fileURL = TopShelfShared.cacheFileURL else { return nil }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        guard let payload = try? JSONDecoder().decode(TopShelfCachePayload.self, from: data) else { return nil }

        let carouselItems: [TVTopShelfCarouselItem] = payload.sections.flatMap { section in
            section.items.compactMap { cachedItem -> TVTopShelfCarouselItem? in
                let item = TVTopShelfCarouselItem(identifier: cachedItem.id)
                item.title = cachedItem.title
                item.contextTitle = section.title

                let contentURL = cachedItem.contentImageURL ?? cachedItem.imageURL
                if let urlString = contentURL, let url = URL(string: urlString) {
                    item.setImageURL(url, for: .screenScale1x)
                    item.setImageURL(url, for: .screenScale2x)
                }

                if let playURL = URL(string: cachedItem.playURL) {
                    item.playAction = TVTopShelfAction(url: playURL)
                }

                if let displayURL = URL(string: cachedItem.displayURL) {
                    item.displayAction = TVTopShelfAction(url: displayURL)
                }

                return item
            }
        }

        guard !carouselItems.isEmpty else { return nil }

        return TVTopShelfCarouselContent(style: .actions, items: carouselItems)
    }
}
