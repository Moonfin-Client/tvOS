import Foundation

enum VideoDynamicRange: String {
    case sdr
    case hdr10
    case hlg
    case hdr10Plus
    case dolbyVision
    case unknown
}

enum PlaybackBackendDirective: String {
    case mpv
    case native
}

struct QueueEntry: Identifiable, Equatable {
    let id: String
    let item: ServerItem
    let mediaSourceId: String?
    var startPositionTicks: Int64
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool {
        lhs.id == rhs.id
    }
}

struct StreamInfo {
    let url: String
    let playSessionId: String
    let mediaSourceId: String
    let playMethod: PlayMethod
    let container: String
    let audioStreams: [ServerMediaStream]
    let subtitleStreams: [ServerMediaStream]
    let videoStream: ServerMediaStream?
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
    let dynamicRange: VideoDynamicRange
    let dvProfile: Int?
    let dvLevel: Int?
    let dvBlSignalCompatibilityId: Int?
    let preferredBackend: PlaybackBackendDirective
    let fallbackReason: String?
    let diagnostics: [String]
}

enum StreamResolverError: Error {
    case noMediaSources
    case noCompatibleStream
    case playbackError(PlaybackErrorCode)
    case missingUserId
}

protocol StreamResolver {
    func resolve(
        item: ServerItem,
        mediaSourceId: String?,
        maxBitrate: Int64?,
        maxAudioChannels: Int?,
        atmosPassthroughEnabled: Bool,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        startTimeTicks: Int64?
    ) async throws -> StreamInfo
}
