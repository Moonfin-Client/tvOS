import SwiftUI
import Combine
import UIKit

/// Manages a single shared VLC player instance used for home-row card previews.
///
/// Only one preview plays at a time. When focus moves to a new card, the manager
/// cancels the in-flight task and restarts for the new item. Each preview loops on
/// a 30-second cycle. Playback stops automatically when the app is backgrounded or
/// suspended.
@MainActor
final class PreviewPlayerManager: ObservableObject {

    private static let maxPreviewPlays = 2
    private static let previewLoopIntervalNanoseconds: UInt64 = 30_000_000_000

    // MARK: - Public observable state

    /// The `id` of the item currently being previewed, or nil when idle.
    @Published private(set) var currentItemId: String?

    /// True while VLC is opening, buffering, or playing (drives overlay visibility).
    @Published private(set) var isVisible: Bool = false

    /// The shared player. Cards observe this directly via VLCPlayerView.
    let player = MpvPlayerWrapper.makePlayer()

    // MARK: - Private state

    private var currentTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    private var currentStreamUrl: URL?
    private var currentSeekPosition: TimeInterval = 0
    private var currentMuted: Bool = true
    private var currentPlayCount: Int = 0
    private var stateObserver: AnyCancellable?

    // MARK: - Init / deinit

    init() {
        stateObserver = player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .opening, .buffering, .playing:
                    self.isVisible = true
                case .ended:
                    self.isVisible = false
                    Task { await self.handlePlaybackEnded() }
                default:
                    self.isVisible = false
                }
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Start a preview for `item` after a 1.5 s debounce. Cancels any existing preview first.
    func requestPreview(for item: ServerItem, muted: Bool, container: AppContainer) {
        currentTask?.cancel()
        stopInternal()
        currentMuted = muted
        currentTask = Task { await startPreview(for: item, container: container) }
    }

    /// Stop preview only if `itemId` is the currently active item (safe to call on unfocus).
    func stopIfCurrent(itemId: String) {
        guard currentItemId == itemId else { return }
        stop()
    }

