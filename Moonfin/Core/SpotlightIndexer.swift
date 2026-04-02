import Foundation

@MainActor
final class SpotlightIndexer {
    static let activityType = "org.moonfin.app.viewItem"
    static let itemIdKey = "itemId"
    static let serverIdKey = "serverId"

    private let serverRepository: ServerRepositoryProtocol
    private var registeredActivities: [String: NSUserActivity] = [:]

    init(serverClientFactory: MediaServerClientFactory, serverRepository: ServerRepositoryProtocol) {
        self.serverRepository = serverRepository
    }

    func indexItems(_ items: [ServerItem]) {
        for item in items where isIndexable(item) && registeredActivities[item.id] == nil {
            let activity = makeActivity(for: item)
            activity.becomeCurrent()
            registeredActivities[item.id] = activity
        }
    }

    func deleteAllItems() {
        for activity in registeredActivities.values {
            activity.invalidate()
        }
        registeredActivities.removeAll()
    }

    private func isIndexable(_ item: ServerItem) -> Bool {
        switch item.type {
        case .movie, .series, .episode, .musicAlbum, .audio, .musicArtist, .boxSet:
            return true
        default:
            return false
        }
    }

    private func makeActivity(for item: ServerItem) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.title = displayTitle(for: item)
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false
        activity.targetContentIdentifier = "moonfin://item?id=\(item.id)"

        let serverId = item.effectiveServerId ?? serverRepository.currentServer.value?.id.uuidString ?? ""
        activity.userInfo = [
            Self.itemIdKey: item.id,
            Self.serverIdKey: serverId
        ]

        var keywords = Set<String>()
        keywords.insert(item.name)
        if let genres = item.genres { keywords.formUnion(genres) }
        if let seriesName = item.seriesName { keywords.insert(seriesName) }
        if let artists = item.artists { keywords.formUnion(artists) }
        if let year = item.productionYear { keywords.insert(String(year)) }
        activity.keywords = keywords

        activity.requiredUserInfoKeys = [Self.itemIdKey]

        return activity
    }

    private func displayTitle(for item: ServerItem) -> String {
        switch item.type {
        case .episode:
            if let series = item.seriesName {
                let ep = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }]
                    .compactMap { $0 }.joined()
                return "\(series) \(ep) — \(item.name)"
            }
            return item.name
        default:
            return item.name
        }
    }

    static func parseUserActivity(_ activity: NSUserActivity) -> (itemId: String, serverId: String?)? {
        guard activity.activityType == activityType,
              let itemId = activity.userInfo?[itemIdKey] as? String else { return nil }
        let serverId = activity.userInfo?[serverIdKey] as? String
        return (itemId, serverId?.isEmpty == true ? nil : serverId)
    }
}
