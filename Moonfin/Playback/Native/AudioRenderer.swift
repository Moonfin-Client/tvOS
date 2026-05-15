import AVFoundation
import CoreMedia
import Darwin
#if canImport(Libavcodec)
import Libavcodec
#endif
#if canImport(Libavutil)
import Libavutil
#endif
#if canImport(Libswresample)
import Libswresample
#endif

final class AudioRenderer {
    private enum OutputMode {
        case pcmDecoded
        case compressedPassthrough
    }

    var currentTime: TimeInterval {
        if outputMode == .compressedPassthrough,
           let synchronizer = compressedSynchronizer {
            let seconds = CMTimeGetSeconds(synchronizer.currentTime())
            if seconds.isFinite && seconds >= 0 {
                return seconds + audioDelaySeconds
            }
        }

        let rendered = samplesRendered
        guard outputSampleRate > 0 else { return 0 }
        return Double(rendered) / Double(outputSampleRate) + audioDelaySeconds
    }

    private(set) var outputSampleRate: Int32 = 0
    private(set) var outputChannels: Int32 = 0

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var compressedRenderer: AVSampleBufferAudioRenderer?
    private var compressedSynchronizer: AVSampleBufferRenderSynchronizer?
    private var compressedFormatDescription: CMAudioFormatDescription?
    private var codecCtx: UnsafeMutablePointer<AVCodecContext>?
    private var swrCtx: OpaquePointer?
    private var frame: UnsafeMutablePointer<AVFrame>?

    private let ringLock = NSLock()
    private var ringBuffer: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>?
    private var ringCapacity = 0
    private var ringWritePos = 0
    private var ringReadPos = 0
    private var ringAvailable = 0
    private var ringChannelCount: Int32 = 0
    private var outputMode: OutputMode = .pcmDecoded

    private var samplesRendered: Int64 = 0
    private var outputUnderrunSamples: Int64 = 0
    private var outputUnderrunCount: Int64 = 0
    private var ringOverflowDroppedSamples: Int64 = 0
    private var compressedPacketCount: Int64 = 0
    private var compressedDroppedPacketCount: Int64 = 0
    private var compressedNextPresentationTime: CMTime = .zero
    private var audioDelaySeconds: TimeInterval = 0
    private var playing = false
    private var playbackRate: Float = 1.0
    private var inputChannels: Int32 = 0
    private var inputLayout: UInt64 = 0
    private var inputSampleRate: Int32 = 0
    private var swrConfigured = false
    private var lastInputFormat: Int32 = -1
    private var swrOutputPtrs: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
    private var swrOutputCapacity: Int = 0
    private var swrOutputChannelCount: Int = 0

    // AVFrame field offsets (FFmpeg 7.x ABI)
    private static let frameExtendedDataOffset = 0x60 // uint8_t **extended_data
    private static let frameNbSamplesOffset = 0x70    // int nb_samples
    private static let frameFormatOffset = 0x74       // int format

    private static let AVERROR_EAGAIN: Int32 = -11

    init() {}

    deinit {
        stop()
    }

    var isReady: Bool {
#if canImport(Libavcodec)
        return true
#else
        return false
#endif
    }

    var renderedSampleCount: Int64 {
        ringLock.lock()
        defer { ringLock.unlock() }
        if outputMode == .compressedPassthrough {
            return compressedPacketCount * 1536
        }
        return samplesRendered
    }

    var droppedSampleCount: Int64 {
        ringLock.lock()
        defer { ringLock.unlock() }
        if outputMode == .compressedPassthrough {
            return compressedDroppedPacketCount * 1536
        }
        return outputUnderrunSamples + ringOverflowDroppedSamples
    }

    var underrunEventCount: Int64 {
        ringLock.lock()
        defer { ringLock.unlock() }
        return outputUnderrunCount
    }

    var overflowDroppedSampleCount: Int64 {
        ringLock.lock()
        defer { ringLock.unlock() }
        if outputMode == .compressedPassthrough {
            return compressedDroppedPacketCount * 1536
        }
        return ringOverflowDroppedSamples
    }

    // MARK: - Configure