    /// Unconditionally stop everything and release player resources.
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        stopInternal()
    }

    // MARK: - Private helpers

    private func stopInternal() {
        loopTask?.cancel()
        loopTask = nil
        currentStreamUrl = nil
        currentSeekPosition = 0
        currentPlayCount = 0
        currentItemId = nil
        isVisible = false
        player.stop()
    }

    @objc private func handleResignActive() {
        stop()
    }

    private func scheduleLoopRestart() {
        loopTask?.cancel()
        guard currentPlayCount < Self.maxPreviewPlays else { return }
        loopTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: Self.previewLoopIntervalNanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.restartPlayback()
        }
    }

    private func handlePlaybackEnded() async {
        guard currentStreamUrl != nil else { return }
        loopTask?.cancel()
        loopTask = nil
        guard currentPlayCount < Self.maxPreviewPlays else {
            stop()
            return
        }
        await restartPlayback()
    }

    private func restartPlayback() async {
        guard let url = currentStreamUrl else { return }
        guard currentPlayCount < Self.maxPreviewPlays else {
            stop()
            return
        }

        currentPlayCount += 1
        scheduleLoopRestart()
        await player.play(streamUrl: url.absoluteString, startPosition: currentSeekPosition)
        player.mediaPlayer?.audio?.isMuted = currentMuted
    }

    // MARK: - Preview startup

    private func startPreview(for item: ServerItem, container: AppContainer) async {
        do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }

        do {
            guard let server = container.serverRepository.currentServer.value else { return }
            let client = container.serverClientFactory.client(for: server)

            guard let episode = try await resolvePreviewEpisode(item: item, client: client) else { return }
            guard !Task.isCancelled else { return }

            let seekPosition = await determineSeekPosition(for: episode, client: client)
            guard !Task.isCancelled else { return }

            let url = try await getStreamUrl(for: episode, client: client)
            guard !Task.isCancelled else { return }

            currentStreamUrl = url
            currentSeekPosition = seekPosition
            currentPlayCount = 1
            currentItemId = item.id

            scheduleLoopRestart()
            await player.play(streamUrl: url.absoluteString, startPosition: seekPosition)
            player.mediaPlayer?.audio?.isMuted = currentMuted

        } catch { }
    }

    // MARK: - Episode resolution

    private func resolvePreviewEpisode(item: ServerItem, client: MediaServerClient) async throws -> ServerItem? {
        let userId = client.userId ?? ""
        switch item.type {
        case .episode, .movie, .trailer, .video:
            return item
        case .season:
            if let seriesId = item.seriesId, !seriesId.isEmpty {
                if let ep = try await getFirstEpisodeOfSeason(seriesId: seriesId, seasonId: item.id, userId: userId, client: client) {
                    return ep
                }
            }
            let fallback = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    userId: userId,
                    parentId: item.id,
                    recursive: false,
                    includeItemTypes: [.episode],
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    limit: 1
                )
            )
            return fallback.items.first

        case .series:
            if let ep = try await getFirstEpisodeOfSeries(seriesId: item.id, userId: userId, client: client) {
                return ep
            }
            let fallback = try await client.itemsApi.getItems(
                request: GetItemsRequest(
                    userId: userId,
                    parentId: item.id,
                    recursive: true,
                    includeItemTypes: [.episode],
                    sortBy: [.sortName],
                    sortOrder: .ascending,
                    limit: 1
                )
            )
            return fallback.items.first

        default:
            return nil
        }
    }

    private func getFirstEpisodeOfSeries(seriesId: String, userId: String, client: MediaServerClient) async throws -> ServerItem? {
        let seasons = try await client.itemsApi.getSeasons(seriesId: seriesId, userId: userId)
        guard let first = seasons.items.first else { return nil }
        return try await getFirstEpisodeOfSeason(seriesId: seriesId, seasonId: first.id, userId: userId, client: client)
    }

    private func getFirstEpisodeOfSeason(seriesId: String, seasonId: String, userId: String, client: MediaServerClient) async throws -> ServerItem? {
        let result = try await client.itemsApi.getEpisodes(seriesId: seriesId, seasonId: seasonId, userId: userId)
        return result.items.first
    }

    // MARK: - Seek position

    private func determineSeekPosition(for episode: ServerItem, client: MediaServerClient) async -> TimeInterval {
        let ticks = episode.userData?.playbackPositionTicks ?? 0
        if ticks > 0 { return Double(ticks) / 10_000_000.0 }

        do {
            let typesQuery = MediaSegmentType.supported.map(\.rawValue).joined(separator: ",")
            let result: MediaSegmentQueryResult = try await client.httpClient.request(
                "/MediaSegments/\(episode.id)",
                queryItems: [URLQueryItem(name: "IncludeSegmentTypes", value: typesQuery)]
            )
            if let intro = result.items.first(where: { $0.type == .intro }) {
                return Double(intro.endTicks) / 10_000_000.0
            }
        } catch { }

        return 4 * 60 // 4-minute default for unstarted media
    }

    // MARK: - Stream URL

    private func getStreamUrl(for episode: ServerItem, client: MediaServerClient) async throws -> URL {
        let request = PlaybackInfoRequest(
            userId: client.userId ?? "",
            startTimeTicks: episode.userData?.playbackPositionTicks,
            enableDirectPlay: false,
            enableDirectStream: false,
            enableTranscoding: true,
            allowVideoStreamCopy: false,
            allowAudioStreamCopy: true
        )
        let playbackResult = try await client.playbackApi.getPlaybackInfo(itemId: episode.id, request: request)

        guard let mediaSource = playbackResult.mediaSources.first else {
            throw NSError(domain: "PreviewPlayer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No media source available"])
        }

        if let transcodingPath = mediaSource.transcodingUrl, !transcodingPath.isEmpty {
            guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
                throw NSError(domain: "PreviewPlayer", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "Missing server base URL"])
            }
            var urlString: String
            if transcodingPath.hasPrefix("http://") || transcodingPath.hasPrefix("https://") {
                urlString = transcodingPath
            } else {
                let path = transcodingPath.hasPrefix("/") ? transcodingPath : "/\(transcodingPath)"
                urlString = "\(base)\(path)"
            }
            if let token = client.accessToken, !urlString.contains("api_key=") {
                urlString += urlString.contains("?") ? "&api_key=\(token)" : "?api_key=\(token)"
            }
            if let url = URL(string: urlString) { return url }
        }

        throw NSError(
            domain: "PreviewPlayer",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "No transcoding preview stream available"]
        )
    }
}
