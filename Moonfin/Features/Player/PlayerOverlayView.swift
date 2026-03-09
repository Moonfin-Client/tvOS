import SwiftUI

struct PlayerOverlayView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedControl: ControlFocus?

    enum ControlFocus: Hashable {
        case seekbar
        case playPause
        case rewind
        case fastForward
        case closedCaptions
        case audioTrack
        case previous
        case next
        case chapters
        case cast
        case speed
        case zoom
    }

    var body: some View {
        VStack {
            headerSection
            Spacer()
            controlsSection
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .transition(.opacity)
        .onAppear { focusedControl = .playPause }
        .defaultFocus($focusedControl, .playPause)
        .onExitCommand {
            if viewModel.isScrubbing {
                viewModel.cancelScrub()
            } else {
                viewModel.hideOverlay()
            }
        }
        .onChange(of: focusedControl) { newFocus in
            viewModel.resetHideTimer()
            if newFocus != .seekbar && viewModel.isScrubbing {
                viewModel.commitScrub()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .background(
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -80)
            .padding(.top, -60)
            .frame(height: 200)
        )
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            primaryControlRow
            seekbarRow
            secondaryControlRow
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -80)
            .padding(.bottom, -60)
            .frame(height: 340)
            .offset(y: 60),
            alignment: .bottom
        )
    }

    private var primaryControlRow: some View {
        HStack(spacing: 12) {
            overlayButton(icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill",
                          focus: .playPause) {
                viewModel.togglePlayPause()
            }

            overlayButton(icon: "backward.fill", focus: .rewind) {
                viewModel.seekBackward()
            }

            overlayButton(icon: "forward.fill", focus: .fastForward) {
                viewModel.seekForward()
            }

            if !viewModel.player.subtitleTracks.isEmpty {
                overlayButton(icon: "captions.bubble", focus: .closedCaptions) {
                    viewModel.showTrackSelection(tab: .subtitles)
                }
            }

            if viewModel.player.audioTracks.count > 1 {
                overlayButton(icon: "speaker.wave.2", focus: .audioTrack) {
                    viewModel.showTrackSelection(tab: .audio)
                }
            }

            Spacer()

            if !viewModel.endTimeText.isEmpty {
                Text(viewModel.endTimeText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }

    private var seekbarRow: some View {
        PlayerSeekBar(
            progress: viewModel.isScrubbing ? viewModel.scrubPosition : viewModel.player.position,
            bufferProgress: 0,
            isFocused: focusedControl == .seekbar
        )
        .focusable()
        .focused($focusedControl, equals: .seekbar)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if !viewModel.isScrubbing { viewModel.beginScrub() }
                viewModel.updateScrub(by: -0.02)
                viewModel.resetHideTimer()
            case .right:
                if !viewModel.isScrubbing { viewModel.beginScrub() }
                viewModel.updateScrub(by: 0.02)
                viewModel.resetHideTimer()
            default:
                break
            }
        }
        .onPlayPauseCommand {
            if viewModel.isScrubbing {
                viewModel.commitScrub()
            } else {
                viewModel.togglePlayPause()
            }
        }
    }

    private var secondaryControlRow: some View {
        HStack(spacing: 12) {
            if viewModel.playbackManager.hasPrevious {
                overlayButton(icon: "backward.end.fill", focus: .previous) {
                    Task { await viewModel.playbackManager.playPrevious() }
                }
            }

            if viewModel.playbackManager.hasNext {
                overlayButton(icon: "forward.end.fill", focus: .next) {
                    Task { await viewModel.playbackManager.playNext() }
                }
            }

            if viewModel.hasChapters {
                overlayButton(icon: "list.bullet", focus: .chapters) {
                    viewModel.showChapterSelection()
                }
            }

            if viewModel.hasCast {
                overlayButton(icon: "person.2", focus: .cast) {
                    viewModel.showCastList()
                }
            }

            overlayButton(icon: "gauge.with.dots.needle.67percent", focus: .speed) {
                viewModel.showTrackSelection(tab: .speed)
            }

            overlayButton(icon: viewModel.player.zoomMode.iconName, focus: .zoom) {
                viewModel.cycleZoom()
            }

            Spacer()

            Text(viewModel.positionText)
                .font(.bodySm)
                .foregroundColor(.white.opacity(0.7))
                .monospacedDigit()
        }
    }

    private func overlayButton(
        icon: String,
        focus: ControlFocus,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            viewModel.resetHideTimer()
        }) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerButtonStyle())
        .focused($focusedControl, equals: focus)
    }
}

struct PlayerButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isFocused ? Color(white: 0.27) : .white)
            .padding(10)
            .background(
                Circle()
                    .fill(isFocused ? Color(white: 0.8, opacity: 0.9) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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


