import Foundation
import UIKit

struct VideoCapabilityDetector {
    enum AppleTVGeneration: String {
        case hd
        case k4Gen1
        case k4Gen2
        case k4Gen3
        case unknown
    }

    struct Capabilities {
        let generation: AppleTVGeneration
        let supportsHDR10: Bool
        let supportsHLG: Bool
        let supportsHDR10Plus: Bool
        let supportsDolbyVision: Bool
        let diagnostics: [String]
    }

    static func current() -> Capabilities {
        let modelIdentifier = resolveModelIdentifier()
        let generation = generationForModel(modelIdentifier)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osLabel = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let connectedScreens = Set(
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen }
                .map { ObjectIdentifier($0) }
        )
        let externalDisplay = connectedScreens.count > 1

        let supportsHDR10: Bool
        let supportsHLG: Bool
        let supportsHDR10Plus: Bool
        let supportsDolbyVision: Bool

        switch generation {
        case .hd:
            supportsHDR10 = false
            supportsHLG = false
            supportsHDR10Plus = false
            supportsDolbyVision = false
        case .k4Gen1:
            supportsHDR10 = true
            supportsHLG = false
            supportsHDR10Plus = false
            supportsDolbyVision = true
        case .k4Gen2:
            supportsHDR10 = true
            supportsHLG = true
            supportsHDR10Plus = false
            supportsDolbyVision = true
        case .k4Gen3:
            supportsHDR10 = true
            supportsHLG = true
            supportsHDR10Plus = true
            supportsDolbyVision = true
        case .unknown:
            supportsHDR10 = false
            supportsHLG = false
            supportsHDR10Plus = false
            supportsDolbyVision = false
        }

        let diagnostics = [
            "os=\(osLabel)",
            "model=\(modelIdentifier)",
            "generation=\(generation.rawValue)",
            "external_display=\(externalDisplay)",
            "hdr10=\(supportsHDR10)",
            "hlg=\(supportsHLG)",
            "hdr10_plus=\(supportsHDR10Plus)",
            "dolby_vision=\(supportsDolbyVision)"
        ]

        return Capabilities(
            generation: generation,
            supportsHDR10: supportsHDR10,
            supportsHLG: supportsHLG,
            supportsHDR10Plus: supportsHDR10Plus,
            supportsDolbyVision: supportsDolbyVision,
            diagnostics: diagnostics
        )
    }

    private static func resolveModelIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        #endif

        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    private static func generationForModel(_ modelIdentifier: String) -> AppleTVGeneration {
        switch modelIdentifier {
        case "AppleTV5,3":
            return .hd
        case "AppleTV6,2":
            return .k4Gen1
        case "AppleTV11,1":
            return .k4Gen2
        case "AppleTV14,1":
            return .k4Gen3
        default:
            return .unknown
        }
    }
}

struct VideoDynamicRangePolicy {
    static func detectRange(videoStream: ServerMediaStream?) -> VideoDynamicRange {
        guard let stream = videoStream else { return .unknown }

        let codec = stream.codec?.lowercased() ?? ""
        let profile = stream.profile?.lowercased() ?? ""
        let range = stream.videoRange?.lowercased() ?? ""
        let rangeType = stream.videoRangeType?.lowercased() ?? ""
        let sample = [codec, profile, range, rangeType].joined(separator: " ")

        if sample.contains("dovi") || sample.contains("dvhe") || sample.contains("dvh1") || sample.contains("dolby") {
            return .dolbyVision
        }

        if sample.contains("hdr10+") || sample.contains("hdr10plus") {
            return .hdr10Plus
        }

        if sample.contains("hlg") {
            return .hlg
        }

        if sample.contains("hdr10") || sample.contains("pq") || sample.contains("hdr") {
            return .hdr10
        }

        if sample.contains("sdr") {
            return .sdr
        }

        return .unknown
    }

    static func decide(
        requestedBackend: PlaybackBackendDirective,
        dynamicRange: VideoDynamicRange,
        capabilities: VideoCapabilityDetector.Capabilities,
        canTranscode: Bool
    ) -> (backend: PlaybackBackendDirective, reason: String?, diagnostics: [String]) {
        var diagnostics = capabilities.diagnostics
        diagnostics.append("dynamic_range=\(dynamicRange.rawValue)")
        diagnostics.append("requested_backend=\(requestedBackend.rawValue)")
        diagnostics.append("can_transcode=\(canTranscode)")

        guard requestedBackend == .mpv else {
            return (.tvvlcKit, nil, diagnostics)
        }

        switch dynamicRange {
        case .sdr:
            return (.mpv, nil, diagnostics)
        case .hdr10:
            if capabilities.supportsHDR10 {
                return (.mpv, nil, diagnostics)
            }
            if canTranscode {
                return (.mpv, "hdr10_requires_transcode", diagnostics)
            }
            return (.tvvlcKit, "mpv_hdr10_uncertain", diagnostics)
        case .hlg:
            if capabilities.supportsHLG {
                return (.mpv, nil, diagnostics)
            }
            if canTranscode {
                return (.mpv, "hlg_requires_transcode", diagnostics)
            }
            return (.tvvlcKit, "mpv_hlg_uncertain", diagnostics)
        case .hdr10Plus:
            if capabilities.supportsHDR10Plus {
                return (.mpv, nil, diagnostics)
            }
            if canTranscode {
                return (.mpv, "hdr10_plus_requires_transcode", diagnostics)
            }
            return (.tvvlcKit, "mpv_hdr10_plus_uncertain", diagnostics)
        case .dolbyVision:
            if capabilities.supportsDolbyVision {
                return (.mpv, nil, diagnostics)
            }
            if canTranscode {
                return (.mpv, "dolby_vision_requires_transcode", diagnostics)
            }
            return (.tvvlcKit, "mpv_dolby_vision_uncertain", diagnostics)
        case .unknown:
            return (.tvvlcKit, "mpv_dynamic_range_unknown", diagnostics)
        }
    }
}
