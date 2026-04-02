import SwiftUI

enum TrackSelectorMode: String, Identifiable {
    case audio, subtitle, version
    var id: String { rawValue }
}

struct TrackSelectorDialog: View {
    let mode: TrackSelectorMode
    let streams: [ServerMediaStream]
    let selectedIndex: Int?
    let onSelect: (Int?) -> Void
    let onDismiss: () -> Void
    var onDownloadSubtitles: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedIndex: Int?

    private var title: String {
        mode == .audio ? "Audio" : "Subtitles"
    }

    private var filteredStreams: [ServerMediaStream] {
        streams.filter { $0.type == (mode == .audio ? .audio : .subtitle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, SpaceTokens.spaceMd)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SpaceTokens.spaceXs) {
                    if mode == .subtitle {
                        FocusableTrackSelectorRow(
                            label: "None",
                            detail: nil,
                            isSelected: selectedIndex == nil || selectedIndex == -1,
                            action: { onSelect(-1) }
                        )
                        .focused($focusedIndex, equals: -1)
                    }

                    ForEach(filteredStreams, id: \.index) { stream in
                        FocusableTrackSelectorRow(
                            label: stream.displayTitle ?? stream.language ?? "Track \(stream.index)",
                            detail: streamDetail(stream),
                            isSelected: selectedIndex == stream.index,
                            action: { onSelect(stream.index) }
                        )
                        .focused($focusedIndex, equals: stream.index)
                    }

                    if let onDownloadSubtitles {
                        Divider().background(Color.white.opacity(0.2))
                            .padding(.vertical, SpaceTokens.spaceXs)

                        FocusableTrackSelectorRow(
                            label: "Download subtitles...",
                            detail: "Search using OpenSubtitles",
                            isSelected: false,
                            action: onDownloadSubtitles
                        )
                    }
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }

            HStack {
                Spacer()
                DetailsGlassDialogButton(title: "Cancel", action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .cornerRadius(RadiusTokens.large)
    }

    private func streamDetail(_ stream: ServerMediaStream) -> String? {
        var parts: [String] = []
        if let codec = stream.codec, !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        if let channels = stream.channels {
            switch channels {
            case 1: parts.append("Mono")
            case 2: parts.append("Stereo")
            case 6: parts.append("5.1")
            case 8: parts.append("7.1")
            default: parts.append("\(channels)ch")
            }
        }
        if stream.isDefault { parts.append("Default") }
        if stream.isForced { parts.append("Forced") }
        if stream.isExternal { parts.append("External") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct FocusableTrackSelectorRow: View {
    let label: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? theme.accent : theme.colorScheme.onBackground.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(label)
                            .font(.bodyLg)
                            .foregroundColor(theme.colorScheme.onBackground)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let detail {
                        Text(detail)
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.24) : Color.white.opacity(0.08))
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.22), lineWidth: isFocused ? 2 : 1)
                    )
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

// MARK: - Version Selector

struct VersionSelectorDialog: View {
    let sources: [ServerMediaSource]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.selectVersion)
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, SpaceTokens.spaceMd)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SpaceTokens.spaceXs) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        FocusableTrackSelectorRow(
                            label: source.name ?? "Version \(index + 1)",
                            detail: versionDetail(source),
                            isSelected: selectedIndex == index,
                            action: { onSelect(index) }
                        )
                        .focused($focusedIndex, equals: index)
                    }
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }

            HStack {
                Spacer()
                DetailsGlassDialogButton(title: "Cancel", action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .cornerRadius(RadiusTokens.large)
    }

    private func versionDetail(_ source: ServerMediaSource) -> String? {
        var parts: [String] = []
        if let container = source.container, !container.isEmpty {
            parts.append(container.uppercased())
        }
        if let bitrate = source.bitrate {
            let mbps = Double(bitrate) / 1_000_000
            parts.append(String(format: "%.1f Mbps", mbps))
        }
        if let video = source.mediaStreams.first(where: { $0.type == .video }) {
            if let w = video.width, let h = video.height {
                parts.append("\(w)×\(h)")
            }
            if let codec = video.codec {
                parts.append(codec.uppercased())
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
