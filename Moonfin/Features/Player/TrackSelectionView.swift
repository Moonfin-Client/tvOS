import SwiftUI

enum TrackSelectionTab: String {
    case audio = "Audio"
    case subtitles = "Subtitles"
    case speed = "Speed"
}

// MARK: - Dialog Shell

struct PlayerDialogShell<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    @EnvironmentObject private var theme: MoonfinTheme

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
                    content
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }
            .frame(maxHeight: 500)

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
        .onExitCommand(perform: onDismiss)
    }
}

// MARK: - Audio Track Dialog

struct PlayerAudioTrackDialog: View {
    @ObservedObject var viewModel: VideoPlayerViewModel

    var body: some View {
        PlayerDialogShell(title: "Audio", onDismiss: { viewModel.hideTrackSelection() }) {
            ForEach(viewModel.player.audioTracks) { track in
                FocusableTrackSelectorRow(
                    label: track.name,
                    detail: nil,
                    isSelected: track.id == viewModel.player.currentAudioTrackIndex,
                    action: { viewModel.playbackManager.setAudioTrack(track.id) }
                )
            }
        }
    }
}

// MARK: - Subtitle Track Dialog

struct PlayerSubtitleTrackDialog: View {
    @ObservedObject var viewModel: VideoPlayerViewModel

    var body: some View {
        PlayerDialogShell(title: "Subtitles", onDismiss: { viewModel.hideTrackSelection() }) {
            FocusableTrackSelectorRow(
                label: "None",
                detail: nil,
                isSelected: viewModel.player.currentSubtitleTrackIndex == -1,
                action: { viewModel.player.disableSubtitles() }
            )

            ForEach(viewModel.player.subtitleTracks) { track in
                FocusableTrackSelectorRow(
                    label: track.name,
                    detail: nil,
                    isSelected: track.id == viewModel.player.currentSubtitleTrackIndex,
                    action: { viewModel.playbackManager.setSubtitleTrack(track.id) }
                )
            }

            Divider().background(Color.white.opacity(0.2))

            subtitleDelayControls

            if viewModel.canDownloadSubtitles {
                Divider().background(Color.white.opacity(0.2))

                FocusableTrackSelectorRow(
                    label: "Download subtitles...",
                    detail: "Search using OpenSubtitles",
                    isSelected: false,
                    action: {
                        viewModel.hideTrackSelection()
                        viewModel.showSubtitleDownload()
                    }
                )
            }
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
        .buttonStyle(CleanButtonStyle())
    }

    private var subtitleDelayLabel: String {
        let delay = viewModel.subtitleDelay
        if abs(delay) < 0.001 { return "0s" }
        return String(format: "%+gs", delay)
    }
}

// MARK: - Speed Dialog

struct PlayerSpeedDialog: View {
    @ObservedObject var viewModel: VideoPlayerViewModel

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        PlayerDialogShell(title: "Speed", onDismiss: { viewModel.hideTrackSelection() }) {
            ForEach(speedOptions, id: \.self) { speed in
                FocusableTrackSelectorRow(
                    label: speedLabel(speed),
                    detail: nil,
                    isSelected: abs(viewModel.player.rate - speed) < 0.01,
                    action: { viewModel.setPlaybackSpeed(speed) }
                )
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "Normal" }
        if speed == floor(speed) { return "\(Int(speed))x" }
        return String(format: "%gx", speed)
    }
}
