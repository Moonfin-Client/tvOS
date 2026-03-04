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

    // MARK: - Repositories

    let userRepository: UserRepositoryProtocol
    let serverRepository: ServerRepositoryProtocol
    let sessionRepository: SessionRepositoryProtocol
    let serverUserRepository: ServerUserRepositoryProtocol
    let authenticationRepository: AuthenticationRepositoryProtocol

    init(
        preferenceStore: PreferenceStore? = nil,
        keychainStore: KeychainStore? = nil,
        authenticationStore: AuthenticationStore? = nil,
        serverClientFactory: MediaServerClientFactory? = nil
    ) {
        let store = preferenceStore ?? UserDefaultsPreferenceStore()
        let authStore = authenticationStore ?? AuthenticationStore()
        let factory = serverClientFactory ?? MediaServerClientFactory()
        let authPrefs = AuthenticationPreferences(store: store)

        self.deviceInfo = DeviceInfo()
        self.preferenceStore = store
        self.keychainStore = keychainStore ?? KeychainStore()
        self.authenticationStore = authStore
        self.authPreferences = authPrefs
        self.userPreferences = UserPreferences(store: store)
        self.serverClientFactory = factory

        let userRepo = UserRepository()
        let serverRepo = ServerRepository(authenticationStore: authStore, serverClientFactory: factory)
        let sessionRepo = SessionRepository(
            authPreferences: authPrefs,
            authenticationStore: authStore,
            serverClientFactory: factory,
            userRepository: userRepo,
            serverRepository: serverRepo
        )
        let serverUserRepo = ServerUserRepository(authenticationStore: authStore, serverClientFactory: factory)
        let authRepo = AuthenticationRepository(
            authenticationStore: authStore,
            authPreferences: authPrefs,
            serverClientFactory: factory,
            sessionRepository: sessionRepo
        )

        self.userRepository = userRepo
        self.serverRepository = serverRepo
        self.sessionRepository = sessionRepo
        self.serverUserRepository = serverUserRepo
        self.authenticationRepository = authRepo
    }
}
