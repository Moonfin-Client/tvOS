import Foundation

struct SyncPlayState {
    var enabled = false
    var groupInfo: SyncPlayGroupInfo?
    var groupState: SyncPlayGroupState = .idle
}

struct SyncPlayGroupInfo: Codable {
    let groupId: String
    let groupName: String?
    let participants: [String]
    let lastUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case groupName = "GroupName"
        case participants = "Participants"
        case lastUpdatedAt = "LastUpdatedAt"
    }
}

enum SyncPlayGroupState: String, Codable {
    case idle = "Idle"
    case waiting = "Waiting"
    case paused = "Paused"
    case playing = "Playing"
}

enum SyncPlayCommandType: String, Codable {
    case unpause = "Unpause"
    case pause = "Pause"
    case seek = "Seek"
    case stop = "Stop"
}

struct SyncPlayCommand {
    let groupId: String
    let command: SyncPlayCommandType
    let positionTicks: Int64
    let whenUtcMs: Int64
    let playlistItemId: String?
    let emittedAtUtcMs: Int64
}

struct SyncPlayGroupUpdate {
    let type: SyncPlayGroupUpdateType
    let data: [String: Any]
}

enum SyncPlayGroupUpdateType: String {
    case groupJoined = "GroupJoined"
    case groupLeft = "GroupLeft"
    case stateUpdate = "StateUpdate"
    case userJoined = "UserJoined"
    case userLeft = "UserLeft"
    case playQueue = "PlayQueue"
    case notInGroup = "NotInGroup"
}

struct SyncPlayUtils {
    static let ticksPerMs: Int64 = 10_000
    static func ticksToMs(_ ticks: Int64) -> Int64 { ticks / ticksPerMs }
    static func msToTicks(_ ms: Int64) -> Int64 { ms * ticksPerMs }

    static func parseISOToMs(_ iso: String) -> Int64 {
        if let date = isoFormatterFractional.date(from: iso) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        if let date = isoFormatter.date(from: iso) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
