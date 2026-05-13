import Foundation
import Darwin
#if canImport(Libavformat)
import Libavformat
#endif
#if canImport(Libavutil)
import Libavutil
#endif
#if canImport(Libavcodec)
import Libavcodec
#endif

struct FFmpegAvailability {
    static let isAvailable: Bool = {
#if canImport(Libavformat)
        return true
#else
        return false
#endif
    }()

    static let abiCompatible: Bool = {
#if canImport(Libavcodec)
        let ver = avcodec_version()
        let major = ver >> 16
        return major == 61
#else
        return false
#endif
    }()
}

struct DVConfiguration {
    let versionMajor: UInt8
    let versionMinor: UInt8
    let profile: UInt8
    let level: UInt8
    let rpuPresent: Bool
    let elPresent: Bool
    let blPresent: Bool
    let blSignalCompatibilityId: UInt8
    let mdCompression: UInt8

    var isProfile5: Bool { profile == 5 }
    var isProfile7: Bool { profile == 7 }
    var isProfile8: Bool { profile == 8 }
    var hasHDR10Base: Bool { blSignalCompatibilityId == 1 || blSignalCompatibilityId == 4 }
}

struct FFSideData {
    let type: Int32
    let data: Data
}

struct FFStreamInfo {
    let index: Int32
    let type: FFStreamType
    let codecId: UInt32
    let width: Int32
    let height: Int32
    let frameRate: Double
    let sampleRate: Int32
    let channels: Int32
    let channelLayout: UInt64
    let bitDepth: Int32
    let extradata: Data?
    let language: String?
    let title: String?
    let isDefault: Bool
    let codecTag: UInt32
    let dvConfig: DVConfiguration?
    let colorPrimaries: Int32
    let colorTransfer: Int32
    let colorSpace: Int32
}

enum FFStreamType {
    case video
    case audio
    case subtitle
    case unknown
}

enum FFReadResult {
    case packet(FFPacket)
    case eof
    case wouldBlock
    case error(Int32)
}

final class FFPacket {
    let streamIndex: Int32
    let pts: Int64
    let dts: Int64
    let duration: Int64
    let size: Int32
    let isKeyframe: Bool
    let sideData: [FFSideData]
    let rawPacket: UnsafeMutableRawPointer

    var data: UnsafeRawPointer? {
        guard size > 0 else { return nil }
        let pktPtr = rawPacket.assumingMemoryBound(to: FFDemuxer.RawAVPacket.self)
        return UnsafeRawPointer(pktPtr.pointee.data)
    }

    init(rawPacket: UnsafeMutableRawPointer) {
        self.rawPacket = rawPacket
        let pkt = rawPacket.assumingMemoryBound(to: FFDemuxer.RawAVPacket.self).pointee
        self.streamIndex = pkt.stream_index
        self.pts = pkt.pts
        self.dts = pkt.dts
        self.duration = pkt.duration
        self.size = pkt.size
        self.isKeyframe = (pkt.flags & 0x0001) != 0
        self.sideData = Self.extractSideData(from: pkt)
    }

    deinit {
        FFDemuxer.freePacket(rawPacket)
    }

    private static func extractSideData(from pkt: FFDemuxer.RawAVPacket) -> [FFSideData] {
        guard let sdPtr = pkt.side_data, pkt.side_data_elems > 0 else { return [] }
        // AVPacketSideData: { uint8_t *data (8), size_t size (8), int type (4), pad (4) } = 24 bytes
        let stride = 24
        var result: [FFSideData] = []
        for i in 0..<Int(pkt.side_data_elems) {
            let entry = sdPtr.advanced(by: i * stride)
            let dataPtr = entry.assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self).pointee
            let size = entry.advanced(by: 8).assumingMemoryBound(to: Int.self).pointee
            let type = entry.advanced(by: 16).assumingMemoryBound(to: Int32.self).pointee
            if let dataPtr, size > 0 {
                result.append(FFSideData(type: type, data: Data(bytes: dataPtr, count: size)))
            }
        }
        return result
    }
}

final class FFDemuxer {

    // AVPacket layout (MPVKit 0.41 / FFmpeg 7.x ABI)
    struct RawAVPacket {
        let buf: UnsafeMutableRawPointer?
        let pts: Int64
        let dts: Int64
        let data: UnsafeMutablePointer<UInt8>?
        let size: Int32
        let stream_index: Int32
        let flags: Int32
        let side_data: UnsafeMutableRawPointer?
        let side_data_elems: Int32
        let duration: Int64
        let pos: Int64
        let opaque: UnsafeMutableRawPointer?
        let opaque_ref: UnsafeMutableRawPointer?
        let time_base_num: Int32
        let time_base_den: Int32
    }

