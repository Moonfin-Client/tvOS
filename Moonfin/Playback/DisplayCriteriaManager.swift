import AVKit
import CoreMedia
import UIKit

@MainActor
final class DisplayCriteriaManager {

    static let shared = DisplayCriteriaManager()
    private init() {}

    @discardableResult
    func apply(stream: StreamInfo) -> Int? {
        guard let videoStream = stream.videoStream else { return nil }
        guard let window = activeWindow() else { return nil }
        let fallbackFps = legacyPreferredFramesPerSecond(for: videoStream, screen: window.screen)
        let manager = window.avDisplayManager
        guard manager.isDisplayCriteriaMatchingEnabled else { return fallbackFps }

        let refreshRate = resolvedRefreshRate(for: videoStream, screen: window.screen)
        if #available(tvOS 17.0, *) {
            let criteria = buildCriteria(
                videoStream: videoStream,
                dynamicRange: stream.dynamicRange,
                refreshRate: refreshRate
            )
            manager.preferredDisplayCriteria = criteria
            return nil
        }

        manager.preferredDisplayCriteria = nil
        return fallbackFps
    }

    func applyNative(formatDescription: CMVideoFormatDescription, refreshRate: Float) {
        guard let window = activeWindow() else { return }
        let manager = window.avDisplayManager
        guard manager.isDisplayCriteriaMatchingEnabled else { return }
        if #available(tvOS 17.0, *) {
            manager.preferredDisplayCriteria = AVDisplayCriteria(
                refreshRate: refreshRate,
                formatDescription: formatDescription
            )
        } else {
            manager.preferredDisplayCriteria = nil
        }
    }

    func reset() {
        guard let window = activeWindow() else { return }
        window.avDisplayManager.preferredDisplayCriteria = nil
    }

    private func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }

    @available(tvOS 17.0, *)
    private func buildCriteria(
        videoStream: ServerMediaStream,
        dynamicRange: VideoDynamicRange,
        refreshRate: Float
    ) -> AVDisplayCriteria? {
        guard let formatDescription = makeFormatDescription(videoStream: videoStream, dynamicRange: dynamicRange) else {
            return nil
        }
        return AVDisplayCriteria(refreshRate: refreshRate, formatDescription: formatDescription)
    }

    private func makeFormatDescription(
        videoStream: ServerMediaStream,
        dynamicRange: VideoDynamicRange
    ) -> CMFormatDescription? {
        let codecType = resolveCodecType(codec: videoStream.codec, dynamicRange: dynamicRange)
        let width = Int32(max(16, videoStream.width ?? 3840))
        let height = Int32(max(16, videoStream.height ?? 2160))
        let extensions = makeColorExtensions(dynamicRange: dynamicRange)

        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: width,
            height: height,
            extensions: extensions,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr else { return nil }
        return formatDescription
    }

    private func resolvedRefreshRate(for videoStream: ServerMediaStream, screen: UIScreen) -> Float {
        let raw = videoStream.realFrameRate ?? 24
        let safe = (raw.isFinite && raw > 0) ? raw : 24
        let screenMax = Float(max(1, screen.maximumFramesPerSecond))
        return min(Float(safe), screenMax)
    }

    private func legacyPreferredFramesPerSecond(for videoStream: ServerMediaStream, screen: UIScreen) -> Int {
        let target = resolvedRefreshRate(for: videoStream, screen: screen)
        let maxFps = max(1, screen.maximumFramesPerSecond)
        let candidates = [24, 25, 30, 48, 50, 60].filter { $0 <= maxFps }
        guard let nearest = candidates.min(by: { abs(Float($0) - target) < abs(Float($1) - target) }) else {
            return max(1, min(maxFps, Int(target.rounded())))
        }
        return nearest
    }

    private func resolveCodecType(codec: String?, dynamicRange: VideoDynamicRange = .unknown) -> CMVideoCodecType {
        if dynamicRange == .dolbyVision {
            return kCMVideoCodecType_DolbyVisionHEVC
        }
        switch codec?.lowercased() {
        case "hevc", "h265":
            return kCMVideoCodecType_HEVC
        case "av1":
            return kCMVideoCodecType_AV1
        case "vp9":
            return kCMVideoCodecType_VP9
        default:
            return kCMVideoCodecType_H264
        }
    }

    private func makeColorExtensions(dynamicRange: VideoDynamicRange) -> CFDictionary {
        var dict: [CFString: CFString] = [:]

        switch dynamicRange {
        case .hdr10, .hdr10Plus, .dolbyVision:
            dict[kCMFormatDescriptionExtension_ColorPrimaries]  = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            dict[kCMFormatDescriptionExtension_TransferFunction] = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
            dict[kCMFormatDescriptionExtension_YCbCrMatrix]     = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020

        case .hlg:
            dict[kCMFormatDescriptionExtension_ColorPrimaries]  = kCMFormatDescriptionColorPrimaries_ITU_R_2020
            dict[kCMFormatDescriptionExtension_TransferFunction] = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
            dict[kCMFormatDescriptionExtension_YCbCrMatrix]     = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020

        case .sdr, .unknown:
            break
        }

        return dict as CFDictionary
    }
}
