import Foundation

enum ServerWebSocketMessage {
    case libraryChanged(itemsAdded: [String], itemsUpdated: [String], itemsRemoved: [String])
    case userDataChanged(userId: String, itemIds: [String])
    case play(itemIds: [String], startPositionTicks: Int64?, playCommand: String)
    case playstate(command: String, seekPositionTicks: Int64?)
    case generalCommand(name: String, arguments: [String: String])
    case serverRestarting
    case serverShuttingDown
    case sessionEnded(sessionId: String)
    case scheduledTaskEnded(taskId: String, taskName: String, status: String)
    case syncPlayCommand(SyncPlayCommand)
    case syncPlayGroupUpdate(SyncPlayGroupUpdate)
}
