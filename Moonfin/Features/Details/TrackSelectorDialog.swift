import SwiftUI

enum TrackSelectorMode: String, Identifiable {
    case audio, subtitle
    var id: String { rawValue }
}

struct TrackSelectorDialog: View {
    let mode: TrackSelectorMode
    let streams: [ServerMediaStream]
    let selectedIndex: Int?
    let onSelect: (Int?) -> Void
    let onDismiss: () -> Void

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
                            action: { onSelect(nil) }
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
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }

            HStack {
                Spacer()
                FocusableDialogButton(title: "Cancel", action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 600)
        .background(theme.colorScheme.surface)
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

private struct FocusableTrackSelectorRow: View {
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
                    .foregroundColor(isFocused ? .black : (isSelected ? theme.accent : theme.colorScheme.onBackground.opacity(0.5)))

                VStack(alignment: .leading, spacing: 2) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(label)
                            .font(.bodyLg)
                            .foregroundColor(isFocused ? .black : theme.colorScheme.onBackground)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if let detail {
                        Text(detail)
                            .font(.captionXs)
                            .foregroundColor(isFocused ? .black.opacity(0.6) : theme.colorScheme.onBackground.opacity(0.5))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
