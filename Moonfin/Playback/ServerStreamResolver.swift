import Foundation

final class ServerStreamResolver: StreamResolver {
    private let client: MediaServerClient
    private let requestedBackend: PlaybackBackendDirective

    private lazy var deviceId: String = AppConstants.deviceId

    private var lastResolvedItemId: String?
    private var lastResolvedSourceId: String?
    private var lastResolvedStartTimeTicks: Int64?
    private var lastResolvedStream: StreamInfo?

    init(client: MediaServerClient, requestedBackend: PlaybackBackendDirective) {
        self.client = client
        self.requestedBackend = requestedBackend
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
              lastResolvedSourceId == mediaSourceId,
              lastResolvedStartTimeTicks == startTimeTicks {
            clearCache()
            return cached
        }

        guard let userId = client.userId else {
            throw StreamResolverError.missingUserId
        }

        let isLiveTv = item.type == .liveTvChannel

        let shouldRetryLyricsPath = item.mediaType == .audio && item.hasLyrics == true
        var subtitleCandidates: [Int?] = [subtitleStreamIndex]
        if shouldRetryLyricsPath {
            if subtitleStreamIndex != -1 {
                subtitleCandidates.append(-1)
            }
            if subtitleStreamIndex != nil {
                subtitleCandidates.append(nil)
            }
        }

        var result: PlaybackInfoResult?
        var lastError: Error?
        for (attempt, candidateSubtitleIndex) in subtitleCandidates.enumerated() {
            let request = PlaybackInfoRequest(
                userId: userId,
                mediaSourceId: mediaSourceId,
                audioStreamIndex: audioStreamIndex,
                subtitleStreamIndex: candidateSubtitleIndex,
                maxStreamingBitrate: maxBitrate,
                maxAudioChannels: maxAudioChannels,
                startTimeTicks: startTimeTicks,
                autoOpenLiveStream: isLiveTv
            )

            do {
                let attemptResult = try await client.playbackApi.getPlaybackInfo(itemId: item.id, request: request)
                if let errorCode = attemptResult.errorCode {
                    if shouldRetryLyricsPath && attempt < subtitleCandidates.count - 1 {
                        continue
                    }
                    if isLiveTv {
                        return buildLiveTvFallbackStream(item: item, userId: userId)
                    }
                    throw StreamResolverError.playbackError(errorCode)
                }

                result = attemptResult
                break
            } catch {
                lastError = error
                if shouldRetryLyricsPath && attempt < subtitleCandidates.count - 1 {
                    continue
                }
                if isLiveTv {
                    return buildLiveTvFallbackStream(item: item, userId: userId)
                }
                throw error
            }
        }

        guard let result else {
            if isLiveTv {
                return buildLiveTvFallbackStream(item: item, userId: userId)
            }
            throw lastError ?? StreamResolverError.noCompatibleStream
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
        let videoStream = source.mediaStreams.first { $0.type == .video }
        let selectedAudioIndex = audioStreamIndex ?? source.defaultAudioStreamIndex
        let selectedAudioStream = audioStreams.first { $0.index == selectedAudioIndex } ?? audioStreams.first
        let container = normalizedContainer(source.container, isAudio: item.mediaType == .audio)

        let audioPolicy = AudioCapabilityPolicy.decide(
            requestedBackend: requestedBackend,
            selectedAudioStream: selectedAudioStream,
            canTranscode: source.transcodingUrl != nil,
            maxAudioChannels: maxAudioChannels
        )

        let capabilities = await MainActor.run { VideoCapabilityDetector.current() }
        let dynamicRange = VideoDynamicRangePolicy.detectRange(videoStream: videoStream)
        let videoPolicy = VideoDynamicRangePolicy.decide(
            requestedBackend: requestedBackend,
            dynamicRange: dynamicRange,
            capabilities: capabilities,
            canTranscode: source.transcodingUrl != nil
        )

        let preferredBackend: PlaybackBackendDirective =
            (videoPolicy.backend == .tvvlcKit || audioPolicy.backend == .tvvlcKit) ? .tvvlcKit : .mpv
        let fallbackReason = audioPolicy.reason ?? videoPolicy.reason
        let combinedDiagnostics = videoPolicy.diagnostics + audioPolicy.diagnostics

        let forceTranscodeReasons: Set<String> = [
            "hdr10_requires_transcode",
            "hlg_requires_transcode",
            "hdr10_plus_requires_transcode",
            "dolby_vision_requires_transcode",
            "downmix_to_stereo_requires_transcode",
            "truehd_requires_transcode",
            "dts_requires_transcode",
            "unsupported_audio_codec_requires_transcode"
        ]
        let shouldForceTranscodeForRange =
            audioPolicy.requiresTranscode ||
            (fallbackReason.map { forceTranscodeReasons.contains($0) } ?? false)

        let streamInfo: StreamInfo

        let preferTranscodedAudioForLyrics = item.mediaType == .audio && item.hasLyrics == true

        if source.supportsDirectPlay && !(preferTranscodedAudioForLyrics && source.transcodingUrl != nil) && !shouldForceTranscodeForRange {
            let params = StreamParams(
                userId: userId,
                mediaSourceId: source.id,
                playSessionId: playSessionId,
                liveStreamId: source.liveStreamId,
                isLiveTv: isLiveTv,
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
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
                dynamicRange: dynamicRange,
                preferredBackend: preferredBackend,
                fallbackReason: fallbackReason,
                diagnostics: combinedDiagnostics
            )
        } else if let transcodingUrl = source.transcodingUrl {
            let method: PlayMethod = source.supportsDirectStream ? .directStream : .transcode
            var url = buildTranscodingUrl(transcodingUrl)
            if isLiveTv, let liveStreamId = source.liveStreamId, !liveStreamId.isEmpty {
                let separator = url.contains("?") ? "&" : "?"
                url += "\(separator)LiveStreamId=\(liveStreamId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? liveStreamId)"
            }
            streamInfo = StreamInfo(
                url: url,
                playSessionId: playSessionId,
                mediaSourceId: source.id,
                playMethod: method,
                container: container,
                audioStreams: audioStreams,
                subtitleStreams: subtitleStreams,
                defaultAudioStreamIndex: source.defaultAudioStreamIndex,
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
                dynamicRange: dynamicRange,
                preferredBackend: .mpv,
                fallbackReason: fallbackReason,
                diagnostics: combinedDiagnostics + [isLiveTv ? "resolved_via=livetv_transcode" : "resolved_via=transcode"]
            )
        } else if isLiveTv {
            let params = StreamParams(
                userId: userId,
                mediaSourceId: source.id,
                playSessionId: playSessionId,
                liveStreamId: source.liveStreamId,
                isLiveTv: true,
                deviceId: deviceId,
                container: container,
                audioStreamIndex: audioStreamIndex ?? source.defaultAudioStreamIndex,
                subtitleStreamIndex: subtitleStreamIndex ?? source.defaultSubtitleStreamIndex,
                maxStreamingBitrate: nil,
                startTimeTicks: nil
            )

            let url = client.playbackApi.getVideoStreamUrl(itemId: item.id, params: params)
            let liveTvPlayMethod: PlayMethod = source.supportsDirectStream ? .directStream : .directPlay
            streamInfo = StreamInfo(
                url: url,
                playSessionId: playSessionId,
                mediaSourceId: source.id,
                playMethod: liveTvPlayMethod,
                container: container,
                audioStreams: audioStreams,
                subtitleStreams: subtitleStreams,
                defaultAudioStreamIndex: source.defaultAudioStreamIndex,
                defaultSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
                dynamicRange: .unknown,
                preferredBackend: requestedBackend,
                fallbackReason: nil,
                diagnostics: ["resolved_via=livetv"]
            )
        } else {
            throw StreamResolverError.noCompatibleStream
        }

        lastResolvedItemId = item.id
        lastResolvedSourceId = mediaSourceId
        lastResolvedStartTimeTicks = startTimeTicks
        lastResolvedStream = streamInfo

        return streamInfo
    }

    func clearCache() {
        lastResolvedItemId = nil
        lastResolvedSourceId = nil
        lastResolvedStartTimeTicks = nil
        lastResolvedStream = nil
    }

    private func buildLiveTvFallbackStream(item: ServerItem, userId: String) -> StreamInfo {
        let params = StreamParams(
            userId: userId,
            mediaSourceId: "",
            playSessionId: "",
            liveStreamId: nil,
            isLiveTv: true,
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
            defaultSubtitleStreamIndex: nil,
            dynamicRange: .unknown,
            preferredBackend: requestedBackend,
            fallbackReason: nil,
            diagnostics: ["resolved_via=livetv_fallback"]
        )
    }

    private func buildTranscodingUrl(_ path: String) -> String {
        let absolutePath: String
        if path.hasPrefix("http") {
            absolutePath = path
        } else {
            guard let base = client.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
                return path
            }
            absolutePath = "\(base)\(path)"
        }

        guard let token = client.accessToken, !token.isEmpty else {
            return absolutePath
        }

        guard var components = URLComponents(string: absolutePath) else {
            return absolutePath
        }
        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "api_key" }) {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
            components.queryItems = queryItems
        }
        return components.url?.absoluteString ?? absolutePath
    }

    private func normalizedContainer(_ rawContainer: String?, isAudio: Bool) -> String {
        let fallback = isAudio ? "mp3" : "ts"
        guard let rawContainer else { return fallback }
        let first = rawContainer
            .split(separator: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first, !first.isEmpty else { return fallback }
        return first
    }
}
