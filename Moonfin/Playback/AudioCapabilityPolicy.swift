import Foundation

struct AudioCapabilityPolicy {
    struct Decision {
        let backend: PlaybackBackendDirective
        let reason: String?
        let requiresTranscode: Bool
        let diagnostics: [String]
    }

    static func decide(
        requestedBackend: PlaybackBackendDirective,
        selectedAudioStream: ServerMediaStream?,
        canTranscode: Bool,
        maxAudioChannels: Int?
    ) -> Decision {
        var diagnostics: [String] = []

        guard requestedBackend == .mpv else {
            return Decision(backend: .mpv, reason: nil, requiresTranscode: false, diagnostics: diagnostics)
        }

        guard let stream = selectedAudioStream else {
            diagnostics.append("audio_stream=none")
            return Decision(backend: .mpv, reason: nil, requiresTranscode: false, diagnostics: diagnostics)
        }

        let codec = (stream.codec ?? "unknown").lowercased()
        let profile = (stream.profile ?? "").lowercased()
        let displayTitle = (stream.displayTitle ?? "").lowercased()
        let channelLayout = (stream.channelLayout ?? "").lowercased()
        let channels = stream.channels ?? 0
        let maxChannelsLabel = maxAudioChannels.map(String.init) ?? "none"

        diagnostics.append("audio_codec=\(codec)")
        diagnostics.append("audio_profile=\(profile)")
        diagnostics.append("audio_channels=\(channels)")
        diagnostics.append("max_audio_channels=\(maxChannelsLabel)")

        let isEac3 = codec == "eac3"
        let isTrueHd = codec == "truehd" || codec == "mlp"
        let isDtsFamily = codec.contains("dts") || codec == "dca"
        let isAtmosJoc = isEac3 && (profile.contains("joc") || displayTitle.contains("atmos") || channelLayout.contains("joc"))

        if maxAudioChannels == 2, channels > 2 {
            diagnostics.append("downmix_preference=stereo")
            if canTranscode {
                return Decision(
                    backend: .mpv,
                    reason: "downmix_to_stereo_requires_transcode",
                    requiresTranscode: true,
                    diagnostics: diagnostics
                )
            }
        }

        if isTrueHd {
            diagnostics.append("audio_feature=truehd")
            return Decision(
                backend: .mpv,
                reason: "truehd_direct_play",
                requiresTranscode: false,
                diagnostics: diagnostics
            )
        }

        if isDtsFamily {
            diagnostics.append("audio_feature=dts_family")
            return Decision(
                backend: .mpv,
                reason: "dts_direct_play",
                requiresTranscode: false,
                diagnostics: diagnostics
            )
        }

        if isAtmosJoc {
            diagnostics.append("audio_feature=eac3_joc")
            return Decision(backend: .mpv, reason: nil, requiresTranscode: false, diagnostics: diagnostics)
        }

        let directCodecs: Set<String> = ["aac", "ac3", "eac3", "flac", "opus", "pcm", "alac", "mp3", "vorbis"]
        if directCodecs.contains(codec) {
            return Decision(backend: .mpv, reason: nil, requiresTranscode: false, diagnostics: diagnostics)
        }

        diagnostics.append("audio_feature=unknown_codec")
        if canTranscode {
            return Decision(
                backend: .mpv,
                reason: "unsupported_audio_codec_requires_transcode",
                requiresTranscode: true,
                diagnostics: diagnostics
            )
        }

        return Decision(
            backend: .mpv,
            reason: "mpv_audio_codec_uncertain",
            requiresTranscode: false,
            diagnostics: diagnostics
        )
    }
}
