import SwiftUI
import Combine

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
    let telemetryPreferences: TelemetryPreferences
    let localizationPreferences: LocalizationPreferences

    // MARK: - Server

    let serverClientFactory: MediaServerClientFactory

    // MARK: - Services

    let dataRefreshService: DataRefreshService
    let pluginSyncService: PluginSyncService
    let itemMutationService: ItemMutationService
    let spotlightIndexer: SpotlightIndexer
    let inactivityTracker: InactivityTracker
    private var inactivityTrackerCancellable: AnyCancellable?
    let serverConnectionMonitor: ServerConnectionMonitor
    let featureDegradationManager: FeatureDegradationManager
    let userViewsService: UserViewsService

    // MARK: - Playback

    let playbackCoordinator: PlaybackCoordinator

    // MARK: - SyncPlay

    let syncPlayManager: SyncPlayManager

    // MARK: - Repositories

    let userRepository: UserRepositoryProtocol
    let serverRepository: ServerRepositoryProtocol
    let sessionRepository: SessionRepositoryProtocol
    let serverUserRepository: ServerUserRepositoryProtocol
    let authenticationRepository: AuthenticationRepositoryProtocol
    let mdbListRepository: MdbListRepository
    let tmdbRepository: TmdbRepository
    let seerrRepository: SeerrRepositoryProtocol
    let multiServerRepository: MultiServerRepositoryProtocol
    let parentalControlsRepository: ParentalControlsRepository

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
        self.telemetryPreferences = TelemetryPreferences(store: store)
        self.localizationPreferences = LocalizationPreferences(store: store)
        self.serverClientFactory = factory
        self.dataRefreshService = DataRefreshService()

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
        self.itemMutationService = ItemMutationService(serverClientFactory: factory, serverRepository: serverRepo)
        self.spotlightIndexer = SpotlightIndexer(serverClientFactory: factory, serverRepository: serverRepo)
        self.playbackCoordinator = PlaybackCoordinator(
            serverClientFactory: factory,
            serverRepository: serverRepo,
            preferences: self.userPreferences
        )
        self.inactivityTracker = InactivityTracker(
            userPreferences: self.userPreferences,
            playbackCoordinator: self.playbackCoordinator
        )
        self.syncPlayManager = SyncPlayManager(
            serverRepository: serverRepo,
            serverClientFactory: factory,
            playbackCoordinator: self.playbackCoordinator,
            userPreferences: self.userPreferences
        )

        self.serverConnectionMonitor = ServerConnectionMonitor(
            serverClientFactory: factory,
            serverRepository: serverRepo
        )
        self.featureDegradationManager = FeatureDegradationManager()
        self.userViewsService = UserViewsService(
            serverRepository: serverRepo,
            serverClientFactory: factory,
            userRepository: userRepo
        )

        let resolveClient: () -> HttpClient? = { [weak serverRepo] in
            guard let server = serverRepo?.currentServer.value else { return nil }
            return factory.client(for: server).httpClient
        }

        self.mdbListRepository = MdbListRepository(resolveClient: resolveClient)
        self.tmdbRepository = TmdbRepository(resolveClient: resolveClient)
        self.seerrRepository = SeerrRepository(
            userRepository: userRepo,
            serverClientFactory: factory,
            sessionRepository: sessionRepo,
            serverRepository: serverRepo
        )
        self.multiServerRepository = MultiServerRepository(
            serverRepository: serverRepo,
            sessionRepository: sessionRepo,
            authenticationStore: authStore,
            serverClientFactory: factory
        )
        self.parentalControlsRepository = ParentalControlsRepository(
            sessionRepository: sessionRepo,
            multiServerRepository: self.multiServerRepository
        )

        let seerrRepo = self.seerrRepository
        let parentalRepo = self.parentalControlsRepository
        self.pluginSyncService = PluginSyncService(
            resolveClient: resolveClient,
            resolveSeerrRepository: { [weak seerrRepo] in seerrRepo },
            resolveParentalRepository: { [weak parentalRepo] in parentalRepo }
        )

        CrashReporter.shared.configure(preferences: self.telemetryPreferences)
        LocalizationManager.shared.configure(preferences: self.localizationPreferences)

        self.inactivityTrackerCancellable = self.inactivityTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }
}
