import Foundation
#if canImport(TVServices)
import TVServices
#endif

enum TopShelfShared {
    static let appGroupIdentifier = "group.org.moonfin.app"
    static let defaultsKey = "topshelf.cache.v1"
}

struct TopShelfCachePayload: Codable {
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

struct TopShelfCacheWriter {
    private static let maxItemsPerSection = 12

    func write(rows: [HomeRow], imageURL: (ServerItem) -> String?) {
        var sections: [TopShelfCachePayload.Section] = []

        if let continueWatchingRow = rows.first(where: { $0.rowType == .continueWatching }) {
            let items = continueWatchingRow.items
                .prefix(Self.maxItemsPerSection)
                .compactMap { makeItem(from: $0, imageURL: imageURL($0)) }
            if !items.isEmpty {
                sections.append(
                    TopShelfCachePayload.Section(
                        id: "continue_watching",
                        title: continueWatchingRow.title,
                        items: items
                    )
                )
            }
        }

        if let latestRow = rows.first(where: {
            if case .latestMedia = $0.rowType { return true }
            return false
        }) {
            let items = latestRow.items
                .prefix(Self.maxItemsPerSection)
                .compactMap { makeItem(from: $0, imageURL: imageURL($0)) }
            if !items.isEmpty {
                sections.append(
                    TopShelfCachePayload.Section(
                        id: "latest_media",
                        title: latestRow.title,
                        items: items
                    )
                )
            }
        }

        guard let defaults = UserDefaults(suiteName: TopShelfShared.appGroupIdentifier) else { return }

        if sections.isEmpty {
            defaults.removeObject(forKey: TopShelfShared.defaultsKey)
            notifyTopShelfChanged()
            return
        }

        let payload = TopShelfCachePayload(sections: sections)
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(payload) else { return }
        defaults.set(encoded, forKey: TopShelfShared.defaultsKey)
        notifyTopShelfChanged()
    }

    private func notifyTopShelfChanged() {
#if canImport(TVServices)
        TVTopShelfContentProvider.topShelfContentDidChange()
#endif
    }

    private func makeItem(from item: ServerItem, imageURL: String?) -> TopShelfCachePayload.Item? {
        guard let displayURL = deepLink(for: item), let playURL = deepLink(for: item) else {
            return nil
        }

        return TopShelfCachePayload.Item(
            id: item.id,
            title: item.name,
            imageURL: imageURL,
            displayURL: displayURL.absoluteString,
            playURL: playURL.absoluteString,
            playbackProgress: playbackProgress(for: item)
        )
    }

    private func deepLink(for item: ServerItem) -> URL? {
        var components = URLComponents()
        components.scheme = "moonfin"
        components.host = "item"

        var queryItems = [URLQueryItem(name: "id", value: item.id)]
        if let serverId = item.effectiveServerId, !serverId.isEmpty {
            queryItems.append(URLQueryItem(name: "serverId", value: serverId))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func playbackProgress(for item: ServerItem) -> Double? {
        if let played = item.userData?.playedPercentage {
            return max(0, min(1, played / 100.0))
        }

        guard
            let ticks = item.userData?.playbackPositionTicks,
            ticks > 0,
            let runtime = item.runTimeTicks,
            runtime > 0
        else {
            return nil
        }

        return max(0, min(1, Double(ticks) / Double(runtime)))
    }
}