    private struct RawAVRational {
        let num: Int32
        let den: Int32
    }

    // AVCodecParameters layout through height (0x4C).
    // Extended fields accessed via raw offsets below.
    private struct RawAVCodecParameters {
        let codec_type: Int32
        let codec_id: UInt32
        let codec_tag: UInt32
        let extradata: UnsafeMutablePointer<UInt8>?
        let extradata_size: Int32
        let coded_side_data: UnsafeMutableRawPointer?
        let nb_coded_side_data: Int32
        let format: Int32
        let bit_rate: Int64
        let bits_per_coded_sample: Int32
        let bits_per_raw_sample: Int32
        let profile: Int32
        let level: Int32
        let width: Int32
        let height: Int32
    }

    // AVCodecParameters extended offsets (beyond RawAVCodecParameters binding)
    // 0x50: sample_aspect_ratio (AVRational, 8 bytes)
    // 0x58: framerate (AVRational, 8 bytes)
    // 0x60: field_order (int32)
    // 0x64: color_range (int32)
    // 0x68: color_primaries (int32)
    // 0x6C: color_trc (int32)
    // 0x70: color_space (int32)
    // 0x74: chroma_location (int32)
    // 0x78: video_delay (int32)
    // 0x7C: padding (4 bytes)
    // 0x80: ch_layout.order (int32)
    // 0x84: ch_layout.nb_channels (int32)
    // 0x88: ch_layout.u.mask (uint64)
    // 0x90: ch_layout.opaque (pointer, 8 bytes)
    // 0x98: sample_rate (int32)

    private struct RawAVDOVIRecord {
        let dv_version_major: UInt8
        let dv_version_minor: UInt8
        let dv_profile: UInt8
        let dv_level: UInt8
        let rpu_present_flag: UInt8
        let el_present_flag: UInt8
        let bl_present_flag: UInt8
        let dv_bl_signal_compatibility_id: UInt8
        let dv_md_compression: UInt8
    }

    private var formatCtx: UnsafeMutablePointer<AVFormatContext>?
    private(set) var streams: [FFStreamInfo] = []
    private(set) var videoStreamIndex: Int32 = -1
    private(set) var audioStreamIndex: Int32 = -1
    private(set) var subtitleStreamIndexes: [Int32] = []
    private(set) var dvConfig: DVConfiguration?
    private(set) var dvELStreamIndex: Int32 = -1
    private(set) var duration: TimeInterval = 0
    private(set) var url: String?
    private var opened = false

    var isDualTrackDV: Bool {
        dvConfig?.elPresent == true && dvELStreamIndex >= 0
    }

    private static let AVMEDIA_TYPE_VIDEO: Int32 = 0
    private static let AVMEDIA_TYPE_AUDIO: Int32 = 1
    private static let AVMEDIA_TYPE_SUBTITLE: Int32 = 3
    private static let AVSEEK_FLAG_BACKWARD: Int32 = 1
    private static let AV_TIME_BASE: Int64 = 1_000_000
    private static let AV_DISPOSITION_DEFAULT: Int32 = 0x0001
    private static let AV_PKT_DATA_DOVI_CONF: Int32 = 23
    private static let AVERROR_EOF: Int32 = {
        let a = Int32(0x45), b = Int32(0x4F), c = Int32(0x46), d = Int32(0x20)
        return -(a | (b << 8) | (c << 16) | (d << 24))
    }()
    private static let AVERROR_EAGAIN: Int32 = -35

    init() {}

    deinit {
        close()
    }

    var isReady: Bool {
        FFmpegAvailability.isAvailable && FFmpegAvailability.abiCompatible
    }

    func open(url: String) -> Bool {
#if canImport(Libavformat)
        close()

        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let result = url.withCString { cUrl in
            avformat_open_input(&ctx, cUrl, nil, nil)
        }
        guard result >= 0, let ctx else { return false }
        formatCtx = ctx
        self.url = url

        guard avformat_find_stream_info(ctx, nil) >= 0 else {
            avformat_close_input(&formatCtx)
            formatCtx = nil
            return false
        }

        opened = true
        readDuration()
        resolveStreams()
        return true
#else
        return false
#endif
    }

