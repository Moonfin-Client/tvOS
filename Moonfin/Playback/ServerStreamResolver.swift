import Foundation

final class ServerStreamResolver: StreamResolver {
    private let client: MediaServerClient

    private lazy var deviceId: String = AppConstants.deviceId

    private var lastResolvedItemId: String?
    private var lastResolvedSourceId: String?
    private var lastResolvedStream: StreamInfo?

    init(client: MediaServerClient) {
        self.client = client
    }

    func resolve(
        item: ServerItem,
        mediaSourceId: String?,
        maxBitrate: Int64?,
        maxAudioChannels: Int?,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        startTimeTicks: Int64?
    ) async throws -> StreamInfo {
        if let cached = lastResolvedStream,
           lastResolvedItemId == item.id,
           lastResolvedSourceId == mediaSourceId {
            clearCache()
            return cached
        }

        guard let userId = client.userId else {
            throw StreamResolverError.missingUserId
        }

        let isLiveTv = item.type == .liveTvChannel

        let request = PlaybackInfoRequest(
            userId: userId,
            mediaSourceId: mediaSourceId,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxStreamingBitrate: maxBitrate,
            maxAudioChannels: maxAudioChannels,
            startTimeTicks: startTimeTicks,
            autoOpenLiveStream: isLiveTv
        )

        let result: PlaybackInfoResult
        do {
            result = try await client.playbackApi.getPlaybackInfo(itemId: item.id, request: request)
        } catch {
            if isLiveTv {
                return buildLiveTvFallbackStream(item: item, userId: userId)
            }
            throw error
        }

        if let errorCode = result.errorCode {
            if isLiveTv {
                return buildLiveTvFallbackStream(item: item, userId: userId)
            }
            throw StreamResolverError.playbackError(errorCode)
        }

        let sources = result.mediaSources
        guard !sources.isEmpty else {
            if isLiveTv {
                return buildLiveTvFallbackStream(item: item, userId: userId)
            }
            throw StreamResolverError.noMediaSources
        }

        let source = sources.first { $0.id == mediaSourceId } ?? sources[0]

        let playSessionId = result.playSessionId ?? ""
        let audioStreams = source.mediaStreams.filter { $0.type == .audio }
        let subtitleStreams = source.mediaStreams.filter { $0.type == .subtitle }
        let container = source.container ?? "ts"

        let streamInfo: StreamInfo

        if source.supportsDirectPlay && !isLiveTv {
            let params = StreamParams(
                userId: userId,
                mediaSourceId: source.id,
                playSessionId: playSessionId,
                deviceId: deviceId,
                container: container,
                audioStreamIndex: audioStreamIndex ?? source.defaultAudioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex ?? source.defaultSubtitleStreamIndex,
                maxStreamingBitrate: nil,
                startTimeTicks: startTimeTicks
            )

            let isVideo = item.mediaType == .video
            let url = isVideo
                ? client.playbackApi.getVideoStreamUrl(itemId: item.id, params: params)
                : client.playbackApi.getAudioStreamUrl(itemId: item.id, params: params)

            streamInfo = StreamInfo(
                url: url,
                playSessionId: playSessionId,
                mediaSourceId: source.id,
                playMethod: .directPlay,
                container: container,
                audioStreams: audioStreams,
                subtitleStreams: subtitleStreams,
                defaultAudioStreamIndex: source.defaultAudioStreamIndex,
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex
            )
        } else if let transcodingUrl = source.transcodingUrl {
            let method: PlayMethod = source.supportsDirectStream ? .directStream : .transcode
            let url = buildTranscodingUrl(transcodingUrl)
            streamInfo = StreamInfo(
                url: url,
                playSessionId: playSessionId,
                mediaSourceId: source.id,
                playMethod: method,
                container: container,
                audioStreams: audioStreams,
                subtitleStreams: subtitleStreams,
                defaultAudioStreamIndex: source.defaultAudioStreamIndex,
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex
            )
        } else if isLiveTv {
            let params = StreamParams(
                userId: userId,
                mediaSourceId: source.id,
                playSessionId: playSessionId,
                deviceId: deviceId,
                container: container,
                audioStreamIndex: audioStreamIndex ?? source.defaultAudioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex ?? source.defaultSubtitleStreamIndex,
                maxStreamingBitrate: nil,
                startTimeTicks: nil
            )

            let url = client.playbackApi.getVideoStreamUrl(itemId: item.id, params: params)
            streamInfo = StreamInfo(
                url: url,
                playSessionId: playSessionId,
                mediaSourceId: source.id,
                playMethod: .directPlay,
                container: container,
                audioStreams: audioStreams,
                subtitleStreams: subtitleStreams,
                defaultAudioStreamIndex: source.defaultAudioStreamIndex,
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex
            )
        } else {
            throw StreamResolverError.noCompatibleStream
        }

        lastResolvedItemId = item.id
        lastResolvedSourceId = mediaSourceId
        lastResolvedStream = streamInfo

        return streamInfo
    }

    func clearCache() {
        lastResolvedItemId = nil
        lastResolvedSourceId = nil
        lastResolvedStream = nil
    }

    private func buildLiveTvFallbackStream(item: ServerItem, userId: String) -> StreamInfo {
        let params = StreamParams(
            userId: userId,
            mediaSourceId: item.id,
            playSessionId: "",
            deviceId: deviceId,
            container: "ts",
            audioStreamIndex: nil,
            subtitleStreamIndex: nil,
            maxStreamingBitrate: nil,
            startTimeTicks: nil
        )

        let url = client.playbackApi.getVideoStreamUrl(itemId: item.id, params: params)
        return StreamInfo(
            url: url,
            playSessionId: "",
            mediaSourceId: "",
            playMethod: .directPlay,
            container: "ts",
            audioStreams: [],
            subtitleStreams: [],
            defaultAudioStreamIndex: nil,
            defaultSubtitleStreamIndex: nil
        )
    }

    private func buildTranscodingUrl(_ path: String) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            return path
        }
        if path.hasPrefix("http") { return path }
        return "\(base)\(path)"
    }
}
