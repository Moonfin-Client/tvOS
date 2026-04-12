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
        let contentImageURL: String?
        let displayURL: String
        let playURL: String
        let playbackProgress: Double?
    }

    let sections: [Section]
}

struct TopShelfCacheWriter {
    private static let maxItems = 15

    func write(
        rows: [HomeRow],
        imageURL: (ServerItem, HomeRowType) -> String?,
        contentImageURL: (ServerItem) -> String?
    ) {
        let latestRows = rows.filter { if case .latestMedia = $0.rowType { return true }; return false }

        var allItems: [TopShelfCachePayload.Item] = []
        for row in latestRows {
            let mapped = row.items.compactMap { serverItem in
                makeItem(from: serverItem, imageURL: imageURL(serverItem, row.rowType), contentImageURL: contentImageURL(serverItem))
            }
            allItems.append(contentsOf: mapped)
        }

        allItems.shuffle()
        let selected = Array(allItems.prefix(Self.maxItems))

        guard !selected.isEmpty else {
            if let fileURL = TopShelfShared.cacheFileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            notifyTopShelfChanged()
            return
        }

        let section = TopShelfCachePayload.Section(
            id: "latest",
            title: "Latest",
            items: selected,
            landscape: true
        )

        guard let fileURL = TopShelfShared.cacheFileURL else { return }

        let payload = TopShelfCachePayload(sections: [section])
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

    private func makeItem(from item: ServerItem, imageURL: String?, contentImageURL: String?) -> TopShelfCachePayload.Item? {
        guard let displayLink = deepLink(for: item, host: "item"),
              let playLink = deepLink(for: item, host: "play") else { return nil }
        return TopShelfCachePayload.Item(
            id: item.id,
            title: item.name,
            imageURL: imageURL,
            contentImageURL: contentImageURL,
            displayURL: displayLink.absoluteString,
            playURL: playLink.absoluteString,
            playbackProgress: playbackProgress(for: item)
        )
    }

    private func deepLink(for item: ServerItem, host: String = "item") -> URL? {
        var components = URLComponents()
        components.scheme = "moonfin"
        components.host = host

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