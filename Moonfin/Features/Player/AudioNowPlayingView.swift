import SwiftUI
import NukeUI

struct AudioNowPlayingView: View {
    private enum FocusTarget: Hashable {
        case lyrics, queue, favorite, seekbar, shuffle, previous, playPause, next, `repeat`
    }

    @ObservedObject var viewModel: AudioNowPlayingViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @EnvironmentObject private var router: NavigationRouter
    @FocusState private var focusedTarget: FocusTarget?

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .ignoresSafeArea()
        .defaultFocus($focusedTarget, .playPause)
        .onExitCommand {
            if viewModel.showQueue {
                viewModel.showQueue = false
                return
            }
            if viewModel.showLyrics {
                viewModel.showLyrics = false
                return
            }
            router.goBack()
        }
        .onChange(of: focusedTarget) { newValue in
            if newValue != .seekbar && viewModel.isScrubbing {
                viewModel.commitScrub()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Color.black

            if let url = viewModel.albumArtUrl {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .blur(radius: 40)
                .opacity(0.4)
                .scaleEffect(1.2)
            }
        }
    }

    private var contentLayer: some View {
        GeometryReader { geo in
            let totalPadding = SpaceTokens.space3xl * 3
            let panelWidth = max(360, (geo.size.width - totalPadding) / 2)
            let seekbarSidePadding = max(CGFloat(48), SpaceTokens.space3xl)

            VStack(spacing: SpaceTokens.spaceMd) {
                Spacer(minLength: 0)

                HStack(spacing: SpaceTokens.space3xl) {
                    VStack(spacing: SpaceTokens.spaceLg) {
                        albumArt
                        trackInfo
                    }
                    .frame(width: panelWidth)

                    if viewModel.showQueue {
                        queueList
                            .frame(width: panelWidth, height: 560)
                            .padding(.top, SpaceTokens.spaceSm)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if viewModel.showLyrics {
                        lyricsPanel
                            .frame(width: panelWidth, height: 560)
                            .padding(.top, SpaceTokens.spaceSm)
                            .transition(.opacity)
                    }
                }

                modeAndFavoriteRow

                progressSection
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, seekbarSidePadding)

                controlButtons
                    .frame(width: panelWidth)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(SpaceTokens.space3xl)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showQueue)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showLyrics)
    }

    private var modeAndFavoriteRow: some View {
        HStack(spacing: SpaceTokens.spaceXl) {
            if viewModel.lyricsAvailable {
                modeToggleButton(
                    icon: "quote.bubble",
                    focus: .lyrics,
                    isActive: viewModel.showLyrics,
                    action: viewModel.toggleLyrics
                )
            }

            favoriteButton

            modeToggleButton(
                icon: "music.note.list",
                focus: .queue,
                isActive: viewModel.showQueue,
                action: viewModel.toggleQueue
            )
        }
    }

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text("Lyrics")
                .font(.titleXl)
                .foregroundColor(.white)

