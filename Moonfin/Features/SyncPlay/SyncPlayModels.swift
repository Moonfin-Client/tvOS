import Foundation

struct SyncPlayState {
    var enabled = false
    var groupId: String?
    var groupName: String?
    var participants: [String] = []
    var groupState: SyncPlayGroupState = .idle
    var queue: [SyncPlayQueueItem] = []
    var currentPlaylistItemId: String?
    var currentItemIndex: Int = -1
    var repeatMode: SyncPlayRepeatMode = .repeatNone
    var shuffleMode: SyncPlayShuffleMode = .sorted
    var lastUpdateAt: String?
}

struct SyncPlayGroupInfo: Codable {
    let groupId: String
    let groupName: String?
    let state: SyncPlayGroupState?
    let participants: [String]
    let lastUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case groupName = "GroupName"
        case state = "State"
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

struct SyncPlayCommand: Decodable {
    let groupId: String
    let command: SyncPlayCommandType
    let positionTicks: Int64
    let whenUtcMs: Int64
    let playlistItemId: String?
    let emittedAtUtcMs: Int64

    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case command = "Command"
        case positionTicks = "PositionTicks"
        case when = "When"
        case playlistItemId = "PlaylistItemId"
        case emittedAt = "EmittedAt"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let when = try container.decode(String.self, forKey: .when)

        groupId = try container.decode(String.self, forKey: .groupId)
        command = try container.decode(SyncPlayCommandType.self, forKey: .command)
        positionTicks = try container.decodeIfPresent(Int64.self, forKey: .positionTicks) ?? 0
        whenUtcMs = SyncPlayUtils.parseISOToMs(when)
        playlistItemId = try container.decodeIfPresent(String.self, forKey: .playlistItemId)

        if let emittedAt = try container.decodeIfPresent(String.self, forKey: .emittedAt) {
            emittedAtUtcMs = SyncPlayUtils.parseISOToMs(emittedAt)
        } else {
            emittedAtUtcMs = whenUtcMs
        }
    }
}

enum SyncPlayGroupUpdatePayload {
    case groupJoined(SyncPlayGroupInfo)
    case groupLeft(String?)
    case stateUpdate(SyncPlayStateUpdate)
    case userJoined(String)
    case userLeft(String)
    case playQueue(SyncPlayPlayQueueUpdate)
    case notInGroup
    case groupDoesNotExist
    case libraryAccessDenied
}

struct SyncPlayGroupUpdate: Decodable {
    let groupId: String
    let type: SyncPlayGroupUpdateType
    let payload: SyncPlayGroupUpdatePayload

    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case type = "Type"
        case data = "Data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decode(String.self, forKey: .groupId)
        type = try container.decode(SyncPlayGroupUpdateType.self, forKey: .type)

        switch type {
        case .groupJoined:
            payload = .groupJoined(try container.decode(SyncPlayGroupInfo.self, forKey: .data))
        case .groupLeft:
            payload = .groupLeft(try container.decodeIfPresent(String.self, forKey: .data))
        case .stateUpdate:
            payload = .stateUpdate(try container.decode(SyncPlayStateUpdate.self, forKey: .data))
        case .userJoined:
            payload = .userJoined(try container.decode(String.self, forKey: .data))
        case .userLeft:
            payload = .userLeft(try container.decode(String.self, forKey: .data))
        case .playQueue:
            payload = .playQueue(try container.decode(SyncPlayPlayQueueUpdate.self, forKey: .data))
        case .notInGroup:
            payload = .notInGroup
        case .groupDoesNotExist:
            payload = .groupDoesNotExist
        case .libraryAccessDenied:
            payload = .libraryAccessDenied
        }
    }
}

enum SyncPlayGroupUpdateType: String, Codable {
    case groupJoined = "GroupJoined"
    case groupLeft = "GroupLeft"
    case stateUpdate = "StateUpdate"
    case userJoined = "UserJoined"
    case userLeft = "UserLeft"
    case playQueue = "PlayQueue"
    case notInGroup = "NotInGroup"
    case groupDoesNotExist = "GroupDoesNotExist"
    case libraryAccessDenied = "LibraryAccessDenied"
}

struct SyncPlayStateUpdate: Codable {
    let state: SyncPlayGroupState
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case state = "State"
        case reason = "Reason"
    }
}

struct SyncPlayQueueItem: Codable {
    let itemId: String
    let playlistItemId: String

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playlistItemId = "PlaylistItemId"
    }
}

enum SyncPlayPlayQueueUpdateReason: String, Codable {
    case newPlaylist = "NewPlaylist"
    case setCurrentItem = "SetCurrentItem"
    case removeItems = "RemoveItems"
    case moveItem = "MoveItem"
    case queue = "Queue"
    case queueNext = "QueueNext"
    case nextItem = "NextItem"
    case previousItem = "PreviousItem"
    case repeatMode = "RepeatMode"
    case shuffleMode = "ShuffleMode"
}

enum SyncPlayShuffleMode: String, Codable {
    case sorted = "Sorted"
    case shuffle = "Shuffle"
}

enum SyncPlayRepeatMode: String, Codable {
    case repeatNone = "RepeatNone"
    case repeatOne = "RepeatOne"
    case repeatAll = "RepeatAll"
}

struct SyncPlayPlayQueueUpdate: Codable {
    let reason: SyncPlayPlayQueueUpdateReason
    let lastUpdate: String
    let playlist: [SyncPlayQueueItem]
    let playingItemIndex: Int
    let startPositionTicks: Int64
    let isPlaying: Bool
    let shuffleMode: SyncPlayShuffleMode
    let repeatMode: SyncPlayRepeatMode

    enum CodingKeys: String, CodingKey {
        case reason = "Reason"
        case lastUpdate = "LastUpdate"
        case playlist = "Playlist"
        case playingItemIndex = "PlayingItemIndex"
        case startPositionTicks = "StartPositionTicks"
        case isPlaying = "IsPlaying"
        case shuffleMode = "ShuffleMode"
        case repeatMode = "RepeatMode"
    }
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

struct SyncPlayCommandIdentity {
    static func dedupeKey(for command: SyncPlayCommand) -> String {
        let playlistId = command.playlistItemId ?? "-"
        return "\(command.groupId)|\(command.command.rawValue)|\(command.whenUtcMs)|\(playlistId)|\(command.emittedAtUtcMs)"
    }
}
