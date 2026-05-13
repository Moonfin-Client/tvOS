import Foundation
import VideoToolbox
import CoreMedia

final class VTDecoder {

    var onFrameDecoded: ((CVPixelBuffer, CMTime) -> Void)?
    var onDecoderError: (() -> Void)?

    private var session: VTDecompressionSession?
    private(set) var formatDescription: CMVideoFormatDescription?
    private var currentExtradata: Data?
    private var dvConfig: DVConfiguration?
    private var reorderBuffer: [(CVPixelBuffer, CMTime)] = []
    private let reorderCapacity = 8
    private let lock = NSLock()
    private var framesDecoded: UInt64 = 0
    private var framesDropped: UInt64 = 0
    private var consecutiveDecodeErrors: Int = 0
    private var sessionRecreationAttempted = false
    private(set) var hasUnrecoverableError = false

    init() {}

    deinit {
        invalidate()
    }

    func configure(extradata: Data, dvConfig: DVConfiguration?) -> Bool {
        if let current = currentExtradata, current == extradata, session != nil {
            return true
        }
        invalidate()
        self.dvConfig = dvConfig
        self.currentExtradata = extradata

        guard let fmtDesc = makeFormatDescription(extradata: extradata, dvConfig: dvConfig) else {
            return false
        }
        self.formatDescription = fmtDesc
        return createSession(formatDescription: fmtDesc)
    }

    func decode(data: UnsafeRawPointer, size: Int, pts: CMTime, dts: CMTime, duration: CMTime) -> Bool {
        guard let session else { return false }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: size,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return false }

        status = CMBlockBufferReplaceDataBytes(
            with: data,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: size
        )
        guard status == kCMBlockBufferNoErr else { return false }

