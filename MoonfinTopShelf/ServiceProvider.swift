import TVServices

private enum TopShelfShared {
    static let appGroupIdentifier = "group.com.moonfin.tv"
    static let defaultsKey = "topshelf.cache.v1"
}

private struct TopShelfCachePayload: Codable {
    struct Section: Codable {
        let id: String
        let title: String
        let items: [Item]
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
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard
            let defaults = UserDefaults(suiteName: TopShelfShared.appGroupIdentifier),
            let data = defaults.data(forKey: TopShelfShared.defaultsKey)
        else {
            completionHandler(nil)
            return
        }

        guard let payload = try? JSONDecoder().decode(TopShelfCachePayload.self, from: data) else {
            completionHandler(nil)
            return
        }

        let sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = payload.sections.compactMap { section in
            let items: [TVTopShelfSectionedItem] = section.items.compactMap { cachedItem in
                let item = TVTopShelfSectionedItem(identifier: cachedItem.id)
                item.title = cachedItem.title
                item.imageShape = .poster

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

        guard !sections.isEmpty else {
            completionHandler(nil)
            return
        }

        completionHandler(TVTopShelfSectionedContent(sections: sections))
    }
}