    func configure(streamInfo: FFStreamInfo, codecpar: UnsafeRawPointer) -> Bool {
#if canImport(Libavcodec)
        teardownCompressedPath()
        teardownCodec()
        freeRingBuffer()

        let codecId = streamInfo.codecId
        if (codecId == 0x15002 || codecId == 0x15015),
           let formatDescription = makeCompressedFormatDescription(streamInfo: streamInfo) {
            outputMode = .compressedPassthrough
            outputSampleRate = streamInfo.sampleRate > 0 ? streamInfo.sampleRate : 48_000
            outputChannels = streamInfo.channels > 0 ? min(streamInfo.channels, 8) : 2
            compressedFormatDescription = formatDescription

            resetPlaybackCounters()

            return true
        }

        outputMode = .pcmDecoded
        compressedFormatDescription = nil

        guard let decoder = avcodec_find_decoder(AVCodecID(streamInfo.codecId)) else { return false }
        guard let ctx = avcodec_alloc_context3(decoder) else { return false }
        codecCtx = ctx

        let par = codecpar.assumingMemoryBound(to: AVCodecParameters.self)
        guard avcodec_parameters_to_context(ctx, par) >= 0 else {
            teardownCodec()
            return false
        }

        guard avcodec_open2(ctx, decoder, nil) >= 0 else {
            teardownCodec()
            return false
        }

        guard let fr = av_frame_alloc() else {
            teardownCodec()
            return false
        }
        frame = fr

        let inSampleRate = streamInfo.sampleRate > 0 ? streamInfo.sampleRate : 48000
        let inChannels = streamInfo.channels > 0 ? streamInfo.channels : 2

        inputChannels = inChannels
        inputLayout = streamInfo.channelLayout
        inputSampleRate = inSampleRate
        swrConfigured = false

        outputSampleRate = inSampleRate
        outputChannels = min(inChannels, 8)

        allocateRingBuffer(channels: outputChannels, capacity: Int(outputSampleRate) * 2)

        resetPlaybackCounters()

        return true
#else
        return false
#endif
    }

    // MARK: - Decode

    func decodePacket(_ packet: FFPacket, timeBase: (num: Int32, den: Int32)?) {
        if outputMode == .compressedPassthrough {
            enqueueCompressedPacket(packet, timeBase: timeBase)
            return
        }

#if canImport(Libavcodec)
        guard let codecCtx, let frame else { return }

        let pktPtr = packet.rawPacket.assumingMemoryBound(to: AVPacket.self)
        let result = avcodec_send_packet(codecCtx, pktPtr)
        guard result >= 0 || result == Self.AVERROR_EAGAIN else { return }

        while true {
            let ret = avcodec_receive_frame(codecCtx, frame)
            if ret < 0 { break }
            convertAndStore(UnsafeMutableRawPointer(frame))
        }
#endif
    }

    // MARK: - Engine control

