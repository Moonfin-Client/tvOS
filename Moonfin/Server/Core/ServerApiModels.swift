import Foundation

struct AuthResult: Codable {
    let accessToken: String
    let user: ServerUser
    let serverId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
        case serverId = "ServerId"
    }
}

struct PublicSystemInfo: Codable {
    let serverName: String?
    let version: String?
    let productName: String?
    let id: String?
    let startupWizardCompleted: Bool?
    let localAddress: String?
    let wanAddress: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
        case localAddress = "LocalAddress"
        case wanAddress = "WanAddress"
    }
}

struct SystemInfo: Codable {
    let serverName: String
    let version: String
    let productName: String
    let id: String
    let localAddress: String?
    let wanAddress: String?
    let operatingSystem: String?
    let httpServerPortNumber: Int?
    let httpsPortNumber: Int?
    let webSocketPortNumber: Int?
    let hasPendingRestart: Bool?
    let isShuttingDown: Bool?
    let canSelfRestart: Bool?
    let canSelfUpdate: Bool?
    let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case id = "Id"
        case localAddress = "LocalAddress"
        case wanAddress = "WanAddress"
        case operatingSystem = "OperatingSystem"
        case httpServerPortNumber = "HttpServerPortNumber"
        case httpsPortNumber = "HttpsPortNumber"
        case webSocketPortNumber = "WebSocketPortNumber"
        case hasPendingRestart = "HasPendingRestart"
        case isShuttingDown = "IsShuttingDown"
        case canSelfRestart = "CanSelfRestart"
        case canSelfUpdate = "CanSelfUpdate"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}

struct QuickConnectInfo: Codable {
    let secret: String
    let code: String
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case authenticated = "Authenticated"
    }

    init(secret: String, code: String, authenticated: Bool = false) {
        self.secret = secret
        self.code = code
        self.authenticated = authenticated
    }
}

struct DisplayPreferences: Codable {
    let id: String?
    let sortBy: String?
    let sortOrder: SortOrder?
    let customPrefs: [String: String]?
    let client: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case sortBy = "SortBy"
        case sortOrder = "SortOrder"
        case customPrefs = "CustomPrefs"
        case client = "Client"
    }
}

struct SessionInfo: Codable {
    let id: String
    let userId: String?
    let userName: String?
    let client: String?
    let deviceId: String?
    let deviceName: String?
    let applicationVersion: String?
    let remoteEndPoint: String?
    let nowPlayingItemId: String?
    let nowPlayingItemName: String?
    let lastActivityDate: Date?
    let supportsRemoteControl: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case userId = "UserId"
        case userName = "UserName"
        case client = "Client"
        case deviceId = "DeviceId"
        case deviceName = "DeviceName"
        case applicationVersion = "ApplicationVersion"
        case remoteEndPoint = "RemoteEndPoint"
        case nowPlayingItemId = "NowPlayingItemId"
        case nowPlayingItemName = "NowPlayingItemName"
        case lastActivityDate = "LastActivityDate"
        case supportsRemoteControl = "SupportsRemoteControl"
    }
}

struct ClientCapabilities: Codable {
    let playableMediaTypes: [String]
    let supportedCommands: [String]
    let supportsMediaControl: Bool
    let supportsSync: Bool
    let iconUrl: String?

    enum CodingKeys: String, CodingKey {
        case playableMediaTypes = "PlayableMediaTypes"
        case supportedCommands = "SupportedCommands"
        case supportsMediaControl = "SupportsMediaControl"
        case supportsSync = "SupportsSync"
        case iconUrl = "IconUrl"
    }

    init(
        playableMediaTypes: [String] = [],
        supportedCommands: [String] = [],
        supportsMediaControl: Bool = false,
        supportsSync: Bool = false,
        iconUrl: String? = nil
    ) {
        self.playableMediaTypes = playableMediaTypes
        self.supportedCommands = supportedCommands
        self.supportsMediaControl = supportsMediaControl
        self.supportsSync = supportsSync
        self.iconUrl = iconUrl
    }
}

