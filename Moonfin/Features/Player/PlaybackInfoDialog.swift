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
            Text("Playback Information")
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, SpaceTokens.spaceMd)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                    playbackSection
                    videoSection
                    audioSection
                    subtitleSection
                }
                .padding(.horizontal, SpaceTokens.spaceLg)
            }
            .frame(maxHeight: 550)

            HStack {
                Spacer()
                FocusableDialogButton(title: "Close", action: { viewModel.hidePlaybackInfo() })
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 650)
        .background(theme.colorScheme.surface)
        .cornerRadius(RadiusTokens.large)
        .onExitCommand { viewModel.hidePlaybackInfo() }
    }

    private var playbackSection: some View {
        InfoSection(title: "Playback") {
            InfoRow(label: "Play Method", value: streamInfo?.playMethod.rawValue ?? "Unknown", isHighlighted: true)
            InfoRow(label: "Container", value: (streamInfo?.container ?? mediaSource?.container ?? "Unknown").uppercased())
            InfoRow(label: "Bitrate", value: formatBitrate(mediaSource?.bitrate))
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if let video = videoStream {
            InfoSection(title: "Video") {
                if let w = video.width, let h = video.height {
                    let fps = video.realFrameRate.map { " @ \(Int($0))fps" } ?? ""
                    InfoRow(label: "Resolution", value: "\(w)×\(h)\(fps)")
                }
                InfoRow(label: "HDR", value: hdrType(for: video))
                InfoRow(label: "Codec", value: videoCodec(for: video))
                if let depth = video.bitDepth {
                    InfoRow(label: "Bit Depth", value: "\(depth)-bit")
                }
                if let br = video.bitRate {
                    InfoRow(label: "Video Bitrate", value: formatBitrate(br))
                }
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        if let audio = activeAudioStream {
            InfoSection(title: "Audio") {
                InfoRow(label: "Track", value: audio.displayTitle ?? audio.language ?? "Unknown")
                InfoRow(label: "Codec", value: audioCodec(for: audio))
                InfoRow(label: "Channels", value: audioChannels(for: audio))
                if let br = audio.bitRate {
                    InfoRow(label: "Audio Bitrate", value: formatBitrate(br))
                }
                if let sr = audio.sampleRate {
                    InfoRow(label: "Sample Rate", value: String(format: "%.1f kHz", Double(sr) / 1000.0))
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleSection: some View {
        if let sub = activeSubtitleStream {
            InfoSection(title: "Subtitles") {
                InfoRow(label: "Track", value: sub.displayTitle ?? sub.language ?? "Unknown")
                InfoRow(label: "Format", value: (sub.codec ?? "Unknown").uppercased())
                InfoRow(label: "Type", value: sub.isExternal ? "External" : "Embedded")
            }
        }
    }

    private func formatBitrate(_ bitrate: Int?) -> String {
        guard let bitrate, bitrate > 0 else { return "Unknown" }
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        }
        if bitrate >= 1_000 {
            return "\(bitrate / 1_000) Kbps"
        }
        return "\(bitrate) bps"
    }

    private func hdrType(for stream: ServerMediaStream) -> String {
        let rangeType = stream.videoRangeType ?? ""
        if rangeType.contains("DOVI") || rangeType.contains("DoVi") { return "Dolby Vision" }
        if rangeType.contains("HDR10Plus") || rangeType.contains("HDR10+") { return "HDR10+" }
        if rangeType.contains("HDR10") { return "HDR10" }
        if rangeType.contains("HLG") { return "HLG" }
        let range = stream.videoRange ?? ""
        if rangeType.contains("HDR") || range == "HDR" { return "HDR" }
        return "SDR"
    }

    private func videoCodec(for stream: ServerMediaStream) -> String {
        var codec = (stream.codec ?? "Unknown").uppercased()
        switch codec {
        case "HEVC": codec = "HEVC (H.265)"
        case "H264", "AVC": codec = "AVC (H.264)"
        case "AV1": codec = "AV1"
        case "VP9": codec = "VP9"
        default: break
        }
        if let profile = stream.profile { codec += " \(profile)" }
        if let level = stream.level { codec += " @L\(Int(level))" }
        return codec
    }

    private func audioCodec(for stream: ServerMediaStream) -> String {
        let raw = (stream.codec ?? "Unknown").uppercased()
        switch raw {
        case "EAC3": return "E-AC3 (Dolby Digital Plus)"
        case "AC3": return "AC3 (Dolby Digital)"
        case "TRUEHD": return "TrueHD"
        case "DTS": return "DTS"
        case "AAC": return "AAC"
        case "FLAC": return "FLAC"
        case "OPUS": return "Opus"
        case "VORBIS": return "Vorbis"
        default: return raw
        }
    }

    private func audioChannels(for stream: ServerMediaStream) -> String {
        guard let channels = stream.channels else { return "Unknown" }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) channels"
        }
    }
}

// MARK: - Supporting Views

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(title)
                .font(.bodyLg)
                .bold()
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.bottom, SpaceTokens.spaceXs)

            content
        }
        .padding(SpaceTokens.spaceMd)
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
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.bodyMd)
                .foregroundColor(isHighlighted ? theme.accent : theme.colorScheme.onBackground)
                .lineLimit(1)

            Spacer()
        }
    }
}