            if viewModel.isLoadingLyrics {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                Spacer()
            } else {
                LyricsView(
                    lyrics: viewModel.lyrics,
                    currentTime: viewModel.player.currentTime,
                    duration: viewModel.player.duration
                )
            }
        }
        .padding(SpaceTokens.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface.opacity(0.26))
        )
        .opacity(0.88)
        .mask(
            LinearGradient(
                colors: [Color.clear, Color.white, Color.white, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }

    private var albumArt: some View {
        Group {
            if let url = viewModel.albumArtUrl {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        albumArtPlaceholder
                    }
                }
            } else {
                albumArtPlaceholder
            }
        }
        .frame(width: 360, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.large))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    private var albumArtPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface)
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var trackInfo: some View {
        VStack(spacing: SpaceTokens.spaceXs) {
            Text(viewModel.trackTitle)
                .font(.title2xl)
                .foregroundColor(.white)
                .lineLimit(1)

            if !viewModel.artistName.isEmpty {
                Text(viewModel.artistName)
                    .font(.bodyLg)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            if !viewModel.albumName.isEmpty {
                Text(viewModel.albumName)
                    .font(.bodyMd)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressSection: some View {
        VStack(spacing: SpaceTokens.spaceXs) {
            PlayerSeekBar(
                progress: viewModel.displayedProgress,
                bufferProgress: viewModel.player.bufferProgress,
                isFocused: focusedTarget == .seekbar
            )
            .focusable()
            .focused($focusedTarget, equals: .seekbar)
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    if !viewModel.isScrubbing { viewModel.beginScrub() }
                    viewModel.updateScrub(by: -0.02)
                case .right:
                    if !viewModel.isScrubbing { viewModel.beginScrub() }
                    viewModel.updateScrub(by: 0.02)
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
            .frame(height: 12)

            HStack {
                Text(viewModel.positionText)
                    .font(.captionXs)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(viewModel.remainingText)
                    .font(.captionXs)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private var favoriteButton: some View {
        audioControlButton(
            icon: viewModel.isFavorite ? "heart.fill" : "heart",
            focus: .favorite,
            size: 22,
            defaultTint: .white,
            focusedBackground: .white
        ) {
            viewModel.toggleFavorite()
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 56) {
            audioControlButton(
                icon: "shuffle",
                focus: .shuffle,
                isAssetIcon: true,
                defaultTint: viewModel.audioManager.playbackOrder == .shuffle ? theme.accent : .white.opacity(0.7),
                focusedBackground: .white
            ) {
                viewModel.audioManager.toggleShuffle()
            }

            audioControlButton(
                icon: "backward.end.fill",
                focus: .previous,
                defaultTint: .white,
                focusedBackground: .white
            ) {
                Task { await viewModel.previous() }
            }

            audioControlButton(
                icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill",
                focus: .playPause,
                size: 40,
                defaultTint: .white,
                focusedBackground: theme.accent
            ) {
                viewModel.togglePlayPause()
            }

            audioControlButton(
                icon: "forward.end.fill",
                focus: .next,
                defaultTint: .white,
                focusedBackground: .white
            ) {
                Task { await viewModel.next() }
            }

            audioControlButton(
                icon: repeatIcon,
                focus: .`repeat`,
                defaultTint: viewModel.audioManager.repeatMode != .off ? theme.accent : .white.opacity(0.7),
                focusedBackground: .white
            ) {
                viewModel.audioManager.toggleRepeatMode()
            }
        }
        .padding(.top, 28)
    }

    private var repeatIcon: String {
        switch viewModel.audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func audioControlButton(
        icon: String,
        focus: FocusTarget,
        isAssetIcon: Bool = false,
        size: CGFloat = 28,
        defaultTint: Color = .white,
        focusedBackground: Color,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedTarget == focus

        return Button(action: action) {
            Group {
                if isAssetIcon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size))
                }
            }
            .foregroundColor(isFocused ? .black : defaultTint)
            .frame(width: 68, height: 68)
            .background(
                Circle()
                    .fill(isFocused ? focusedBackground : .clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($focusedTarget, equals: focus)
    }

    private func modeToggleButton(icon: String, focus: FocusTarget, isActive: Bool, action: @escaping () -> Void) -> some View {
        let isFocused = focusedTarget == focus

        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(isFocused ? .black : (isActive ? theme.accent : .white.opacity(0.85)))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(isFocused ? Color.white : (isActive ? Color.white.opacity(0.16) : Color.white.opacity(0.08)))
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($focusedTarget, equals: focus)
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack {
                Text("Queue")
                    .font(.titleXl)
                    .foregroundColor(.white)
                Spacer()
                Text("\(viewModel.audioManager.queue.count) tracks")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.5))
            }

            ScrollView {
                LazyVStack(spacing: SpaceTokens.space2xs) {
                    ForEach(Array(viewModel.audioManager.queue.enumerated()), id: \.element.id) { index, entry in
                        queueRow(entry: entry, index: index)
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .padding(.top, SpaceTokens.spaceMd)
        .padding(SpaceTokens.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface.opacity(0.22))
        )
        .opacity(0.86)
        .mask(
            LinearGradient(
                colors: [Color.clear, Color.white, Color.white, Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }

    private func queueRow(entry: QueueEntry, index: Int) -> some View {
        let isCurrent = index == viewModel.audioManager.currentIndex
        return Button {
            Task { await viewModel.playQueueItem(at: index) }
        } label: {
            QueueRowLabel(entry: entry, index: index, isCurrent: isCurrent, duration: formatDuration(entry.item.runTimeTicks ?? 0))
        }
        .buttonStyle(CleanButtonStyle())
    }

    private func formatDuration(_ ticks: Int64) -> String {
        let totalSeconds = Int(ticks / 10_000_000)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct QueueRowLabel: View {
    let entry: QueueEntry
    let index: Int
    let isCurrent: Bool
    let duration: String

    @EnvironmentObject private var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    private var primaryText: Color {
        if isFocused { return .black }
        return isCurrent ? theme.accent : .white
    }

    private var secondaryText: Color {
        isFocused ? .black.opacity(0.72) : .white.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.captionXs)
                    .foregroundColor(isFocused ? .black : theme.accent)
                    .frame(width: 20)
            } else {
                Text("\(index + 1)")
                    .font(.captionXs)
                    .foregroundColor(isFocused ? .black.opacity(0.7) : .white.opacity(0.4))
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name)
                    .font(.bodySm)
                    .foregroundColor(primaryText)
                    .lineLimit(1)

                if let artist = entry.item.artists?.first {
                    Text(artist)
                        .font(.captionXs)
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if entry.item.runTimeTicks != nil {
                Text(duration)
                    .font(.captionXs)
                    .foregroundColor(isFocused ? .black.opacity(0.7) : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, SpaceTokens.spaceSm)
        .padding(.vertical, SpaceTokens.spaceXs)
        .background {
            if isFocused {
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isCurrent ? Color.white.opacity(0.1) : .clear)
            }
        }
    }
}
