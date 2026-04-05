import AVKit
import CoreMedia
import UIKit

@MainActor
final class DisplayCriteriaManager {

    static let shared = DisplayCriteriaManager()
    private init() {}

    func apply(stream: StreamInfo) {
        guard let videoStream = stream.videoStream else { return }
        guard let window = activeWindow() else { return }
        let manager = window.avDisplayManager
        guard manager.isDisplayCriteriaMatchingEnabled else { return }

        let criteria = buildCriteria(videoStream: videoStream, dynamicRange: stream.dynamicRange)
        manager.preferredDisplayCriteria = criteria
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

    private func buildCriteria(
        videoStream: ServerMediaStream,
        dynamicRange: VideoDynamicRange
    ) -> AVDisplayCriteria? {
        guard #available(tvOS 17.0, *) else { return nil }
        let fps = Float(videoStream.realFrameRate ?? 24)
        guard let formatDescription = makeFormatDescription(videoStream: videoStream, dynamicRange: dynamicRange) else {
            return nil
        }
        return AVDisplayCriteria(refreshRate: fps, formatDescription: formatDescription)
    }

    private func makeFormatDescription(
        videoStream: ServerMediaStream,
        dynamicRange: VideoDynamicRange
    ) -> CMFormatDescription? {
        let codecType = resolveCodecType(codec: videoStream.codec)
        let width = Int32(videoStream.width ?? 3840)
        let height = Int32(videoStream.height ?? 2160)
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

    private func resolveCodecType(codec: String?) -> CMVideoCodecType {
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
