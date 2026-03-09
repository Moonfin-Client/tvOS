import SwiftUI

enum TrackSelectionTab: String, CaseIterable {
    case audio = "Audio"
    case subtitles = "Subtitles"
    case speed = "Speed"
}

struct TrackSelectionView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @State private var selectedTab: TrackSelectionTab

    init(viewModel: VideoPlayerViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._selectedTab = State(initialValue: viewModel.trackSelectionTab)
    }

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 0) {
                tabBar
                Divider().background(Color.white.opacity(0.2))
                tabContent
            }
            .frame(width: 400)
            .background(theme.colorScheme.surface.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.large))
        }
        .padding(48)
        .transition(.opacity)
        .onExitCommand {
            viewModel.hideTrackSelection()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TrackSelectionTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.bodyMd)
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpaceTokens.spaceMd)
                }
                .buttonStyle(TrackTabButtonStyle(isActive: selectedTab == tab))
            }
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: SpaceTokens.space2xs) {
                switch selectedTab {
                case .audio:
                    audioTrackList
                case .subtitles:
                    subtitleTrackList
                case .speed:
                    speedList
                }
            }
            .padding(SpaceTokens.spaceMd)
        }
        .frame(maxHeight: 500)
    }

    private var audioTrackList: some View {
        ForEach(viewModel.player.audioTracks) { track in
            trackRow(
                name: track.name,
                isSelected: track.id == viewModel.player.currentAudioTrackIndex
            ) {
                viewModel.playbackManager.setAudioTrack(track.id)
            }
        }
    }

    private var subtitleTrackList: some View {
        Group {
            trackRow(
                name: "Off",
                isSelected: viewModel.player.currentSubtitleTrackIndex == -1
            ) {
                viewModel.player.disableSubtitles()
            }

            ForEach(viewModel.player.subtitleTracks) { track in
                trackRow(
                    name: track.name,
                    isSelected: track.id == viewModel.player.currentSubtitleTrackIndex
                ) {
                    viewModel.playbackManager.setSubtitleTrack(track.id)
                }
            }

            Divider().background(Color.white.opacity(0.2))

            subtitleDelayControls
        }
    }

    private var subtitleDelayControls: some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            Text("Subtitle Delay: \(subtitleDelayLabel)")
                .font(.bodySm)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: SpaceTokens.spaceMd) {
                delayButton("−0.25s") { viewModel.adjustSubtitleDelay(by: -0.25) }
                delayButton("Reset") { viewModel.resetSubtitleDelay() }
                delayButton("+0.25s") { viewModel.adjustSubtitleDelay(by: 0.25) }
            }
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
    }

    private func delayButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.bodySm)
                .foregroundColor(.white)
                .padding(.horizontal, SpaceTokens.spaceMd)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(RoundedRectangle(cornerRadius: RadiusTokens.small).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(TrackRowButtonStyle())
    }

    private var subtitleDelayLabel: String {
        let delay = viewModel.subtitleDelay
        if abs(delay) < 0.001 { return "0s" }
        return String(format: "%+gs", delay)
    }

    private var speedList: some View {
        ForEach(speedOptions, id: \.self) { speed in
            trackRow(
                name: speedLabel(speed),
                isSelected: abs(viewModel.player.rate - speed) < 0.01
            ) {
                viewModel.setPlaybackSpeed(speed)
            }
        }
    }

    private func trackRow(
        name: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .font(.bodyMd)
                    .foregroundColor(.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(theme.accent)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackRowButtonStyle(isSelected: isSelected))
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "Normal" }
        if speed == floor(speed) { return "\(Int(speed))x" }
        return String(format: "%gx", speed)
    }
}

struct TrackTabButtonStyle: ButtonStyle {
    let isActive: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.3) : (isActive ? Color.white.opacity(0.1) : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}

struct TrackRowButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.25) : (isSelected ? Color.white.opacity(0.1) : .clear))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
