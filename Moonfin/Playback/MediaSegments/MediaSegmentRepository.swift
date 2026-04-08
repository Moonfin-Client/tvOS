import Foundation
import OSLog

protocol MediaSegmentRepository {
    func getSegmentTypeAction(_ type: MediaSegmentType) -> MediaSegmentAction
    func setSegmentTypeAction(_ type: MediaSegmentType, action: MediaSegmentAction)
    func getSegmentsForItem(itemId: String) async -> [MediaSegmentDto]
    func resolvedAction(for segment: MediaSegmentDto) -> MediaSegmentAction
}

final class MediaSegmentRepositoryImpl: MediaSegmentRepository {
    static let skipMinDuration: TimeInterval = 1.0
    static let askToSkipMinDuration: TimeInterval = 3.0
    static let askToSkipAutoHideDuration: TimeInterval = 8.0

    private let preferences: UserPreferences
    private let client: MediaServerClient
    private var typeActions: [MediaSegmentType: MediaSegmentAction] = [:]
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "MediaSegments")

    init(preferences: UserPreferences, client: MediaServerClient) {
        self.preferences = preferences
        self.client = client
        restoreActions()
    }

    private func restoreActions() {
        let raw = preferences[UserPreferences.mediaSegmentActions]
        typeActions = Self.parseActionsString(raw)
    }

    private func saveActions() {
        preferences[UserPreferences.mediaSegmentActions] = Self.actionsToString(typeActions)
    }

    func getSegmentTypeAction(_ type: MediaSegmentType) -> MediaSegmentAction {
        guard MediaSegmentType.supported.contains(type) else { return .nothing }
        return typeActions[type] ?? .nothing
    }

    func setSegmentTypeAction(_ type: MediaSegmentType, action: MediaSegmentAction) {
        guard MediaSegmentType.supported.contains(type) else { return }
        typeActions[type] = action
        saveActions()
    }

    func resolvedAction(for segment: MediaSegmentDto) -> MediaSegmentAction {
        let action = getSegmentTypeAction(segment.type)
        if action == .skip && segment.durationSeconds < Self.skipMinDuration { return .nothing }
        if action == .askToSkip && segment.durationSeconds < Self.askToSkipMinDuration { return .nothing }
        return action
    }

    func getSegmentsForItem(itemId: String) async -> [MediaSegmentDto] {
        guard client.serverType == .jellyfin else { return [] }
        do {
            let result: MediaSegmentQueryResult = try await client.httpClient.request(
                "/MediaSegments/\(itemId)",
                queryItems: []
            )
            return result.items
        } catch {
            logger.error("Failed to fetch segments for \(itemId): \(error.localizedDescription)")
            return []
        }
    }

    static func parseActionsString(_ value: String) -> [MediaSegmentType: MediaSegmentAction] {
        var map: [MediaSegmentType: MediaSegmentAction] = [:]
        for pair in value.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let type = MediaSegmentType(rawValue: String(parts[0])),
                  let action = MediaSegmentAction(rawValue: String(parts[1])) else { continue }
            map[type] = action
        }
        return map
    }

    static func actionsToString(_ map: [MediaSegmentType: MediaSegmentAction]) -> String {
        map.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value.rawValue)" }
            .joined(separator: ",")
    }
}
