import SwiftUI

struct PlayerOverlayView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedControl: ControlFocus?
    @StateObject private var trickPlayLoader = TrickPlayImageLoader()

    private static let headerGradientColors: [Color] = [.black.opacity(0.8), .clear]
    private static let controlsGradientColors: [Color] = [.clear, .black.opacity(0.85)]
    private static let rowButtonSpacing: CGFloat = 20
    private static let buttonSize: CGFloat = 46

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
        case channels
        case jumpToLive
        case queueNext
        case speed
        case zoom
        case info
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
        .onAppear { focusedControl = initialFocusControl }
        .defaultFocus($focusedControl, initialFocusControl)
        .onPlayPauseCommand {
            if viewModel.isScrubbing {
                viewModel.commitScrub()
            } else {
                viewModel.togglePlayPause()
            }
            viewModel.resetHideTimer()
        }
        .onExitCommand {
            viewModel.markExitCommandHandled()
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

    private var initialFocusControl: ControlFocus {
        viewModel.isLiveTV ? .playPause : .seekbar
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
                colors: Self.headerGradientColors,
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
            if !viewModel.isLiveTV {
                trickPlayPreviewSection
                seekbarRow
            }
            secondaryControlRow
        }
        .background(
            LinearGradient(
                colors: Self.controlsGradientColors,
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
        HStack(spacing: Self.rowButtonSpacing) {
            overlayButton(icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill",
                          focus: .playPause) {
                viewModel.togglePlayPause()
            }

            if viewModel.isLiveTV, viewModel.canJumpToLive {
                overlayButton(icon: "dot.radiowaves.left.and.right", focus: .jumpToLive) {
                    Task { await viewModel.jumpToLive() }
                }
            }

            if !viewModel.isLiveTV {
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
            }

            Spacer()

            if !viewModel.isLiveTV && !viewModel.endTimeText.isEmpty {
                Text(viewModel.endTimeText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }

    private var currentTrickPlayInfo: TrickPlayInfo? {
        guard viewModel.playbackManager.trickPlayEnabled,
              let entry = viewModel.playbackManager.currentEntry else { return nil }
        return entry.item.trickPlayInfo(for: entry.mediaSourceId)
    }

    @ViewBuilder
    private var trickPlayPreviewSection: some View {
        if viewModel.isScrubbing, let info = currentTrickPlayInfo {
            GeometryReader { geo in
                TrickPlayPreview(
                    thumbnail: trickPlayLoader.thumbnail,
                    position: CGFloat(viewModel.scrubPosition),
                    barWidth: geo.size.width,
                    thumbSize: CGSize(width: CGFloat(info.width), height: CGFloat(info.height))
                )
            }
            .frame(height: CGFloat(info.height) * 1.5)
            .onChange(of: viewModel.scrubPosition) { newPosition in
                loadTrickPlayTile(position: newPosition, info: info)
            }
            .onAppear {
                loadTrickPlayTile(position: viewModel.scrubPosition, info: info)
            }
            .onDisappear {
                trickPlayLoader.clear()
            }
        }
    }

    private func loadTrickPlayTile(position: Float, info: TrickPlayInfo) {
        guard let entry = viewModel.playbackManager.currentEntry,
              let baseUrl = viewModel.playbackManager.serverBaseUrl else { return }
        let duration = viewModel.player.duration
        guard duration > 0 else { return }
        let positionMs = Int(Double(position) * duration * 1000)
        if let tile = trickPlayTile(
            positionMs: positionMs,
            info: info,
            itemId: entry.item.id,
            mediaSourceId: entry.mediaSourceId,
            baseUrl: baseUrl,
            accessToken: viewModel.playbackManager.serverAccessToken
        ) {
            trickPlayLoader.load(tile: tile)
        }
    }

    private var seekbarRow: some View {
        PlayerSeekBar(
            progress: viewModel.isScrubbing ? viewModel.scrubPosition : viewModel.player.position,
            bufferProgress: viewModel.player.bufferProgress,
            isFocused: focusedControl == .seekbar
        )
        .focusable()
        .focused($focusedControl, equals: .seekbar)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                if !viewModel.isScrubbing { viewModel.beginScrub() }
                viewModel.updateScrub(bySeconds: -viewModel.skipBackSeconds)
                viewModel.resetHideTimer()
            case .right:
                if !viewModel.isScrubbing { viewModel.beginScrub() }
                viewModel.updateScrub(bySeconds: viewModel.skipForwardSeconds)
                viewModel.resetHideTimer()
            case .up, .down:
                if viewModel.isScrubbing { viewModel.commitScrub() }
            default:
                break
            }
        }
        .onTapGesture {
            viewModel.togglePlayPause()
            viewModel.resetHideTimer()
        }
    }

    private var secondaryControlRow: some View {
        HStack(spacing: Self.rowButtonSpacing) {
            if !viewModel.isLiveTV {
                if viewModel.playbackManager.hasPrevious {
                    overlayButton(icon: "backward.end.fill", focus: .previous) {
                        Task { await viewModel.playPrevious() }
                    }
                }

                if viewModel.playbackManager.hasNext {
                    overlayButton(icon: "forward.end.fill", focus: .next) {
                        Task { await viewModel.playNext() }
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

                if viewModel.syncPlayActive, viewModel.nextQueueItem != nil {
                    overlayButton(icon: "text.line.first.and.arrowtriangle.forward", focus: .queueNext) {
                        viewModel.queueNextItemForSyncPlay()
                    }
                }
            } else {
                overlayButton(icon: "list.bullet", focus: .channels) {
                    viewModel.showChannelList()
                }
            }

            overlayButton(icon: "gauge.with.dots.needle.67percent", focus: .speed) {
                viewModel.showTrackSelection(tab: .speed)
            }

            overlayButton(icon: viewModel.player.zoomMode.iconName, focus: .zoom) {
                viewModel.cycleZoom()
            }

            overlayButton(icon: "info.circle", focus: .info) {
                viewModel.showPlaybackInfo()
            }

            Spacer()

            if !viewModel.isLiveTV {
                Text(viewModel.positionText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
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
                .frame(width: Self.buttonSize, height: Self.buttonSize)
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