    func start() -> Bool {
        if outputMode == .compressedPassthrough {
            guard compressedFormatDescription != nil else { return false }

            if compressedRenderer == nil || compressedSynchronizer == nil {
                let renderer = AVSampleBufferAudioRenderer()
                let synchronizer = AVSampleBufferRenderSynchronizer()
                synchronizer.addRenderer(renderer)
                compressedRenderer = renderer
                compressedSynchronizer = synchronizer
            }

            if let synchronizer = compressedSynchronizer {
                synchronizer.setRate(playbackRate, time: synchronizer.currentTime())
            }
            playing = true
            return true
        }

        guard outputSampleRate > 0, outputChannels > 0 else { return false }
        guard engine == nil else { return true }

        let channels = outputChannels
        let sampleRate = outputSampleRate

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else { return false }

        let eng = AVAudioEngine()
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }
            return self.renderCallback(frameCount: frameCount, bufferList: bufferList, channels: channels)
        }

        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)

        do {
            eng.prepare()
            try eng.start()
        } catch {
            return false
        }

        engine = eng
        sourceNode = node
        playing = true
        return true
    }

    func pause() {
        if outputMode == .compressedPassthrough {
            if let synchronizer = compressedSynchronizer {
                synchronizer.setRate(0, time: synchronizer.currentTime())
            }
            playing = false
            return
        }

        engine?.pause()
        playing = false
    }

    func resume() {
        if outputMode == .compressedPassthrough {
            if let synchronizer = compressedSynchronizer {
                synchronizer.setRate(playbackRate, time: synchronizer.currentTime())
            }
            playing = true
            return
        }

        do {
            try engine?.start()
            playing = true
        } catch {}
    }

    func stop() {
        playing = false
        if outputMode == .compressedPassthrough {
            teardownCompressedPath()
            outputMode = .pcmDecoded
        }

        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
        teardownCodec()
        freeRingBuffer()
        resetPlaybackCounters()
        audioDelaySeconds = 0
    }

    func flush() {
        if outputMode == .compressedPassthrough {
            compressedRenderer?.flush()
            ringLock.lock()
            compressedNextPresentationTime = .zero
            ringLock.unlock()
            return
        }

#if canImport(Libavcodec)
        if let codecCtx {
            avcodec_flush_buffers(codecCtx)
        }
#endif
        ringLock.lock()
        ringWritePos = 0
        ringReadPos = 0
        ringAvailable = 0
        ringLock.unlock()
        samplesRendered = 0
        swrConfigured = false
        lastInputFormat = -1
        teardownSwr()
    }

    func setAudioDelay(_ seconds: TimeInterval) {
        audioDelaySeconds = seconds
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if outputMode == .compressedPassthrough {
            if playing, let synchronizer = compressedSynchronizer {
                synchronizer.setRate(rate, time: synchronizer.currentTime())
            }
            return
        }

        sourceNode?.rate = rate
    }

    // MARK: - Track switching

    func setAudioTrack(streamInfo: FFStreamInfo, codecpar: UnsafeRawPointer) -> Bool {
        let wasPlaying = playing
        pause()

        let result = configure(streamInfo: streamInfo, codecpar: codecpar)
        guard result else { return false }

        if wasPlaying {
            _ = start()
            resume()
        }
        return true
    }

    // MARK: - Render callback

    private func renderCallback(frameCount: UInt32, bufferList: UnsafeMutablePointer<AudioBufferList>, channels: Int32) -> OSStatus {
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        let count = Int(frameCount)

        ringLock.lock()
        let available = ringAvailable
        let toRead = min(count, available)
        let cap = ringCapacity

        if toRead > 0, let ring = ringBuffer {
            for ch in 0..<Int(min(channels, Int32(abl.count))) {
                guard let dst = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                guard let src = ring[ch] else { continue }
                var readPos = ringReadPos
                for s in 0..<toRead {
                    dst[s] = src[readPos]
                    readPos = (readPos + 1) % cap
                }
            }
            ringReadPos = (ringReadPos + toRead) % cap
            ringAvailable -= toRead
        }

        if toRead < count {
            outputUnderrunSamples += Int64(count - toRead)
            outputUnderrunCount += 1
        }
        samplesRendered += Int64(toRead)
        ringLock.unlock()

        if toRead < count {
            for ch in 0..<abl.count {
                guard let dst = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for s in toRead..<count {
                    dst[s] = 0
                }
            }
        }

        for ch in 0..<abl.count {
            abl[ch].mDataByteSize = UInt32(count * MemoryLayout<Float>.size)
        }
        return noErr
    }

    private func enqueueCompressedPacket(_ packet: FFPacket, timeBase: (num: Int32, den: Int32)?) {
        guard outputMode == .compressedPassthrough,
              let renderer = compressedRenderer,
              let formatDescription = compressedFormatDescription,
              let packetData = packet.data,
              packet.size > 0
        else {
            return
        }

        guard renderer.isReadyForMoreMediaData else {
            incrementCompressedDroppedPacketCount()
            return
        }

        var blockBuffer: CMBlockBuffer?
        let packetSize = Int(packet.size)
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: packetSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: packetSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            incrementCompressedDroppedPacketCount()
            return
        }

        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: packetData,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: packetSize
        )
        guard copyStatus == kCMBlockBufferNoErr else {
            incrementCompressedDroppedPacketCount()
            return
        }

        let defaultDuration = defaultCompressedPacketDuration()
        let packetDuration = packetCMTime(packet.duration, timeBase: timeBase)
        let duration = (packetDuration.isValid && packetDuration > .zero) ? packetDuration : defaultDuration

        var presentationTime = packetCMTime(packet.pts, timeBase: timeBase)
        ringLock.lock()
        if !presentationTime.isValid {
            presentationTime = compressedNextPresentationTime
        }
        if duration.isValid {
            compressedNextPresentationTime = CMTimeAdd(presentationTime, duration)
        }
        ringLock.unlock()

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = packetSize
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sampleBuffer else {
            incrementCompressedDroppedPacketCount()
            return
        }

        renderer.enqueue(sampleBuffer)

        ringLock.lock()
        compressedPacketCount += 1
        ringLock.unlock()
    }

    private func packetCMTime(_ value: Int64, timeBase: (num: Int32, den: Int32)?) -> CMTime {
        guard let timeBase, timeBase.den > 0, timeBase.num > 0 else { return .invalid }
        let noPtsValue = Int64(bitPattern: 0x8000000000000000)
        guard value != noPtsValue else { return .invalid }
        let seconds = Double(value) * Double(timeBase.num) / Double(timeBase.den)
        return CMTime(seconds: seconds, preferredTimescale: 90000)
    }

    private func defaultCompressedPacketDuration() -> CMTime {
        guard outputSampleRate > 0 else {
            return CMTime(seconds: 0.032, preferredTimescale: 90000)
        }
        let seconds = 1536.0 / Double(outputSampleRate)
        return CMTime(seconds: seconds, preferredTimescale: 90000)
    }

    // MARK: - SWR conversion

    private func convertAndStore(_ frame: UnsafeMutableRawPointer) {
#if canImport(Libswresample)

        let nbSamples = frame.advanced(by: Self.frameNbSamplesOffset)
            .assumingMemoryBound(to: Int32.self).pointee
        guard nbSamples > 0 else { return }

        let frameFormat = frame.advanced(by: Self.frameFormatOffset)
            .assumingMemoryBound(to: Int32.self).pointee

        if !swrConfigured || frameFormat != lastInputFormat {
            teardownSwr()
            let outMask = channelMask(for: outputChannels)
            guard setupSwr(
                inChannels: inputChannels, inLayout: inputLayout,
                inSampleRate: inputSampleRate, inFormat: frameFormat,
                outChannels: outputChannels, outMask: outMask, outSampleRate: outputSampleRate
            ) else { return }
            swrConfigured = true
            lastInputFormat = frameFormat
        }

        guard let swrCtx else { return }

        let extData = frame.advanced(by: Self.frameExtendedDataOffset)
            .assumingMemoryBound(to: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.self).pointee

        let channels = Int(outputChannels)
        let needed = Int(nbSamples) * MemoryLayout<Float>.size
        if swrOutputPtrs == nil || swrOutputCapacity < needed || swrOutputChannelCount != channels {
            freeSwrOutputBuffers()
            swrOutputChannelCount = channels
            swrOutputCapacity = max(needed, 8192 * MemoryLayout<Float>.size)
            swrOutputPtrs = .allocate(capacity: channels)
            for ch in 0..<channels {
                swrOutputPtrs?[ch] = .allocate(capacity: swrOutputCapacity)
            }
        }
        guard let outPtrs = swrOutputPtrs else { return }

        let inPtrs = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: Int(inputChannels))
        defer { inPtrs.deallocate() }
        for ch in 0..<Int(inputChannels) {
            inPtrs[ch] = UnsafePointer(extData[ch])
        }

        let converted = swr_convert(swrCtx, outPtrs, nbSamples, inPtrs, nbSamples)
        guard converted > 0 else { return }

        let sampleCount = Int(converted)
        ringLock.lock()
        guard let ring = ringBuffer else {
            ringLock.unlock()
            return
        }
        let cap = ringCapacity
        let space = cap - ringAvailable
        let toWrite = min(sampleCount, space)
        if toWrite < sampleCount {
            ringOverflowDroppedSamples += Int64(sampleCount - toWrite)
        }
        if toWrite > 0 {
            for ch in 0..<Int(ringChannelCount) {
                guard let dst = ring[ch], let src = outPtrs[ch] else { continue }
                let floatSrc = UnsafeRawPointer(src).assumingMemoryBound(to: Float.self)
                var writePos = ringWritePos
                for s in 0..<toWrite {
                    dst[writePos] = floatSrc[s]
                    writePos = (writePos + 1) % cap
                }
            }
            ringWritePos = (ringWritePos + toWrite) % cap
            ringAvailable += toWrite
        }
        ringLock.unlock()
