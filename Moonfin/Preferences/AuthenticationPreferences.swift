import Foundation

final class AuthenticationPreferences {
    private var store: PreferenceStore

    static let autoLoginBehavior = Preference(key: "auth_auto_login_behavior", defaultValue: AutoLoginBehavior.lastUser)
    static let autoLoginServerId = Preference(key: "auth_auto_login_server_id", defaultValue: "")
    static let autoLoginUserId = Preference(key: "auth_auto_login_user_id", defaultValue: "")
    static let lastServerId = Preference(key: "auth_last_server_id", defaultValue: "")
    static let lastUserId = Preference(key: "auth_last_user_id", defaultValue: "")
    static let sortBy = Preference(key: "auth_sort_by", defaultValue: ServerSortBy.lastUsed)
    static let alwaysAuthenticate = Preference(key: "auth_always_authenticate", defaultValue: false)

    init(store: PreferenceStore) {
        self.store = store
    }

    var autoLoginBehavior: AutoLoginBehavior {
        get { store[Self.autoLoginBehavior] }
        set { store[Self.autoLoginBehavior] = newValue }
    }

    var autoLoginServerId: String {
        get { store[Self.autoLoginServerId] }
        set { store[Self.autoLoginServerId] = newValue }
    }

    var autoLoginUserId: String {
        get { store[Self.autoLoginUserId] }
        set { store[Self.autoLoginUserId] = newValue }
    }

    var lastServerId: String {
        get { store[Self.lastServerId] }
        set { store[Self.lastServerId] = newValue }
    }

    var lastUserId: String {
        get { store[Self.lastUserId] }
        set { store[Self.lastUserId] = newValue }
    }

    var sortBy: ServerSortBy {
        get { store[Self.sortBy] }
        set { store[Self.sortBy] = newValue }
    }

    var alwaysAuthenticate: Bool {
        get { store[Self.alwaysAuthenticate] }
        set { store[Self.alwaysAuthenticate] = newValue }
    }
}

enum AutoLoginBehavior: String, StringRepresentableEnum, CaseIterable {
    case lastUser
    case disabled
    case specificUser

    var displayName: String {
        switch self {
        case .lastUser: return Strings.authLastUser
        case .disabled: return Strings.disabled
        case .specificUser: return Strings.authSpecificUser
        }
    }
}

enum ServerSortBy: String, StringRepresentableEnum, CaseIterable {
    case lastUsed
    case alphabetical

    var displayName: String {
        switch self {
        case .lastUsed: return Strings.lastUsed
        case .alphabetical: return Strings.alphabetical
        }
    }
}
