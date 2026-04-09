import SwiftUI
import Combine
import UIKit

@MainActor
final class PreviewPlayerManager: ObservableObject {

    private static let maxPreviewPlays = 2
    private static let previewLoopIntervalNanoseconds: UInt64 = 30_000_000_000
    private static let idleTeardownNanoseconds: UInt64 = 30_000_000_000

    @Published private(set) var currentItemId: String?
    @Published private(set) var isVisible: Bool = false

    private(set) var player: MpvPlayerWrapper?

    let persistentSurface: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }()

    private var currentTask: Task<Void, Never>?
    private var loopTask: Task<Void, Never>?
    private var idleTeardownTask: Task<Void, Never>?
    private var pendingItemId: String?
    private var currentStreamUrl: URL?
    private var currentSeekPosition: TimeInterval = 0
    private var currentMuted: Bool = true
    private var currentPlayCount: Int = 0
    private var stateObserver: AnyCancellable?

    init() {
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

    private func ensurePlayer() -> MpvPlayerWrapper {
        if let existing = player { return existing }
        let created = MpvPlayerWrapper.makePlayer()
        created.attachVideoView(persistentSurface)
        if persistentSurface.window != nil {
            created.notifySurfaceReady()
        }
        player = created
        stateObserver = created.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .playing:
                    self.isVisible = true
                case .ended:
                    self.isVisible = false
                    Task { await self.handlePlaybackEnded() }
                default:
                    self.isVisible = false
                }
            }
        return created
    }

    private func teardownPlayer() {
        stateObserver?.cancel()
        stateObserver = nil
        player?.stop()
        player = nil
        persistentSurface.subviews.forEach { $0.removeFromSuperview() }
        persistentSurface.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func scheduleIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.idleTeardownNanoseconds)
            guard !Task.isCancelled else { return }
            self?.teardownPlayer()
        }
    }

    private func cancelIdleTeardown() {
        idleTeardownTask?.cancel()
        idleTeardownTask = nil
    }

    func requestPreview(for item: ServerItem, muted: Bool, container: AppContainer) {
        if currentItemId == item.id, currentTask != nil { return }
        currentTask?.cancel()
        stopInternal()
        cancelIdleTeardown()
        currentMuted = muted
        pendingItemId = item.id
        currentTask = Task { await startPreview(for: item, container: container) }
    }

    func stopIfCurrent(itemId: String) {
        if pendingItemId == itemId {
            pendingItemId = nil
            currentTask?.cancel()
            currentTask = nil
            return
        }
        guard currentItemId == itemId else { return }
        stop()
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        stopInternal()
    }

    // MARK: - Private helpers

    private func stopInternal() {
        loopTask?.cancel()
        loopTask = nil
        pendingItemId = nil
        currentStreamUrl = nil
        currentSeekPosition = 0
        currentPlayCount = 0
        currentItemId = nil
        isVisible = false
        player?.stop()
        scheduleIdleTeardown()
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
        let p = ensurePlayer()
        p.configureDynamicRangeIntent(contentRange: .sdr, sinkIsHdrCapable: false)
        p.setMuted(currentMuted)
        scheduleLoopRestart()
        await p.play(streamUrl: url.absoluteString, startPosition: currentSeekPosition)
    }

    // MARK: - Preview startup

    private func startPreview(for item: ServerItem, container: AppContainer) async {
        do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }

        do {
            guard let server = container.serverRepository.currentServer.value else { return }
            let client = container.serverClientFactory.client(for: server)

            guard let episode = try await resolvePreviewEpisode(item: item, client: client) else { return }
            guard !Task.isCancelled else { return }

            async let seekPositionTask = determineSeekPosition(for: episode, client: client)
            async let urlTask = getStreamUrl(for: episode, client: client)

            let seekPosition = await seekPositionTask
            let url = try await urlTask
            guard !Task.isCancelled else { return }

            currentStreamUrl = url
            currentSeekPosition = seekPosition
            currentPlayCount = 1
            currentItemId = item.id
            pendingItemId = nil

            let p = ensurePlayer()
            p.configureDynamicRangeIntent(contentRange: .sdr, sinkIsHdrCapable: false)
            p.setMuted(currentMuted)
            scheduleLoopRestart()
            await p.play(streamUrl: url.absoluteString, startPosition: seekPosition)

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
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: false,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true
        )
        let playbackResult = try await client.playbackApi.getPlaybackInfo(itemId: episode.id, request: request)

        guard let mediaSource = playbackResult.mediaSources.first else {
            throw NSError(domain: "PreviewPlayer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No media source available"])
        }

        let rawContainer = mediaSource.container ?? "mp4"
        let container = rawContainer.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "mp4"
        let playSessionId = playbackResult.playSessionId ?? ""
        let params = StreamParams(
            userId: client.userId ?? "",
            mediaSourceId: mediaSource.id,
            playSessionId: playSessionId,
            liveStreamId: mediaSource.liveStreamId,
            isLiveTv: false,
            deviceId: AppConstants.deviceId,
            container: container,
            audioStreamIndex: mediaSource.defaultAudioStreamIndex,
            subtitleStreamIndex: nil,
            maxStreamingBitrate: nil,
            startTimeTicks: nil
        )
        let urlString = client.playbackApi.getVideoStreamUrl(itemId: episode.id, params: params)
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "PreviewPlayer", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "No playable preview stream available"])
        }
        return url
    }
}
