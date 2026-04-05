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
        let sinkProfile: SinkProfile
        let diagnostics: [String]
    }

    struct SinkProfile {
        let screenLabel: String
        let displayGamut: String
        let currentMode: String
        let maximumFramesPerSecond: Int
        let isHdrCapable: Bool
        let diagnostics: [String]
    }

    static func current() -> Capabilities {
        let modelIdentifier = resolveModelIdentifier()
        let generation = generationForModel(modelIdentifier)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osLabel = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let activeScreen = resolveActiveScreen()
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

        let sinkProfile = resolveSinkProfile(
            screen: activeScreen,
            generation: generation,
            supportsHDR10: supportsHDR10
        )

        let diagnostics = [
            "os=\(osLabel)",
            "model=\(modelIdentifier)",
            "generation=\(generation.rawValue)",
            "external_display=\(externalDisplay)",
            "hdr10=\(supportsHDR10)",
            "hlg=\(supportsHLG)",
            "hdr10_plus=\(supportsHDR10Plus)",
            "dolby_vision=\(supportsDolbyVision)"
        ] + sinkProfile.diagnostics

        return Capabilities(
            generation: generation,
            supportsHDR10: supportsHDR10,
            supportsHLG: supportsHLG,
            supportsHDR10Plus: supportsHDR10Plus,
            supportsDolbyVision: supportsDolbyVision,
            sinkProfile: sinkProfile,
            diagnostics: diagnostics
        )
    }

    private static func resolveActiveScreen() -> UIScreen {
        if let sceneScreen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .screen {
            return sceneScreen
        }
        return UIScreen.main
    }

    private static func resolveSinkProfile(
        screen: UIScreen,
        generation: AppleTVGeneration,
        supportsHDR10: Bool
    ) -> SinkProfile {
        let modeSize = screen.currentMode?.size
        let modeLabel: String
        if let modeSize {
            modeLabel = "\(Int(modeSize.width))x\(Int(modeSize.height))"
        } else {
            modeLabel = "unknown"
        }

        let gamutLabel: String
        switch screen.traitCollection.displayGamut {
        case .P3:
            gamutLabel = "p3"
        case .SRGB:
            gamutLabel = "srgb"
        default:
            gamutLabel = "unspecified"
        }

        let isHdrCapable = supportsHDR10 && gamutLabel == "p3"

        let diagnostics = [
            "sink_screen=\(screen === UIScreen.main ? "main" : "external")",
            "sink_generation=\(generation.rawValue)",
            "sink_mode=\(modeLabel)",
            "sink_gamut=\(gamutLabel)",
            "sink_max_fps=\(screen.maximumFramesPerSecond)",
            "sink_hdr_capable=\(isHdrCapable)"
        ]

        return SinkProfile(
            screenLabel: screen === UIScreen.main ? "main" : "external",
            displayGamut: gamutLabel,
            currentMode: modeLabel,
            maximumFramesPerSecond: screen.maximumFramesPerSecond,
            isHdrCapable: isHdrCapable,
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
        canTranscode: Bool,
        videoStream: ServerMediaStream? = nil
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
            if capabilities.sinkProfile.isHdrCapable {
                return (.mpv, "prefer_mpv_hdr_pipeline", diagnostics)
            }
            if canTranscode {
                return (.mpv, "hdr10_requires_tone_mapping", diagnostics)
            }
            return (.tvvlcKit, "mpv_hdr10_uncertain", diagnostics)
        case .hlg:
            if capabilities.sinkProfile.isHdrCapable && capabilities.supportsHLG {
                return (.mpv, "prefer_mpv_hdr_pipeline", diagnostics)
            }
            if canTranscode {
                return (.mpv, "hlg_requires_tone_mapping", diagnostics)
            }
            return (.tvvlcKit, "mpv_hlg_uncertain", diagnostics)
        case .hdr10Plus:
            if capabilities.sinkProfile.isHdrCapable && capabilities.supportsHDR10Plus {
                return (.mpv, "prefer_mpv_hdr_pipeline", diagnostics)
            }
            if canTranscode {
                return (.mpv, "hdr10_plus_requires_tone_mapping", diagnostics)
            }
            return (.tvvlcKit, "mpv_hdr10_plus_uncertain", diagnostics)
        case .dolbyVision:
            if isDolbyVisionProfile5(videoStream: videoStream) {
                return (.tvvlcKit, "dolby_vision_profile5_prefer_vlc", diagnostics)
            }
            if capabilities.sinkProfile.isHdrCapable && canTranscode {
                return (.mpv, "dolby_vision_requires_transcode", diagnostics)
            }
            return (.tvvlcKit, "mpv_dolby_vision_uncertain", diagnostics)
        case .unknown:
            return (.mpv, "mpv_dynamic_range_unknown", diagnostics)
        }
    }

    private static func isDolbyVisionProfile5(videoStream: ServerMediaStream?) -> Bool {
        guard let stream = videoStream else { return false }
        let codec = stream.codec?.lowercased() ?? ""
        let profile = stream.profile?.lowercased() ?? ""
        let rangeType = stream.videoRangeType?.lowercased() ?? ""
        let combined = [codec, profile, rangeType].joined(separator: " ")
        if combined.contains("dvhe.05") || combined.contains("dvh1.05") {
            return true
        }
        if rangeType == "dovi" && !combined.contains("hdr10") {
            return true
        }
        return false
    }
}