    func readPacket() -> FFReadResult {
#if canImport(Libavformat)
        guard opened, let ctx = formatCtx else { return .error(-1) }
        guard let pkt = av_packet_alloc() else { return .error(-1) }

        let result = av_read_frame(ctx, pkt)
        if result >= 0 {
            return .packet(FFPacket(rawPacket: UnsafeMutableRawPointer(pkt)))
        }
        var pktPtr: UnsafeMutablePointer<AVPacket>? = pkt
        av_packet_free(&pktPtr)
        if result == Self.AVERROR_EOF {
            return .eof
        }
        if result == Self.AVERROR_EAGAIN {
            return .wouldBlock
        }
        return .error(result)
#else
        return .error(-1)
#endif
    }

    func seek(to seconds: TimeInterval) -> Bool {
#if canImport(Libavformat)
        guard opened, let ctx = formatCtx else { return false }
        let ts = Int64(seconds * Double(Self.AV_TIME_BASE))
        return av_seek_frame(ctx, -1, ts, Self.AVSEEK_FLAG_BACKWARD) >= 0
#else
        return false
#endif
    }

    func close() {
        guard opened else { return }
        opened = false
        streams = []
        videoStreamIndex = -1
        audioStreamIndex = -1
        subtitleStreamIndexes = []
        dvConfig = nil
        dvELStreamIndex = -1
        duration = 0
        url = nil
#if canImport(Libavformat)
        if formatCtx != nil {
            avformat_close_input(&formatCtx)
            formatCtx = nil
        }
#endif
    }

    static func freePacket(_ rawPacket: UnsafeMutableRawPointer) {
#if canImport(Libavcodec)
        var pkt: UnsafeMutablePointer<AVPacket>? = rawPacket.assumingMemoryBound(to: AVPacket.self)
        av_packet_free(&pkt)
#endif
    }

    func setDVConfigFromPacket(_ config: DVConfiguration) {
        if dvConfig == nil {
            dvConfig = config
        }
    }

    @discardableResult
    func seedDVConfigFromServer(profile: Int?, level: Int?, blSignalCompatibilityId: Int?) -> Bool {
        guard dvConfig == nil else { return false }
        guard let profile, profile > 0 else { return false }

        let clampedProfile = UInt8(clamping: profile)
        let clampedLevel = UInt8(clamping: max(level ?? 1, 1))
        let defaultCompatibility = profile == 8 ? 1 : 0
        let compatibility = UInt8(clamping: max(blSignalCompatibilityId ?? defaultCompatibility, 0))

        dvConfig = DVConfiguration(
            versionMajor: 1,
            versionMinor: 0,
            profile: clampedProfile,
            level: clampedLevel,
            rpuPresent: true,
            elPresent: false,
            blPresent: true,
            blSignalCompatibilityId: compatibility,
            mdCompression: 0
        )
        return true
    }

    func codecpar(forStreamIndex index: Int32) -> UnsafeMutableRawPointer? {
        guard let ctx = formatCtx, index >= 0 else { return nil }
        let ctxRaw = UnsafeMutableRawPointer(ctx)
        let count = Int(ctxRaw.advanced(by: 0x24).assumingMemoryBound(to: UInt32.self).pointee)
        guard Int(index) < count else { return nil }
        let streamsArray = ctxRaw.advanced(by: 0x28)
            .assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer>.self).pointee
        let stream = streamsArray[Int(index)]
        return stream.advanced(by: 0x10)
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee
    }

    func timeBase(forStreamIndex index: Int32) -> (num: Int32, den: Int32) {
        guard let ctx = formatCtx, index >= 0 else { return (0, 1) }
        let ctxRaw = UnsafeMutableRawPointer(ctx)
        let count = Int(ctxRaw.advanced(by: 0x24).assumingMemoryBound(to: UInt32.self).pointee)
        guard Int(index) < count else { return (0, 1) }
        let streamsArray = ctxRaw.advanced(by: 0x28)
            .assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer>.self).pointee
        let stream = streamsArray[Int(index)]
        let num = stream.advanced(by: 0x20).assumingMemoryBound(to: Int32.self).pointee
        let den = stream.advanced(by: 0x24).assumingMemoryBound(to: Int32.self).pointee
        return (num, den > 0 ? den : 1)
    }

    // MARK: - AVFormatContext offsets (MPVKit 0.41 / FFmpeg 7.x)
    // 0x24: nb_streams (uint32)
    // 0x28: streams (AVStream**)
    // 0x40: duration (int64)

    private func readDuration() {
        guard let ctx = formatCtx else { return }
        let ctxRaw = UnsafeMutableRawPointer(ctx)
        let durationUs = ctxRaw.advanced(by: 0x40).assumingMemoryBound(to: Int64.self).pointee
        if durationUs > 0 {
            duration = TimeInterval(durationUs) / Double(Self.AV_TIME_BASE)
        }
    }

    private func resolveStreams() {
        guard let ctx = formatCtx else { return }
        let ctxRaw = UnsafeMutableRawPointer(ctx)

        let count = Int(ctxRaw.advanced(by: 0x24).assumingMemoryBound(to: UInt32.self).pointee)
        let streamsArray = ctxRaw.advanced(by: 0x28)
            .assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutableRawPointer>.self).pointee

        for i in 0..<count {
            let stream = streamsArray[i]
            let info = parseStream(stream, index: Int32(i))
            streams.append(info)
        }

