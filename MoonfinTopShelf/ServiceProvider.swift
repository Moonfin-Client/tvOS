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

        let sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = payload.sections.compactMap { section in
            let shape: TVTopShelfSectionedItem.ImageShape = (section.landscape == true) ? .hdtv : .poster

            let items: [TVTopShelfSectionedItem] = section.items.compactMap { cachedItem in
                let item = TVTopShelfSectionedItem(identifier: cachedItem.id)
                item.title = cachedItem.title
                item.imageShape = shape

                if let progress = cachedItem.playbackProgress {
                    item.playbackProgress = max(0, min(1, progress))
                }

                if let imageURL = cachedItem.imageURL, let url = URL(string: imageURL) {
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

            guard !items.isEmpty else { return nil }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }

        guard !sections.isEmpty else { return nil }

        return TVTopShelfSectionedContent(sections: sections)
    }
}
