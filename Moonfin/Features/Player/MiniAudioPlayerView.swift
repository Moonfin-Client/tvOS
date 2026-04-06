import SwiftUI

struct MiniAudioPlayerView: View {
    @ObservedObject var audioManager: AudioManager
    @EnvironmentObject private var theme: MoonfinTheme
    @EnvironmentObject private var router: NavigationRouter

    private enum FocusTarget: Hashable {
        case trackInfo, previous, playPause, next
    }

    @FocusState private var focused: FocusTarget?

    private var player: MpvPlayerWrapper { audioManager.player }
    private var currentItem: ServerItem? { audioManager.currentItem }

    private var isPlaying: Bool {
        if case .buffering = player.state { return true }
        return player.state == .playing || player.state == .opening
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(player.currentTime / player.duration, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            content
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 48)
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 3)
    }

    private var content: some View {
        HStack(spacing: 0) {
            trackInfoButton
            Spacer(minLength: 0)
            transportControls
                .padding(.trailing, 20)
        }
        .frame(height: 80)
    }

    private var trackInfoButton: some View {
        Button {
            router.navigate(to: .nowPlaying)
        } label: {
            HStack(spacing: 16) {
                albumArt
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem?.name ?? "")
                        .font(.callout.weight(.semibold))
                        .foregroundColor(focused == .trackInfo ? .black : .white)
                        .lineLimit(1)

                    let artist = currentItem?.artists?.joined(separator: ", ")
                        ?? currentItem?.albumArtist
                        ?? ""
                    if !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(focused == .trackInfo ? .black.opacity(0.6) : .white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(focused == .trackInfo ? Color.white : .clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($focused, equals: .trackInfo)
    }

    private var albumArt: some View {
        Group {
            if let item = currentItem, let url = audioManager.albumArtUrl(for: item) {
                CachedImage(url: url)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.4))
                    )
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            miniButton(icon: "backward.fill", focus: .previous) {
                Task { await audioManager.previous() }
            }

            miniButton(icon: isPlaying ? "pause.fill" : "play.fill", focus: .playPause) {
                if isPlaying {
                    audioManager.playbackManager.pause()
                } else {
                    audioManager.playbackManager.resume()
                }
            }

            miniButton(icon: "forward.fill", focus: .next) {
                Task { await audioManager.next() }
            }
        }
    }

    private func miniButton(icon: String, focus: FocusTarget, action: @escaping () -> Void) -> some View {
        let isFocused = focused == focus
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isFocused ? .black : .white.opacity(0.85))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(isFocused ? Color.white : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($focused, equals: focus)
    }
}
