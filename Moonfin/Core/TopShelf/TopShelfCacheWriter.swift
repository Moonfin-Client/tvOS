import Foundation
#if canImport(TVServices)
import TVServices
#endif

enum TopShelfShared {
    static let appGroupIdentifier = "group.org.moonfin.app"
    static let cacheFileName = "topshelf_cache.json"

    static var cacheFileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let dir = container.appendingPathComponent("Library/Caches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheFileName)
    }
}

struct TopShelfCachePayload: Codable {
    struct Section: Codable {
        let id: String
        let title: String
        let items: [Item]
        let landscape: Bool
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

    func write(
        rows: [HomeRow],
        imageURL: (ServerItem, HomeRowType) -> String?,
        isLandscape: (HomeRowType) -> Bool
    ) {
        var sections: [TopShelfCachePayload.Section] = []

        if let continueWatchingRow = rows.first(where: { $0.rowType == .continueWatching }) {
            let landscape = isLandscape(.continueWatching)
            let items = continueWatchingRow.items
                .prefix(Self.maxItemsPerSection)
                .compactMap { makeItem(from: $0, imageURL: imageURL($0, .continueWatching)) }
            if !items.isEmpty {
                sections.append(
                    TopShelfCachePayload.Section(
                        id: "continue_watching",
                        title: continueWatchingRow.title,
                        items: items,
                        landscape: landscape
                    )
                )
            }
        }

        for latestRow in rows.filter({ if case .latestMedia = $0.rowType { return true }; return false }) {
            let landscape = isLandscape(latestRow.rowType)
            let items = latestRow.items
                .prefix(Self.maxItemsPerSection)
                .compactMap { makeItem(from: $0, imageURL: imageURL($0, latestRow.rowType)) }
            if !items.isEmpty {
                sections.append(
                    TopShelfCachePayload.Section(
                        id: "latest_\(latestRow.id)",
                        title: latestRow.title,
                        items: items,
                        landscape: landscape
                    )
                )
            }
        }

        guard let fileURL = TopShelfShared.cacheFileURL else { return }

        if sections.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            notifyTopShelfChanged()
            return
        }

        let payload = TopShelfCachePayload(sections: sections)
        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(payload)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        notifyTopShelfChanged()
    }

    private func notifyTopShelfChanged() {
#if canImport(TVServices)
        DispatchQueue.main.async {
            TVTopShelfContentProvider.topShelfContentDidChange()
            NotificationCenter.default.post(
                name: .TVTopShelfItemsDidChange,
                object: nil
            )
        }
#endif
    }

    private func makeItem(from item: ServerItem, imageURL: String?) -> TopShelfCachePayload.Item? {
        guard let link = deepLink(for: item) else { return nil }
        let linkString = link.absoluteString
        return TopShelfCachePayload.Item(
            id: item.id,
            title: item.name,
            imageURL: imageURL,
            displayURL: linkString,
            playURL: linkString,
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