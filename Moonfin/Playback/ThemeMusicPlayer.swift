import AVFoundation
import Combine

@MainActor
final class ThemeMusicPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var currentItemId: String?
    private var fadeTask: Task<Void, Never>?
    private var targetVolume: Float = 0.3

    private static let fadeDurationMs: UInt64 = 2000
    private static let fadeStepMs: UInt64 = 50
    private static let validTypes: Set<ItemType> = [.series, .movie, .season, .episode]

    func playThemeMusic(
        for item: ServerItem,
        client: MediaServerClient,
        preferences: UserPreferences
    ) {
        guard preferences[UserPreferences.themeMusicEnabled] else { return }
        guard Self.validTypes.contains(item.type) else { return }

        let resolvedId = (item.type == .episode ? item.seriesId : nil) ?? item.id

        if currentItemId == resolvedId && isPlaying { return }

        stop()
        currentItemId = resolvedId
        targetVolume = Float(preferences[UserPreferences.themeMusicVolume]) / 100.0

        Task {
            guard let userId = client.userId else { return }
            do {
                let result = try await client.userLibraryApi.getThemeMedia(
                    itemId: resolvedId,
                    userId: userId,
                    inheritFromParent: true
                )
                let songs = result.themeSongsResult.items
                guard !songs.isEmpty else { return }
                guard currentItemId == resolvedId else { return }

                let song = songs.randomElement()!
                let url = buildAudioUrl(itemId: song.id, client: client)
                guard let audioUrl = URL(string: url) else { return }

                startPlayback(url: audioUrl)
            } catch { }
        }
    }

    func fadeOutAndStop() {
        guard isPlaying else {
            stop()
            return
        }

        fadeTask?.cancel()
        fadeTask = Task {
            let steps = Int(Self.fadeDurationMs / Self.fadeStepMs)
            let currentVol = queuePlayer?.volume ?? targetVolume

            for i in stride(from: steps, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                let vol = (Float(i) / Float(steps)) * currentVol
                queuePlayer?.volume = vol
                try? await Task.sleep(nanoseconds: Self.fadeStepMs * 1_000_000)
            }

            stop()
        }
    }

    func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        playerLooper?.disableLooping()
        playerLooper = nil
        currentItemId = nil
        isPlaying = false
    }

    private func startPlayback(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: playerItem)
        let looper = AVPlayerLooper(player: queue, templateItem: playerItem)

        queue.volume = 0
        queue.play()

        self.queuePlayer = queue
        self.playerLooper = looper
        self.isPlaying = true

        fadeIn()
    }

    private func fadeIn() {
        fadeTask?.cancel()
        fadeTask = Task {
            let steps = Int(Self.fadeDurationMs / Self.fadeStepMs)

            for i in 0...steps {
                guard !Task.isCancelled else { return }
                let vol = (Float(i) / Float(steps)) * targetVolume
                queuePlayer?.volume = vol
                try? await Task.sleep(nanoseconds: Self.fadeStepMs * 1_000_000)
            }
        }
    }

    private func buildAudioUrl(itemId: String, client: MediaServerClient) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else { return "" }
        var url = "\(base)/Audio/\(itemId)/stream?static=true&audioCodec=mp3&audioBitrate=128000"
        if let token = client.accessToken {
            url += "&api_key=\(token)"
        }
        return url
    }
}