#if canImport(Libavformat)
        let videoType = AVMediaType(0)  // AVMEDIA_TYPE_VIDEO
        let audioType = AVMediaType(1)  // AVMEDIA_TYPE_AUDIO
        let bestVideo = av_find_best_stream(ctx, videoType, -1, -1, nil, 0)
        if bestVideo >= 0 {
            videoStreamIndex = bestVideo
        }
        let related = bestVideo >= 0 ? bestVideo : Int32(-1)
        let bestAudio = av_find_best_stream(ctx, audioType, -1, related, nil, 0)
        if bestAudio >= 0 {
            audioStreamIndex = bestAudio
        }
#endif

        if videoStreamIndex < 0 {
            videoStreamIndex = streams.first(where: { $0.type == .video })?.index ?? -1
        }
        if audioStreamIndex < 0 {
            audioStreamIndex = streams.first(where: { $0.type == .audio })?.index ?? -1
        }

        subtitleStreamIndexes = streams.filter { $0.type == .subtitle }.map(\.index)

        if videoStreamIndex >= 0 {
            dvConfig = streams[Int(videoStreamIndex)].dvConfig
        }

        if dvConfig == nil, videoStreamIndex >= 0 {
            if let dvTrack = streams.first(where: { $0.type == .video && $0.dvConfig != nil }) {
                videoStreamIndex = dvTrack.index
                dvConfig = dvTrack.dvConfig
            }
        }

        if let dvConfig, dvConfig.elPresent {
            for stream in streams where stream.type == .video && stream.index != videoStreamIndex {
                dvELStreamIndex = stream.index
                break
            }
        }
    }

    // MARK: - AVStream offsets (MPVKit 0.41 / FFmpeg 7.x, no FF_API_AVSTREAM_SIDE_DATA)
    // 0x00: av_class (pointer, 8)
    // 0x08: index (int, 4)
    // 0x0C: id (int, 4)
    // 0x10: codecpar (pointer, 8)
    // 0x18: priv_data (pointer, 8)
    // 0x20: time_base (AVRational, 8)
    // 0x28: start_time (int64, 8)
    // 0x30: duration (int64, 8)
    // 0x38: nb_frames (int64, 8)
    // 0x40: disposition (int, 4)
    // 0x44: discard (int, 4)
    // 0x48: sample_aspect_ratio (AVRational, 8)
    // 0x50: metadata (pointer, 8)
    // 0x58: avg_frame_rate (AVRational, 8)
    // 0x60: attached_pic (AVPacket, 0x68 bytes)
    // 0xC8: event_flags (int, 4)
    // 0xCC: r_frame_rate (AVRational, 8)
    // 0xD4: pts_wrap_bits (int, 4)

    private func parseStream(_ stream: UnsafeMutableRawPointer, index: Int32) -> FFStreamInfo {
        let codecpar = stream.advanced(by: 0x10)
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee
        let disposition = stream.advanced(by: 0x40)
            .assumingMemoryBound(to: Int32.self).pointee
        let avgFR = stream.advanced(by: 0x58)
            .assumingMemoryBound(to: RawAVRational.self).pointee
        let metadata = stream.advanced(by: 0x50)
            .assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee
        let rFR = stream.advanced(by: 0xCC)
            .assumingMemoryBound(to: RawAVRational.self).pointee

        let frameRate: Double
        if avgFR.den > 0, avgFR.num > 0 {
            frameRate = Double(avgFR.num) / Double(avgFR.den)
        } else if rFR.den > 0, rFR.num > 0 {
            frameRate = Double(rFR.num) / Double(rFR.den)
        } else {
            frameRate = 0
        }

        let isDefault = (disposition & Self.AV_DISPOSITION_DEFAULT) != 0
        let language = dictGet(metadata, key: "language")
        let title = dictGet(metadata, key: "title")

        var type: FFStreamType = .unknown
        var codecId: UInt32 = 0
        var codecTag: UInt32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        var sampleRate: Int32 = 0
        var channels: Int32 = 0
        var channelLayout: UInt64 = 0
        var bitDepth: Int32 = 0
        var extradata: Data?
        var colorPrimaries: Int32 = 0
        var colorTransfer: Int32 = 0
        var colorSpace: Int32 = 0

        if let codecpar {
            let par = codecpar.assumingMemoryBound(to: RawAVCodecParameters.self).pointee
            codecId = par.codec_id
            codecTag = par.codec_tag
            width = par.width
            height = par.height
            bitDepth = par.bits_per_raw_sample > 0 ? par.bits_per_raw_sample : par.bits_per_coded_sample

            switch par.codec_type {
            case Self.AVMEDIA_TYPE_VIDEO:
                type = .video
                colorPrimaries = codecpar.advanced(by: 0x68).assumingMemoryBound(to: Int32.self).pointee
                colorTransfer = codecpar.advanced(by: 0x6C).assumingMemoryBound(to: Int32.self).pointee
                colorSpace = codecpar.advanced(by: 0x70).assumingMemoryBound(to: Int32.self).pointee
            case Self.AVMEDIA_TYPE_AUDIO:
                type = .audio
                channels = codecpar.advanced(by: 0x84).assumingMemoryBound(to: Int32.self).pointee
                channelLayout = codecpar.advanced(by: 0x88).assumingMemoryBound(to: UInt64.self).pointee
                sampleRate = codecpar.advanced(by: 0x98).assumingMemoryBound(to: Int32.self).pointee
            case Self.AVMEDIA_TYPE_SUBTITLE:
                type = .subtitle
            default:
                type = .unknown
            }

            if let extPtr = par.extradata, par.extradata_size > 0 {
                extradata = Data(bytes: extPtr, count: Int(par.extradata_size))
            }
        }

        let dv = extractDVConfig(codecpar: codecpar)

        return FFStreamInfo(
            index: index,
            type: type,
            codecId: codecId,
            width: width,
            height: height,
            frameRate: frameRate,
            sampleRate: sampleRate,
            channels: channels,
            channelLayout: channelLayout,
            bitDepth: bitDepth,
            extradata: extradata,
            language: language,
            title: title,
            isDefault: isDefault,
            codecTag: codecTag,
            dvConfig: dv,
            colorPrimaries: colorPrimaries,
            colorTransfer: colorTransfer,
            colorSpace: colorSpace
        )
    }

    // Reads DOVI config from AVCodecParameters.coded_side_data
    // (av_stream_get_side_data was removed in this FFmpeg build)
    private func extractDVConfig(codecpar: UnsafeMutableRawPointer?) -> DVConfiguration? {
        guard let codecpar else { return nil }
        let par = codecpar.assumingMemoryBound(to: RawAVCodecParameters.self).pointee
        guard let sideDataArray = par.coded_side_data, par.nb_coded_side_data > 0 else { return nil }

        let stride = 24
        for i in 0..<Int(par.nb_coded_side_data) {
            let entry = UnsafeRawPointer(sideDataArray).advanced(by: i * stride)
            let type = entry.advanced(by: 16).load(as: Int32.self)
            guard type == Self.AV_PKT_DATA_DOVI_CONF else { continue }

            let dataPtr = entry.load(as: UnsafePointer<UInt8>?.self)
            let size = entry.advanced(by: 8).load(as: Int.self)
            guard let dataPtr, size >= MemoryLayout<RawAVDOVIRecord>.size else { continue }

            let record = UnsafeRawPointer(dataPtr).assumingMemoryBound(to: RawAVDOVIRecord.self).pointee
            return DVConfiguration(
                versionMajor: record.dv_version_major,
                versionMinor: record.dv_version_minor,
                profile: record.dv_profile,
                level: record.dv_level,
                rpuPresent: record.rpu_present_flag != 0,
                elPresent: record.el_present_flag != 0,
                blPresent: record.bl_present_flag != 0,
                blSignalCompatibilityId: record.dv_bl_signal_compatibility_id,
                mdCompression: record.dv_md_compression
            )
        }
        return nil
    }

    private func dictGet(_ dict: UnsafeMutableRawPointer?, key: String) -> String? {
#if canImport(Libavutil)
        guard let dict else { return nil }
        guard let entry = key.withCString({ cKey in
            av_dict_get(OpaquePointer(dict), cKey, nil, 0)
        }) else { return nil }
        guard let valuePtr = entry.pointee.value else { return nil }
        return String(cString: valuePtr)
#else
        return nil
#endif
    }
}
