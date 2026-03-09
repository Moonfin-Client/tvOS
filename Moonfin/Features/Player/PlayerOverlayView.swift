import SwiftUI

struct PlayerOverlayView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedControl: ControlFocus?

    enum ControlFocus: Hashable {
        case playPause
        case rewind
        case fastForward
        case previous
        case next
        case tracks
        case speed
    }

    var body: some View {
        VStack {
            headerSection
            Spacer()
            controlsSection
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 27)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .onChange(of: viewModel.overlayVisible) { visible in
            if visible {
                focusedControl = .playPause
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Text(viewModel.title)
                .font(.title2xl)
                .foregroundColor(.white)
                .lineLimit(1)

            if !viewModel.subtitle.isEmpty {
                Text(viewModel.subtitle)
                    .font(.bodyLg)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SpaceTokens.spaceMd)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -48)
            .padding(.top, -27)
        )
    }

    private var controlsSection: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            PlayerSeekBar(
                progress: viewModel.player.position,
                bufferProgress: 0,
                isFocused: false
            )

            HStack(spacing: SpaceTokens.spaceLg) {
                controlButtonRow
                Spacer()
                Text(viewModel.positionText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.8))
                    .monospacedDigit()
            }
        }
        .padding(.top, SpaceTokens.spaceMd)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -48)
            .padding(.bottom, -27)
        )
    }

    private var controlButtonRow: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if viewModel.playbackManager.hasPrevious {
                overlayButton(
                    icon: "backward.end.fill",
                    focus: .previous
                ) {
                    Task { await viewModel.playbackManager.playPrevious() }
                }
            }

            overlayButton(
                icon: "gobackward.15",
                focus: .rewind
            ) {
                viewModel.seekBackward()
            }

            overlayButton(
                icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill",
                focus: .playPause,
                size: 44
            ) {
                viewModel.togglePlayPause()
            }

            overlayButton(
                icon: "goforward.15",
                focus: .fastForward
            ) {
                viewModel.seekForward()
            }

            if viewModel.playbackManager.hasNext {
                overlayButton(
                    icon: "forward.end.fill",
                    focus: .next
                ) {
                    Task { await viewModel.playbackManager.playNext() }
                }
            }

            Spacer().frame(width: SpaceTokens.spaceSm)

            overlayButton(
                icon: "textformat.subscript",
                focus: .tracks
            ) {
                viewModel.showTrackSelection(tab: .audio)
            }

            overlayButton(
                icon: "gauge.with.dots.needle.67percent",
                focus: .speed
            ) {
                viewModel.showTrackSelection(tab: .speed)
            }
        }
    }

    private func overlayButton(
        icon: String,
        focus: ControlFocus,
        size: CGFloat = 32,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(.white)
                .frame(width: size + 24, height: size + 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(OverlayButtonStyle(isFocused: focusedControl == focus))
        .focused($focusedControl, equals: focus)
    }
}

struct OverlayButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.2 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
