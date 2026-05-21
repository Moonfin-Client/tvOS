import SwiftUI

struct PlayerOverlayView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @FocusState private var focusedControl: ControlFocus?
    @Namespace private var controlsFocusNamespace
    @StateObject private var trickPlayLoader = TrickPlayImageLoader()

    private static let headerGradientColors: [Color] = [.black.opacity(0.8), .clear]
    private static let controlsGradientColors: [Color] = [.clear, .black.opacity(0.85)]
    private static let transportButtonSpacing: CGFloat = 8
    private static let secondaryButtonSpacing: CGFloat = 8
    private static let clusterSpacing: CGFloat = 12
    private static let buttonSize: CGFloat = 52
    private static let iconSize: CGFloat = 24
    private static let tooltipVerticalOffset: CGFloat = 22

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
        case queueNext
        case speed
        case quality
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if let logoUrl = viewModel.logoUrl {
                    CachedImage(urlString: logoUrl, contentMode: .fit)
                        .frame(height: 82)
                        .frame(maxWidth: 460, alignment: .leading)
                } else {
                    Text(viewModel.title)
                        .font(.title2xl)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                if !viewModel.subtitle.isEmpty {
                    Text(viewModel.subtitle)
                        .font(.bodyLg)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            if viewModel.isLiveTV {
                liveBadge
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
            .frame(height: 260)
        )
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.bodySm)
            Text("LIVE")
                .font(.bodySm)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.95))
        )
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            if !viewModel.isLiveTV {
                trickPlayPreviewSection
                seekbarSection
            }
            bottomControlsRow
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

    private var seekbarSection: some View {
        VStack(spacing: 4) {
            if !viewModel.endTimeText.isEmpty {
                HStack {
                    Spacer()
                    Text(viewModel.endTimeText)
                        .font(.bodySm)
                        .foregroundColor(.white.opacity(0.7))
                        .monospacedDigit()
                }
                .padding(.trailing, 16)
            }

            seekbarRow

            HStack {
                Text(viewModel.currentTimeText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()

                Spacer()

                Text(viewModel.durationText)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
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
            case .up:
                if viewModel.isScrubbing { viewModel.commitScrub() }
            case .down:
                if viewModel.isScrubbing { viewModel.commitScrub() }
                focusedControl = .playPause
                DispatchQueue.main.async {
                    focusedControl = .playPause
                }
                viewModel.resetHideTimer()
            default:
                break
            }
        }
        .onTapGesture {
            viewModel.togglePlayPause()
            viewModel.resetHideTimer()
        }
    }

    private var bottomControlsRow: some View {
        HStack(spacing: Self.clusterSpacing) {
            transportCluster
            secondaryCluster
            Spacer(minLength: 0)
        }
        .focusScope(controlsFocusNamespace)
        .overlayPreferenceValue(ControlButtonAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let focused = focusedControl,
                   let tooltip = tooltipText(for: focused),
                   let anchor = anchors[focused] {
                    let rect = proxy[anchor]
                    Text(tooltip)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.78))
                        )
                        .position(x: rect.midX, y: rect.minY - Self.tooltipVerticalOffset)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var transportCluster: some View {
        HStack(spacing: Self.transportButtonSpacing) {
            if !viewModel.isLiveTV, viewModel.playbackManager.hasPrevious {
                overlayButton(icon: "backward.end.fill", focus: .previous) {
                    Task { await viewModel.playPrevious() }
                }
            }

            if !viewModel.isLiveTV {
                overlayButton(icon: "backward.fill", focus: .rewind) {
                    viewModel.seekBackward()
                }
            }

            overlayButton(icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill", focus: .playPause) {
                viewModel.togglePlayPause()
            }
            .prefersDefaultFocus(in: controlsFocusNamespace)

            if !viewModel.isLiveTV {
                overlayButton(icon: "forward.fill", focus: .fastForward) {
                    viewModel.seekForward()
                }
            }

            if !viewModel.isLiveTV, viewModel.playbackManager.hasNext {
                overlayButton(icon: "forward.end.fill", focus: .next) {
                    Task { await viewModel.playNext() }
                }
            }
        }
    }

    private var secondaryCluster: some View {
        HStack(spacing: Self.secondaryButtonSpacing) {
            if viewModel.isLiveTV {
                overlayButton(icon: "list.bullet", focus: .channels) {
                    viewModel.showChannelList()
                }

                overlayButton(icon: "gauge.with.dots.needle.67percent", focus: .speed) {
                    viewModel.showTrackSelection(tab: .speed)
                }
            } else {
                if viewModel.syncPlayActive, viewModel.nextQueueItem != nil {
                    overlayButton(icon: "text.line.first.and.arrowtriangle.forward", focus: .queueNext) {
                        viewModel.queueNextItemForSyncPlay()
                    }
                }

                overlayButton(icon: "gauge.with.dots.needle.67percent", focus: .speed) {
                    viewModel.showTrackSelection(tab: .speed)
                }

                if viewModel.hasChapters {
                    overlayButton(icon: "list.bullet", focus: .chapters) {
                        viewModel.showChapterSelection()
                    }
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

                if viewModel.hasCast {
                    overlayButton(icon: "person.2", focus: .cast) {
                        viewModel.showCastList()
                    }
                }
            }

            overlayButton(icon: "line.3.horizontal.decrease", focus: .quality) {
                viewModel.showTrackSelection(tab: .quality)
            }

            overlayButton(icon: viewModel.player.zoomMode.iconName, focus: .zoom) {
                viewModel.cycleZoom()
            }

            overlayButton(icon: "info.circle", focus: .info) {
                viewModel.showPlaybackInfo()
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
                .font(.system(size: Self.iconSize, weight: .medium))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerButtonStyle())
        .focused($focusedControl, equals: focus)
        .anchorPreference(key: ControlButtonAnchorPreferenceKey.self, value: .bounds) { anchor in
            [focus: anchor]
        }
    }

    private func tooltipText(for focus: ControlFocus) -> String? {
        switch focus {
        case .playPause:
            return viewModel.player.isPlaying ? "Pause" : "Play"
        case .rewind:
            return "Seek Back"
        case .fastForward:
            return "Seek Forward"
        case .closedCaptions:
            return "Subtitles"
        case .audioTrack:
            return "Audio"
        case .previous:
            return "Previous"
        case .next:
            return "Next"
        case .chapters:
            return "Chapters"
        case .cast:
            return "Cast & Crew"
        case .channels:
            return "Channels"
        case .queueNext:
            return "Queue Next"
        case .speed:
            return "Playback Speed"
        case .quality:
            return "Playback Quality"
        case .zoom:
            return "Zoom Mode"
        case .info:
            return "Playback Information"
        case .seekbar:
            return nil
        }
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

private struct ControlButtonAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [PlayerOverlayView.ControlFocus: Anchor<CGRect>] = [:]

    static func reduce(value: inout [PlayerOverlayView.ControlFocus: Anchor<CGRect>], nextValue: () -> [PlayerOverlayView.ControlFocus: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

