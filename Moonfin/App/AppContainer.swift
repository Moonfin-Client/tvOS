import SwiftUI

@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Core

    let deviceInfo: DeviceInfo

    // MARK: - Stores

    let preferenceStore: PreferenceStore
    let keychainStore: KeychainStore
    let authenticationStore: AuthenticationStore

    // MARK: - Preferences

    let authPreferences: AuthenticationPreferences
    let userPreferences: UserPreferences

    // MARK: - Server

    let serverClientFactory: MediaServerClientFactory

    init(
        preferenceStore: PreferenceStore? = nil,
        keychainStore: KeychainStore? = nil,
        authenticationStore: AuthenticationStore? = nil,
        serverClientFactory: MediaServerClientFactory? = nil
    ) {
        let store = preferenceStore ?? UserDefaultsPreferenceStore()
        self.deviceInfo = DeviceInfo()
        self.preferenceStore = store
        self.keychainStore = keychainStore ?? KeychainStore()
        self.authenticationStore = authenticationStore ?? AuthenticationStore()
        self.authPreferences = AuthenticationPreferences(store: store)
        self.userPreferences = UserPreferences(store: store)
        self.serverClientFactory = serverClientFactory ?? MediaServerClientFactory()
    }
}
