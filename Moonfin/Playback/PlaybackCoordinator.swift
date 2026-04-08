import Foundation
import Combine

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var videoPlayerManager: PlaybackManager?
    @Published private(set) var audioManager: AudioManager?
    @Published private(set) var liveTvChannels: [ServerItem] = []
    @Published private(set) var liveTvCurrentIndex: Int = 0

    private let serverClientFactory: MediaServerClientFactory
    private let serverRepository: ServerRepositoryProtocol
    private let preferences: UserPreferences
    private let dataRefreshService: DataRefreshService

    private var client: MediaServerClient? {
        guard let server = serverRepository.currentServer.value else { return nil }
        return serverClientFactory.client(for: server)
    }

    private func client(for serverId: String?) -> MediaServerClient? {
        if let serverId,
           let parsedId = UUID.from(rawId: serverId),
           let server = serverRepository.storedServers.value.first(where: { $0.id == parsedId }) {
            return serverClientFactory.client(for: server)
        }

        return client
    }

    init(
        serverClientFactory: MediaServerClientFactory,
        serverRepository: ServerRepositoryProtocol,
        preferences: UserPreferences,
        dataRefreshService: DataRefreshService
    ) {
        self.serverClientFactory = serverClientFactory
        self.serverRepository = serverRepository
        self.preferences = preferences
        self.dataRefreshService = dataRefreshService
    }

    func startVideoPlayback(
        items: [ServerItem],
        startIndex: Int = 0,
        startPosition: TimeInterval = 0,
        serverId: String? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        mediaSourceIndex: Int? = nil
    ) async {
        await stopAudioPlayback()
        await stopVideoPlayback(shouldClearLiveTvContext: false)
        let startItem = items.indices.contains(startIndex) ? items[startIndex] : nil
        guard let client = client(for: serverId ?? startItem?.effectiveServerId) else { return }
        let player = makePlayer()
        let manager = PlaybackManager(player: player, client: client, preferences: preferences, dataRefreshService: dataRefreshService)
        videoPlayerManager = manager
        // Fire-and-forget: play() awaits the surface attachment which only
        // happens after the caller navigates to the video-player screen.
        // Blocking here would deadlock because navigation runs after this returns.
        Task {
            await manager.play(
                items: items,
                startIndex: startIndex,
                startPosition: startPosition,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex,
                mediaSourceIndex: mediaSourceIndex
            )
        }
    }

    func setLiveTvContext(channels: [ServerItem], currentIndex: Int) {
        liveTvChannels = channels
        liveTvCurrentIndex = max(0, min(currentIndex, max(0, channels.count - 1)))
    }

    func clearLiveTvContext() {
        liveTvChannels = []
        liveTvCurrentIndex = 0
    }

    func stepLiveTvChannel(by delta: Int) -> ServerItem? {
        guard !liveTvChannels.isEmpty else { return nil }
        let count = liveTvChannels.count
        let next = (liveTvCurrentIndex + delta % count + count) % count
        liveTvCurrentIndex = next
        return liveTvChannels[next]
    }

    func stopVideoPlayback(shouldClearLiveTvContext: Bool = true) async {
        await videoPlayerManager?.stop()
        videoPlayerManager = nil
        if shouldClearLiveTvContext {
            clearLiveTvContext()
        }
    }

    func startAudioPlayback(items: [ServerItem], startIndex: Int = 0, serverId: String? = nil, shuffle: Bool = false) async {
        await stopVideoPlayback()
        await stopAudioPlayback()
        let startItem = items.indices.contains(startIndex) ? items[startIndex] : nil
        guard let client = client(for: serverId ?? startItem?.effectiveServerId) else { return }
        let player = makePlayer()
        let manager = PlaybackManager(player: player, client: client, preferences: preferences, dataRefreshService: dataRefreshService)
        let audio = AudioManager(playbackManager: manager, client: client)
        audioManager = audio
        Task {
            await audio.playNow(items: items, startIndex: startIndex, shuffle: shuffle)
        }
    }

    func stopAudioPlayback() async {
        await audioManager?.playbackManager.stop()
        audioManager = nil
    }

    private func makePlayer() -> MpvPlayerWrapper {
        MpvPlayerWrapper.makePlayer()
    }
}