        var sampleSize = size
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts
        )

        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
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
        guard status == noErr, let sampleBuffer else { return false }

        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression]
        var infoFlags: VTDecodeInfoFlags = []

        status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )

        if status != noErr {
            framesDropped += 1
            consecutiveDecodeErrors += 1
            if consecutiveDecodeErrors >= 5 && !sessionRecreationAttempted {
                sessionRecreationAttempted = true
                if recreateSession() {
                    consecutiveDecodeErrors = 0
                }
            }
            if consecutiveDecodeErrors >= 10 {
                hasUnrecoverableError = true
                onDecoderError?()
            }
            return false
        }
        consecutiveDecodeErrors = 0
        return true
    }

    func flush() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
        }
        drainReorderBuffer(force: true)
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        currentExtradata = nil
        consecutiveDecodeErrors = 0
        sessionRecreationAttempted = false
        hasUnrecoverableError = false
        lock.lock()
        reorderBuffer.removeAll()
        lock.unlock()
    }

    func resetErrorState() {
        consecutiveDecodeErrors = 0
        sessionRecreationAttempted = false
        hasUnrecoverableError = false
    }

    var decodedCount: UInt64 { framesDecoded }
    var droppedCount: UInt64 { framesDropped }

    // MARK: - Session creation

    private func recreateSession() -> Bool {
        guard let fmtDesc = formatDescription else { return false }
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        lock.lock()
        reorderBuffer.removeAll()
        lock.unlock()
        return createSession(formatDescription: fmtDesc)
    }

    private func createSession(formatDescription: CMVideoFormatDescription) -> Bool {
        var decoderSpec: [CFString: Any] = [:]
        if #available(tvOS 17.0, *) {
            decoderSpec[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = true
        }

        let fullRange = sourceUsesFullRange(formatDescription)
        let outputPixelFormat: OSType = fullRange
            ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange

        let outputAttrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferPixelFormatTypeKey: outputPixelFormat,
            kCVImageBufferColorPrimariesKey: preferredColorPrimaries(),
            kCVImageBufferTransferFunctionKey: preferredTransferFunction(),
            kCVImageBufferYCbCrMatrixKey: preferredYCbCrMatrix()
        ]

        var session: VTDecompressionSession?
        var callback = makeOutputCallback()

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: outputAttrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else { return false }
        self.session = session

        if #available(tvOS 17.0, *) {
            VTSessionSetProperty(
                session,
                key: kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata,
                value: kCFBooleanTrue
            )
        }

        return true
    }

    private func makeOutputCallback() -> VTDecompressionOutputCallbackRecord {
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        return VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, pixelBuffer, pts, _ in
                guard let refCon else { return }
                let decoder = Unmanaged<VTDecoder>.fromOpaque(refCon).takeUnretainedValue()
                guard status == noErr, let pixelBuffer else {
                    decoder.framesDropped += 1
                    return
                }
                decoder.attachColorMetadata(to: pixelBuffer)
                decoder.framesDecoded += 1
                decoder.insertIntoReorderBuffer(pixelBuffer: pixelBuffer, pts: pts)
            },
            decompressionOutputRefCon: rawSelf
        )
    }

    private func sourceUsesFullRange(_ formatDescription: CMVideoFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [CFString: Any] else {
            return false
        }

        if let number = extensions[kCMFormatDescriptionExtension_FullRangeVideo] as? NSNumber {
            return number.boolValue
        }

        if let fullRange = extensions[kCMFormatDescriptionExtension_FullRangeVideo] as? Bool {
            return fullRange
        }

        return false
    }

    private func preferredColorPrimaries() -> CFString {
        guard let formatDescription,
              let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [CFString: Any],
              let value = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String else {
            return dvConfig == nil ? kCVImageBufferColorPrimaries_ITU_R_709_2 : kCVImageBufferColorPrimaries_ITU_R_2020
        }

        if value == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
            return kCVImageBufferColorPrimaries_ITU_R_2020
        }
        return kCVImageBufferColorPrimaries_ITU_R_709_2
    }

    private func preferredTransferFunction() -> CFString {
        guard let formatDescription,
              let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [CFString: Any],
              let value = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String else {
            return dvConfig == nil ? kCVImageBufferTransferFunction_ITU_R_709_2 : kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        }

        if value == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return kCVImageBufferTransferFunction_ITU_R_2100_HLG
        }
        if value == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            return kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        }
        return kCVImageBufferTransferFunction_ITU_R_709_2
    }

    private func preferredYCbCrMatrix() -> CFString {
        guard let formatDescription,
              let extensions = CMFormatDescriptionGetExtensions(formatDescription) as? [CFString: Any],
              let value = extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String else {
            return dvConfig == nil ? kCVImageBufferYCbCrMatrix_ITU_R_709_2 : kCVImageBufferYCbCrMatrix_ITU_R_2020
        }

        if value == (kCMFormatDescriptionYCbCrMatrix_ITU_R_2020 as String) {
            return kCVImageBufferYCbCrMatrix_ITU_R_2020
        }
        return kCVImageBufferYCbCrMatrix_ITU_R_709_2
    }

    private func attachColorMetadata(to pixelBuffer: CVPixelBuffer) {
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, preferredColorPrimaries(), .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, preferredTransferFunction(), .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, preferredYCbCrMatrix(), .shouldPropagate)
    }

    // MARK: - Frame reordering

    private func insertIntoReorderBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        reorderBuffer.append((pixelBuffer, pts))
        reorderBuffer.sort { $0.1.value < $1.1.value }
        let shouldDrain = reorderBuffer.count >= reorderCapacity
        lock.unlock()

        if shouldDrain {
            drainReorderBuffer(force: false)
        }
    }

    private func drainReorderBuffer(force: Bool) {
        lock.lock()
        let drainCount = force ? reorderBuffer.count : max(0, reorderBuffer.count - reorderCapacity / 2)
        let frames = Array(reorderBuffer.prefix(drainCount))
        reorderBuffer.removeFirst(drainCount)
        lock.unlock()

        for (pixelBuffer, pts) in frames {
            onFrameDecoded?(pixelBuffer, pts)
        }
    }

    // MARK: - Format description

    private func makeFormatDescription(
        extradata: Data,
        dvConfig: DVConfiguration?
    ) -> CMVideoFormatDescription? {
        let parameterSets = parseHEVCParameterSets(from: extradata)
        guard !parameterSets.isEmpty else { return nil }

        var fmtDesc: CMVideoFormatDescription?

        let status = parameterSets.withUnsafeBufferPointers { pointers, sizes in
            CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers,
                parameterSetSizes: sizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &fmtDesc
            )
        }
        guard status == noErr, let fmtDesc else { return nil }

        if let dvConfig {
            return attachDVConfig(to: fmtDesc, dvConfig: dvConfig) ?? fmtDesc
        }
        return fmtDesc
    }

    private func attachDVConfig(
        to baseDesc: CMVideoFormatDescription,
        dvConfig: DVConfiguration
    ) -> CMVideoFormatDescription? {
        let dvvcData = buildDvvCBox(dvConfig: dvConfig)

        guard let baseExtensions = CMFormatDescriptionGetExtensions(baseDesc) as? [CFString: Any] else {
            return nil
        }
        var extensions = baseExtensions

        var atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Any] ?? [:]
        atoms["dvvC"] = dvvcData as CFData
        extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] = atoms

        let dims = CMVideoFormatDescriptionGetDimensions(baseDesc)
        var newDesc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_DolbyVisionHEVC,
            width: dims.width,
            height: dims.height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &newDesc
        )
        guard status == noErr else { return nil }
        return newDesc
    }

    // 24-byte DOVIDecoderConfigurationRecord per DOVI ISO spec
    private func buildDvvCBox(dvConfig: DVConfiguration) -> Data {
        var data = Data(count: 24)
        data[0] = dvConfig.versionMajor
        data[1] = dvConfig.versionMinor

        // Byte 2: upper 7 bits = profile, lower 1 bit = top bit of level
        data[2] = (dvConfig.profile << 1) | (dvConfig.level >> 5)
        // Byte 3: remaining 5 bits of level + rpu(1) + el(1) + bl(1)
        var byte3: UInt8 = (dvConfig.level & 0x1F) << 3
        if dvConfig.rpuPresent { byte3 |= 0x04 }
        if dvConfig.elPresent { byte3 |= 0x02 }
        if dvConfig.blPresent { byte3 |= 0x01 }
        data[3] = byte3

        // Byte 4: upper 4 bits = bl_signal_compatibility_id, lower 4 bits = md_compression
        data[4] = (dvConfig.blSignalCompatibilityId << 4) | (dvConfig.mdCompression & 0x0F)

        return data
    }

    // MARK: - HEVC parameter set parsing

    // Extradata can be in HVCC (length-prefixed) or Annex B (start code) format
    private func parseHEVCParameterSets(from extradata: Data) -> [Data] {
        if extradata.count >= 23 && extradata[0] == 1 {
            return parseHVCC(extradata)
        }
        return parseAnnexB(extradata)
    }

    // HVCC (HEVCDecoderConfigurationRecord) format:
    // Byte 0: configurationVersion (1)
    // Bytes 1-22: various config fields
    // Byte 22: lengthSizeMinusOne (lower 2 bits) + other flags
    // Byte 22: numOfArrays
    // Then for each array:
    //   1 byte: type (lower 6 bits = NAL unit type)
    //   2 bytes: numNalus (big-endian)
    //   For each NALU:
    //     2 bytes: naluLength (big-endian)
    //     naluLength bytes: data
    private func parseHVCC(_ data: Data) -> [Data] {
        guard data.count >= 23 else { return [] }
        var result: [Data] = []
        let numArrays = Int(data[22])
        var offset = 23

        for _ in 0..<numArrays {
            guard offset + 3 <= data.count else { break }
            offset += 1 // skip array header byte
            let numNalus = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2

            for _ in 0..<numNalus {
                guard offset + 2 <= data.count else { break }
                let naluLen = Int(data[offset]) << 8 | Int(data[offset + 1])
                offset += 2
                guard offset + naluLen <= data.count else { break }
                result.append(data[offset..<(offset + naluLen)])
                offset += naluLen
            }
        }
        return result
    }

    // Annex B format: 0x00000001 or 0x000001 start codes separating NALUs
    private func parseAnnexB(_ data: Data) -> [Data] {
        var result: [Data] = []
        var i = 0
        let count = data.count

        while i < count {
            let startCodeLen: Int
            if i + 3 < count && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1 {
                startCodeLen = 4
            } else if i + 2 < count && data[i] == 0 && data[i+1] == 0 && data[i+2] == 1 {
                startCodeLen = 3
            } else {
                i += 1
                continue
            }

            let naluStart = i + startCodeLen
            var naluEnd = count

            for j in naluStart..<count {
                if j + 3 < count && data[j] == 0 && data[j+1] == 0 && data[j+2] == 0 && data[j+3] == 1 {
                    naluEnd = j
                    break
                }
                if j + 2 < count && data[j] == 0 && data[j+1] == 0 && data[j+2] == 1 {
                    naluEnd = j
                    break
                }
            }

            if naluEnd > naluStart {
                let naluType = (data[naluStart] >> 1) & 0x3F
                // VPS=32, SPS=33, PPS=34
                if naluType >= 32 && naluType <= 34 {
                    result.append(data[naluStart..<naluEnd])
                }
            }
            i = naluEnd
        }
        return result
    }
}

// Helper to pass arrays of parameter set pointers to CoreMedia
private extension Array where Element == Data {
    func withUnsafeBufferPointers<R>(
        _ body: (_ pointers: [UnsafePointer<UInt8>], _ sizes: [Int]) -> R
    ) -> R {
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []

        func pin(index: Int, _ continuation: () -> R) -> R {
            if index >= count {
                return continuation()
            }
            return self[index].withUnsafeBytes { rawBuf -> R in
                guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return continuation()
                }
                pointers.append(ptr)
                sizes.append(rawBuf.count)
                return pin(index: index + 1, continuation)
            }
        }

        return pin(index: 0) {
            body(pointers, sizes)
        }
    }
}
