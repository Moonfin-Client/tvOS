import SwiftUI

struct PlaybackInfoDialog: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme

    private var streamInfo: StreamInfo? { viewModel.playbackManager.currentStreamInfo }
    private var mediaSource: ServerMediaSource? {
        viewModel.playbackManager.currentEntry?.item.mediaSources?.first(where: { $0.id == streamInfo?.mediaSourceId })
            ?? viewModel.playbackManager.currentEntry?.item.mediaSources?.first
    }

    private var videoStream: ServerMediaStream? {
        let allStreams = mediaSource?.mediaStreams ?? (streamInfo.map { $0.audioStreams + $0.subtitleStreams } ?? [])
        return allStreams.first(where: { $0.type == .video })
    }

    private var activeAudioStream: ServerMediaStream? {
        let idx = viewModel.player.currentAudioTrackIndex
        let streams = mediaSource?.mediaStreams ?? streamInfo?.audioStreams ?? []
        return streams.first(where: { $0.type == .audio && $0.index == Int(idx) })
            ?? streams.first(where: { $0.type == .audio && $0.isDefault })
            ?? streams.first(where: { $0.type == .audio })
    }

    private var activeSubtitleStream: ServerMediaStream? {
        let idx = viewModel.player.currentSubtitleTrackIndex
        guard idx >= 0 else { return nil }
        let streams = mediaSource?.mediaStreams ?? streamInfo?.subtitleStreams ?? []
        return streams.first(where: { $0.type == .subtitle && $0.index == Int(idx) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.playerPlaybackInformation)
                .font(.captionSm)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.top, SpaceTokens.spaceMd)
                .padding(.bottom, SpaceTokens.spaceXs)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                    playbackSection
                    videoSection
                    audioSection
                    subtitleSection
                }
                .padding(.horizontal, SpaceTokens.spaceMd)
            }
            .frame(maxHeight: 900)

            HStack {
                Spacer()
                FocusableDialogButton(title: Strings.close, action: { viewModel.hidePlaybackInfo() })
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceXs)
        }
        .frame(width: 580)
        .background(theme.colorScheme.surface)
        .cornerRadius(RadiusTokens.large)
        .onExitCommand { viewModel.hidePlaybackInfo() }
    }

    private var playbackSection: some View {
        InfoSection(title: Strings.playerPlaybackSection) {
            InfoRow(label: Strings.playerPlayMethod, value: streamInfo?.playMethod.rawValue ?? Strings.playerUnknown, isHighlighted: true)
            InfoRow(label: Strings.playerBackend, value: backendDisplayName)
            if let reason = viewModel.player.playbackFallbackReason {
                InfoRow(label: Strings.playerFallback, value: reason)
            }
            InfoRow(label: Strings.playerContainer, value: (streamInfo?.container ?? mediaSource?.container ?? Strings.playerUnknown).uppercased())
            InfoRow(label: Strings.playerBitrate, value: formatBitrate(mediaSource?.bitrate))
        }
    }

    private var backendDisplayName: String {
        switch viewModel.player.playbackBackendIdentifier {
        case "native": return "Native"
        case "mpv": return "mpv"
        default: return "mpv"
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if let video = videoStream {
            let playerType = String(describing: type(of: viewModel.player))
            let telemetry = viewModel.player.dynamicRangeTelemetrySnapshot()
            InfoSection(title: Strings.playerVideoSection) {
                if let w = video.width, let h = video.height {
                    let fps = video.realFrameRate.map { Strings.playerFpsSuffix(Int($0)) } ?? ""
                    InfoRow(label: Strings.playerResolution, value: Strings.playerResolutionValue(w, h, fps))
                }
                InfoRow(label: Strings.playerHdr, value: hdrType(for: video))
                InfoRow(label: Strings.playerPlayerType, value: playerType)
                InfoRow(label: Strings.playerCodec, value: videoCodec(for: video))
                if let depth = video.bitDepth {
                    InfoRow(label: Strings.playerBitDepth, value: Strings.playerBitDepthValue(depth))
                }
                if let br = video.bitRate {
                    InfoRow(label: Strings.playerVideoBitrate, value: formatBitrate(br))
                }
                // Native backend frame counters
                if let decoded = telemetry["native_frames_decoded"],
                   let dropped = telemetry["native_frames_dropped"] {
                    InfoRow(label: Strings.playerFrames, value: Strings.playerFramesValue(decoded, dropped))
                }
                // mpv HDR metadata
                Group {
                    if let hdrType = telemetry["mpv_hdr_type"], hdrType != "unknown" {
                        InfoRow(label: Strings.playerHdrMetadata, value: hdrType)
                    }
                    if let maxCLL = telemetry["mpv_max_cll"], maxCLL != "unknown" {
                        InfoRow(label: Strings.playerMaxCll, value: Strings.playerNitsValue(maxCLL))
                    }
                    if let maxFALL = telemetry["mpv_max_fall"], maxFALL != "unknown" {
                        InfoRow(label: Strings.playerMaxFall, value: Strings.playerNitsValue(maxFALL))
                    }
                }
                // Tone mapping diagnostics
                Group {
                    InfoRow(label: Strings.playerTelemetry, value: telemetry["mpv_dynamic_range_telemetry"] ?? Strings.playerEmpty(telemetry.count))
                    InfoRow(label: Strings.playerToneMap, value: telemetry["mpv_intent_tone_mapping"] ?? Strings.playerNA)
                    InfoRow(label: Strings.playerSinkHdr, value: telemetry["mpv_intent_sink_hdr_capable"] ?? Strings.playerNA)
                    InfoRow(label: Strings.playerContent, value: telemetry["mpv_intent_content_range"] ?? Strings.playerNA)
                }
                Group {
                    if let inPrim = telemetry["mpv_input_primaries"] {
                        InfoRow(label: Strings.playerInColor, value: Strings.playerColorPair(inPrim, telemetry["mpv_input_transfer"] ?? Strings.playerUnknownShort))
                    }
                    if let outPrim = telemetry["mpv_output_primaries"] {
                        InfoRow(label: Strings.playerOutColor, value: Strings.playerColorPair(outPrim, telemetry["mpv_output_transfer"] ?? Strings.playerUnknownShort))
                    }
                    if let aPrim = telemetry["mpv_active_target_prim"] {
                        InfoRow(label: Strings.playerTarget, value: Strings.playerColorPair(aPrim, telemetry["mpv_active_target_trc"] ?? Strings.playerUnknownShort))
                    }
                    if let aTM = telemetry["mpv_active_tone_mapping"] {
                        InfoRow(label: Strings.playerActiveToneMapping, value: aTM)
                    }
                    if let aHw = telemetry["mpv_active_hwdec"] {
                        InfoRow(label: Strings.playerHardwareDecode, value: aHw)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        if let audio = activeAudioStream {
            InfoSection(title: Strings.playerAudioSection) {
                InfoRow(label: Strings.playerTrack, value: audio.displayTitle ?? audio.language ?? Strings.playerUnknown)
                InfoRow(label: Strings.playerCodec, value: audioCodec(for: audio))
                InfoRow(label: Strings.playerChannels, value: audioChannels(for: audio))
                if let br = audio.bitRate {
                    InfoRow(label: Strings.playerAudioBitrate, value: formatBitrate(br))
                }
                if let sr = audio.sampleRate {
                    InfoRow(label: Strings.playerSampleRate, value: Strings.playerSampleRateValue(Double(sr) / 1000.0))
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleSection: some View {
        if let sub = activeSubtitleStream {
            InfoSection(title: Strings.subtitleTrack) {
                InfoRow(label: Strings.playerTrack, value: sub.displayTitle ?? sub.language ?? Strings.playerUnknown)
                InfoRow(label: Strings.playerFormat, value: (sub.codec ?? Strings.playerUnknown).uppercased())
                InfoRow(label: Strings.playerType, value: sub.isExternal ? Strings.playerExternal : Strings.playerEmbedded)
            }
        }
    }

    private func formatBitrate(_ bitrate: Int?) -> String {
        guard let bitrate, bitrate > 0 else { return Strings.playerUnknown }
        if bitrate >= 1_000_000 {
            return Strings.playerBitrateMbps(Double(bitrate) / 1_000_000)
        }
        if bitrate >= 1_000 {
            return Strings.playerBitrateKbps(bitrate / 1_000)
        }
        return Strings.playerBitrateBps(bitrate)
    }

    private func hdrType(for stream: ServerMediaStream) -> String {
        let rangeType = stream.videoRangeType ?? ""
        let telemetry = viewModel.player.dynamicRangeTelemetrySnapshot()
        let isDV = rangeType.contains("DOVI") || rangeType.contains("DoVi")

        if isDV, let profile = telemetry["native_dv_profile"], let level = telemetry["native_dv_level"] {
            return Strings.playerDolbyVisionProfile(profile, level)
        }
        if isDV { return Strings.playerDolbyVision }
        if rangeType.contains("HDR10Plus") || rangeType.contains("HDR10+") { return Strings.playerHdr10Plus }
        if rangeType.contains("HDR10") { return Strings.playerHdr10 }
        if rangeType.contains("HLG") { return Strings.playerHlg }
        let range = stream.videoRange ?? ""
        if rangeType.contains("HDR") || range == "HDR" { return Strings.playerHdrValue }
        return Strings.playerSdr
    }

    private func videoCodec(for stream: ServerMediaStream) -> String {
        var codec = (stream.codec ?? Strings.playerUnknown).uppercased()
        switch codec {
        case "HEVC": codec = Strings.playerCodecHevc
        case "H264", "AVC": codec = Strings.playerCodecAvc
        case "AV1": codec = Strings.playerCodecAv1
        case "VP9": codec = Strings.playerCodecVp9
        default: break
        }
        if let profile = stream.profile { codec += Strings.playerCodecProfileSuffix(profile) }
        if let level = stream.level { codec += Strings.playerCodecLevelSuffix(Int(level)) }
        return codec
    }

    private func audioCodec(for stream: ServerMediaStream) -> String {
        let raw = (stream.codec ?? Strings.playerUnknown).uppercased()
        switch raw {
        case "EAC3": return Strings.playerAudioCodecEac3
        case "AC3": return Strings.playerAudioCodecAc3
        case "TRUEHD": return Strings.playerAudioCodecTrueHd
        case "DTS": return Strings.playerAudioCodecDts
        case "AAC": return Strings.playerAudioCodecAac
        case "FLAC": return Strings.playerAudioCodecFlac
        case "OPUS": return Strings.playerAudioCodecOpus
        case "VORBIS": return Strings.playerAudioCodecVorbis
        default: return raw
        }
    }

    private func audioChannels(for stream: ServerMediaStream) -> String {
        guard let channels = stream.channels else { return Strings.playerUnknown }
        switch channels {
        case 1: return Strings.playerMono
        case 2: return Strings.playerStereo
        case 6: return "5.1"
        case 8: return "7.1"
        default: return Strings.playerChannelsCount(channels)
        }
    }
}

// MARK: - Supporting Views

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.captionXs)
                .bold()
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.bottom, 2)

            content
        }
        .padding(SpaceTokens.spaceSm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var isHighlighted: Bool = false
    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2xs)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.caption2xs)
                .foregroundColor(isHighlighted ? theme.accent : theme.colorScheme.onBackground)
                .lineLimit(1)

            Spacer()
        }
    }
}
