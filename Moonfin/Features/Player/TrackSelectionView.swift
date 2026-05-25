import SwiftUI

enum TrackSelectionTab: String {
    case audio = "Audio"
    case subtitles = "Subtitles"
    case speed = "Speed"
    case quality = "Quality"
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
                FocusableDialogButton(title: Strings.cancel, action: onDismiss)
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
        PlayerDialogShell(title: Strings.audioTrack, onDismiss: { viewModel.hideTrackSelection() }) {
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
        PlayerDialogShell(title: Strings.subtitleTrack, onDismiss: { viewModel.hideTrackSelection() }) {
            FocusableTrackSelectorRow(
                label: Strings.none,
                detail: nil,
                isSelected: viewModel.player.currentSubtitleTrackIndex == -1,
                action: { viewModel.playbackManager.disableSubtitles() }
            )

            if viewModel.usesServerSubtitleStreams {
                ForEach(viewModel.serverSubtitleStreams, id: \.index) { stream in
                    FocusableTrackSelectorRow(
                        label: viewModel.subtitleLabel(for: stream),
                        detail: viewModel.subtitleDetail(for: stream),
                        isSelected: stream.index == viewModel.activeServerSubtitleStreamIndex
                            && viewModel.player.currentSubtitleTrackIndex != -1,
                        action: { viewModel.selectSubtitle(serverStream: stream) }
                    )
                }
            } else {
                ForEach(viewModel.player.subtitleTracks) { track in
                    FocusableTrackSelectorRow(
                        label: track.name,
                        detail: nil,
                        isSelected: track.id == viewModel.player.currentSubtitleTrackIndex,
                        action: { viewModel.playbackManager.setSubtitleTrack(track.id) }
                    )
                }
            }

            Divider().background(Color.white.opacity(0.2))

            subtitleDelayControls

            if viewModel.canDownloadSubtitles {
                Divider().background(Color.white.opacity(0.2))

                FocusableTrackSelectorRow(
                    label: Strings.playerDownloadSubtitles,
                    detail: Strings.playerOpenSubtitlesSearch,
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
            Text(Strings.playerSubtitleDelay(subtitleDelayLabel))
                .font(.bodySm)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: SpaceTokens.spaceMd) {
                delayButton(Strings.playerSubtitleDelayDown) { viewModel.adjustSubtitleDelay(by: -0.25) }
                delayButton(Strings.playerSubtitleDelayReset) { viewModel.resetSubtitleDelay() }
                delayButton(Strings.playerSubtitleDelayUp) { viewModel.adjustSubtitleDelay(by: 0.25) }
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
        PlayerDialogShell(title: Strings.playbackSpeed, onDismiss: { viewModel.hideTrackSelection() }) {
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
        if speed == 1.0 { return Strings.playerSpeedNormal }
        if speed == floor(speed) { return "\(Int(speed))x" }
        return String(format: "%gx", speed)
    }
}

// MARK: - Quality Dialog

struct PlayerQualityDialog: View {
    @ObservedObject var viewModel: VideoPlayerViewModel

    var body: some View {
        PlayerDialogShell(title: Strings.maxBitrate, onDismiss: { viewModel.hideTrackSelection() }) {
            ForEach(viewModel.maxBitrateOptions, id: \.0) { value, label in
                FocusableTrackSelectorRow(
                    label: label,
                    detail: nil,
                    isSelected: viewModel.selectedMaxBitrate == value,
                    action: { viewModel.setMaxBitrate(value) }
                )
            }
        }
    }
}
