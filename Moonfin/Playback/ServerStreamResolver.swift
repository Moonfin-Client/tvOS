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

        let request = PlaybackInfoRequest(
            userId: userId,
            mediaSourceId: mediaSourceId,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            maxStreamingBitrate: maxBitrate,
            startTimeTicks: startTimeTicks
        )

        let result = try await client.playbackApi.getPlaybackInfo(itemId: item.id, request: request)

        if let errorCode = result.errorCode {
            throw StreamResolverError.playbackError(errorCode)
        }

        let sources = result.mediaSources
        guard !sources.isEmpty else {
            throw StreamResolverError.noMediaSources
        }

        let source = sources.first { $0.id == mediaSourceId } ?? sources[0]

        let playSessionId = result.playSessionId ?? ""
        let audioStreams = source.mediaStreams.filter { $0.type == .audio }
        let subtitleStreams = source.mediaStreams.filter { $0.type == .subtitle }
        let container = source.container ?? "ts"

        let streamInfo: StreamInfo

        if source.supportsDirectPlay {
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
            let method: PlayMethod
            if source.supportsDirectStream {
                method = .directStream
            } else if source.supportsTranscoding {
                method = .transcode
            } else {
                throw StreamResolverError.noCompatibleStream
            }

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

    private func buildTranscodingUrl(_ path: String) -> String {
        guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            return path
        }
        if path.hasPrefix("http") { return path }
        return "\(base)\(path)"
    }
}
