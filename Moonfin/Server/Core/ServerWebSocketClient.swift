import Foundation

final class ServerWebSocketClient: ServerWebSocketApi {
    private let serverType: ServerType
    private let httpClient: HttpClient
    private var webSocketTask: URLSessionWebSocketTask?
    private var keepAliveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 12

    var onMessage: ((ServerWebSocketMessage) -> Void)?

    init(serverType: ServerType, httpClient: HttpClient) {
        self.serverType = serverType
        self.httpClient = httpClient
    }

    func connect() async throws {
        await disconnect()
        guard let baseURL = httpClient.baseURL,
              let token = httpClient.accessToken else { return }

        let wsURL: URL
        switch serverType {
        case .jellyfin:
            wsURL = buildJellyfinURL(base: baseURL)
        case .emby:
            wsURL = buildEmbyURL(base: baseURL, token: token, deviceId: httpClient.deviceId)
        }

        var request = URLRequest(url: wsURL)
        if serverType == .jellyfin {
            request.setValue(httpClient.authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        reconnectAttempt = 0
        receiveMessages()
    }

    func disconnect() async {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func buildJellyfinURL(base: URL) -> URL {
        let str = base.absoluteString
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(str)/socket")!
    }

    private func buildEmbyURL(base: URL, token: String, deviceId: String) -> URL {
        let str = base.absoluteString
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceId
        return URL(string: "\(str)/embywebsocket?api_key=\(token)&deviceId=\(encoded)")!
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleRawMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleRawMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handleRawMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = json["MessageType"] as? String else { return }

        let msgData = json["Data"]

        if messageType == "ForceKeepAlive" {
            let interval = (msgData as? NSNumber)?.int64Value ?? 60
            startKeepAlive(intervalSeconds: interval)
            return
        }

        guard let dataDict = msgData as? [String: Any] else {
            switch messageType {
            case "ServerRestarting":
                onMessage?(.serverRestarting)
            case "ServerShuttingDown":
                onMessage?(.serverShuttingDown)
            default:
                break
            }
            return
        }

        let parsed = parseMessage(type: messageType, data: dataDict)
        if let parsed { onMessage?(parsed) }
    }

    private func parseMessage(type: String, data: [String: Any]) -> ServerWebSocketMessage? {
        switch type {
        case "LibraryChanged":
            return .libraryChanged(
                itemsAdded: data["ItemsAdded"] as? [String] ?? [],
                itemsUpdated: data["ItemsUpdated"] as? [String] ?? [],
                itemsRemoved: data["ItemsRemoved"] as? [String] ?? []
            )
        case "UserDataChanged":
            guard let userId = data["UserId"] as? String else { return nil }
            let itemIds = (data["UserDataList"] as? [[String: Any]])?
                .compactMap { $0["ItemId"] as? String } ?? []
            return .userDataChanged(userId: userId, itemIds: itemIds)
        case "Play":
            let itemIds = data["ItemIds"] as? [String] ?? []
            guard !itemIds.isEmpty else { return nil }
            let ticks = data["StartPositionTicks"] as? Int64
            let command = data["PlayCommand"] as? String ?? "PlayNow"
            return .play(itemIds: itemIds, startPositionTicks: ticks, playCommand: command)
        case "Playstate":
            guard let command = data["Command"] as? String else { return nil }
            let ticks = data["SeekPositionTicks"] as? Int64
            return .playstate(command: command, seekPositionTicks: ticks)
        case "GeneralCommand":
            guard let name = data["Name"] as? String else { return nil }
            let args = (data["Arguments"] as? [String: Any])?
                .compactMapValues { $0 as? String } ?? [:]
            return .generalCommand(name: name, arguments: args)
        case "SessionEnded":
            let sessionId = data["Id"] as? String ?? data["SessionId"] as? String ?? ""
            guard !sessionId.isEmpty else { return nil }
            return .sessionEnded(sessionId: sessionId)
        case "ScheduledTaskEnded":
            guard let taskId = data["Id"] as? String,
                  let taskName = data["Name"] as? String,
                  let status = data["Status"] as? String else { return nil }
            return .scheduledTaskEnded(taskId: taskId, taskName: taskName, status: status)
        default:
            return nil
        }
    }

    private func startKeepAlive(intervalSeconds: Int64) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 500_000_000)
                guard !Task.isCancelled else { break }
                let message = URLSessionWebSocketTask.Message.string("{\"MessageType\":\"KeepAlive\"}")
                try? await self?.webSocketTask?.send(message)
            }
        }
    }

    private func scheduleReconnect() {
        guard httpClient.isConfigured else { return }
        guard reconnectAttempt < maxReconnectAttempts else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let attempt = self.reconnectAttempt
            let baseDelay = min(30_000, 1_000 * (1 << min(attempt, 5)))
            let jitter = Int.random(in: 0...(baseDelay / 2))
            let delayMs = baseDelay + jitter
            self.reconnectAttempt += 1

            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            try? await self.connect()
        }
    }
}
