import Foundation
import Combine

@MainActor
final class PlaybackCoordinator: ObservableObject {
    @Published private(set) var videoPlayerManager: PlaybackManager?
    @Published private(set) var audioManager: AudioManager?

    private let serverClientFactory: MediaServerClientFactory
    private let serverRepository: ServerRepositoryProtocol
    private let preferences: UserPreferences

    private var client: MediaServerClient? {
        guard let server = serverRepository.currentServer.value else { return nil }
        return serverClientFactory.client(for: server)
    }

    init(
        serverClientFactory: MediaServerClientFactory,
        serverRepository: ServerRepositoryProtocol,
        preferences: UserPreferences
    ) {
        self.serverClientFactory = serverClientFactory
        self.serverRepository = serverRepository
        self.preferences = preferences
    }

    func startVideoPlayback(
        items: [ServerItem],
        startIndex: Int = 0,
        startPosition: TimeInterval = 0,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async {
        await stopVideoPlayback()
        guard let client else { return }
        let player = VLCPlayerWrapper()
        let manager = PlaybackManager(player: player, client: client, preferences: preferences)
        videoPlayerManager = manager
        await manager.play(
            items: items,
            startIndex: startIndex,
            startPosition: startPosition,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    func stopVideoPlayback() async {
        await videoPlayerManager?.stop()
        videoPlayerManager = nil
    }

    func startAudioPlayback(items: [ServerItem], startIndex: Int = 0, shuffle: Bool = false) async {
        await stopAudioPlayback()
        guard let client else { return }
        let player = VLCPlayerWrapper()
        let manager = PlaybackManager(player: player, client: client, preferences: preferences)
        let audio = AudioManager(playbackManager: manager, client: client)
        audioManager = audio
        await audio.playNow(items: items, startIndex: startIndex, shuffle: shuffle)
    }

    func stopAudioPlayback() async {
        await audioManager?.playbackManager.stop()
        audioManager = nil
    }
}