#endif
    }

    // MARK: - SWR setup

    private func makeCompressedFormatDescription(streamInfo: FFStreamInfo) -> CMAudioFormatDescription? {
        let formatId: AudioFormatID
        switch streamInfo.codecId {
        case 0x15002:
            formatId = kAudioFormatAC3
        case 0x15015:
            formatId = kAudioFormatEnhancedAC3
        default:
            return nil
        }

        let sampleRate = streamInfo.sampleRate > 0 ? streamInfo.sampleRate : 48_000
        let channels = streamInfo.channels > 0 ? streamInfo.channels : 2

        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: formatId,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1536,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = channelLayoutTag(for: channels)

        var formatDescription: CMAudioFormatDescription?
        let cookie = streamInfo.extradata ?? Data()
        let result: OSStatus = cookie.withUnsafeBytes { bytes in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: MemoryLayout<AudioChannelLayout>.size,
                layout: &channelLayout,
                magicCookieSize: bytes.baseAddress == nil ? 0 : cookie.count,
                magicCookie: bytes.baseAddress,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }

        guard result == noErr else { return nil }
        return formatDescription
    }

    private func channelLayoutTag(for channels: Int32) -> AudioChannelLayoutTag {
        switch channels {
        case 1:
            return kAudioChannelLayoutTag_Mono
        case 2:
            return kAudioChannelLayoutTag_Stereo
        case 6:
            return kAudioChannelLayoutTag_MPEG_5_1_A
        case 8:
            return kAudioChannelLayoutTag_MPEG_7_1_A
        default:
            return kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(UInt32(max(1, channels)))
        }
    }

    private func setupSwr(
        inChannels: Int32, inLayout: UInt64, inSampleRate: Int32, inFormat: Int32,
        outChannels: Int32, outMask: UInt64, outSampleRate: Int32
    ) -> Bool {
#if canImport(Libswresample)
        teardownSwr()

        var inChLayout = AVChannelLayout()
        av_channel_layout_default(&inChLayout, inChannels)
        if inLayout > 0 {
            inChLayout.order = AV_CHANNEL_ORDER_NATIVE
            inChLayout.u.mask = inLayout
        }
        var outChLayout = AVChannelLayout()
        av_channel_layout_default(&outChLayout, outChannels)
        outChLayout.order = AV_CHANNEL_ORDER_NATIVE
        outChLayout.u.mask = outMask

        var swr: OpaquePointer?
        let result = swr_alloc_set_opts2(
            &swr,
            &outChLayout, AV_SAMPLE_FMT_FLTP, outSampleRate,
            &inChLayout, AVSampleFormat(inFormat), inSampleRate,
            0, nil
        )
        guard result >= 0, let swr else { return false }
        swrCtx = swr

        guard swr_init(swr) >= 0 else {
            teardownSwr()
            return false
        }

        return true
#else
        return false
#endif
    }

    // MARK: - Ring buffer

    private func allocateRingBuffer(channels: Int32, capacity: Int) {
        freeRingBuffer()
        let ch = Int(channels)
        ringChannelCount = channels
        ringCapacity = capacity
        ringBuffer = .allocate(capacity: ch)
        for i in 0..<ch {
            ringBuffer?[i] = .allocate(capacity: capacity)
        }
        ringWritePos = 0
        ringReadPos = 0
        ringAvailable = 0
    }

    private func freeRingBuffer() {
        guard let ring = ringBuffer else { return }
        for i in 0..<Int(ringChannelCount) {
            ring[i]?.deallocate()
        }
        ring.deallocate()
        ringBuffer = nil
        ringCapacity = 0
        ringChannelCount = 0
        ringWritePos = 0
        ringReadPos = 0
        ringAvailable = 0
    }

    private func resetPlaybackCounters() {
        ringLock.lock()
        samplesRendered = 0
        outputUnderrunSamples = 0
        outputUnderrunCount = 0
        ringOverflowDroppedSamples = 0
        compressedPacketCount = 0
        compressedDroppedPacketCount = 0
        compressedNextPresentationTime = .zero
        ringLock.unlock()
    }

    private func incrementCompressedDroppedPacketCount() {
        ringLock.lock()
        compressedDroppedPacketCount += 1
        ringLock.unlock()
    }

    // MARK: - Teardown

    private func teardownCodec() {
#if canImport(Libavcodec)
        if frame != nil {
            av_frame_free(&frame)
        }
        frame = nil

        if codecCtx != nil {
            avcodec_free_context(&codecCtx)
        }
        codecCtx = nil
#endif
        teardownSwr()
    }

    private func teardownCompressedPath() {
        if let synchronizer = compressedSynchronizer,
           let renderer = compressedRenderer {
            synchronizer.removeRenderer(renderer, at: synchronizer.currentTime())
        }
        compressedRenderer = nil
        compressedSynchronizer = nil
        compressedFormatDescription = nil
        ringLock.lock()
        compressedPacketCount = 0
        compressedDroppedPacketCount = 0
        compressedNextPresentationTime = .zero
        ringLock.unlock()
    }

    private func teardownSwr() {
#if canImport(Libswresample)
        if swrCtx != nil {
            swr_free(&swrCtx)
        }
        swrCtx = nil
#endif
        freeSwrOutputBuffers()
    }

    private func freeSwrOutputBuffers() {
        guard let ptrs = swrOutputPtrs else { return }
        for ch in 0..<swrOutputChannelCount {
            ptrs[ch]?.deallocate()
        }
        ptrs.deallocate()
        swrOutputPtrs = nil
        swrOutputCapacity = 0
        swrOutputChannelCount = 0
    }

    private func channelMask(for channels: Int32) -> UInt64 {
        switch channels {
        case 1: return 0x4          // FC
        case 2: return 0x3          // FL|FR
        case 6: return 0x3F         // FL|FR|FC|LFE|BL|BR (5.1)
        case 8: return 0x63F        // FL|FR|FC|LFE|BL|BR|SL|SR (7.1)
        default: return 0x3
        }
    }

}
