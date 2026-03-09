import SwiftUI
import NukeUI

struct AudioNowPlayingView: View {
    @ObservedObject var viewModel: AudioNowPlayingViewModel
    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .ignoresSafeArea()
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
        HStack(spacing: SpaceTokens.space3xl) {
            VStack(spacing: SpaceTokens.spaceLg) {
                albumArt
                trackInfo
                progressSection
                controlButtons
            }
            .frame(width: 500)

            if viewModel.showQueue {
                queueList
                    .frame(width: 400)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if viewModel.hasLyrics {
                LyricsView(
                    lyrics: viewModel.lyrics,
                    currentTime: viewModel.player.currentTime,
                    duration: viewModel.player.duration
                )
                .frame(width: 400)
                .transition(.opacity)
            }
        }
        .padding(SpaceTokens.space3xl)
        .animation(.easeInOut(duration: 0.3), value: viewModel.showQueue)
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
                progress: viewModel.player.position,
                bufferProgress: 0,
                isFocused: false
            )
            .frame(height: 6)

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

    private var controlButtons: some View {
        HStack(spacing: SpaceTokens.spaceXl) {
            audioControlButton(
                icon: "shuffle",
                tint: viewModel.audioManager.playbackOrder == .shuffle ? theme.accent : .white.opacity(0.7)
            ) {
                viewModel.audioManager.toggleShuffle()
            }

            audioControlButton(icon: "backward.fill") {
                Task { await viewModel.previous() }
            }

            audioControlButton(
                icon: viewModel.player.isPlaying ? "pause.fill" : "play.fill",
                size: 40
            ) {
                viewModel.togglePlayPause()
            }

            audioControlButton(icon: "forward.fill") {
                Task { await viewModel.next() }
            }

            audioControlButton(
                icon: repeatIcon,
                tint: viewModel.audioManager.repeatMode != .off ? theme.accent : .white.opacity(0.7)
            ) {
                viewModel.audioManager.toggleRepeatMode()
            }
        }
    }

    private var repeatIcon: String {
        switch viewModel.audioManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func audioControlButton(
        icon: String,
        size: CGFloat = 28,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
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
        }
        .padding(SpaceTokens.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface.opacity(0.6))
        )
    }

    private func queueRow(entry: QueueEntry, index: Int) -> some View {
        let isCurrent = index == viewModel.audioManager.currentIndex
        return Button {
            Task { await viewModel.playQueueItem(at: index) }
        } label: {
            HStack(spacing: SpaceTokens.spaceSm) {
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.captionXs)
                        .foregroundColor(theme.accent)
                        .frame(width: 20)
                } else {
                    Text("\(index + 1)")
                        .font(.captionXs)
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item.name)
                        .font(.bodySm)
                        .foregroundColor(isCurrent ? theme.accent : .white)
                        .lineLimit(1)

                    if let artist = entry.item.artists?.first {
                        Text(artist)
                            .font(.captionXs)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let ticks = entry.item.runTimeTicks {
                    Text(formatDuration(ticks))
                        .font(.captionXs)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceXs)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isCurrent ? Color.white.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ ticks: Int64) -> String {
        let totalSeconds = Int(ticks / 10_000_000)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
