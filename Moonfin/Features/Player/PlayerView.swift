import SwiftUI

struct VideoPlayerScreen: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(playbackManager: PlaybackManager) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(playbackManager: playbackManager))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCPlayerView(player: viewModel.player)
                .ignoresSafeArea()

            gestureLayer

            if viewModel.overlayVisible {
                PlayerOverlayView(viewModel: viewModel)
            }

            if viewModel.trackSelectionVisible {
                trackSelectionOverlay
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.trackSelectionVisible)
        .onAppear {
            viewModel.showOverlay()
        }
        .onDisappear {
            Task { await viewModel.playbackManager.stop() }
        }
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .onPlayPauseCommand {
                viewModel.togglePlayPause()
                if !viewModel.overlayVisible { viewModel.showOverlay() }
            }
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    viewModel.seekBackward()
                case .right:
                    viewModel.seekForward()
                case .down:
                    viewModel.showTrackSelection()
                case .up:
                    if !viewModel.overlayVisible {
                        viewModel.showOverlay()
                    }
                @unknown default:
                    break
                }
            }
            .onExitCommand {
                if viewModel.trackSelectionVisible {
                    viewModel.hideTrackSelection()
                } else if viewModel.overlayVisible {
                    viewModel.hideOverlay()
                } else {
                    dismiss()
                }
            }
    }

    private var trackSelectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            TrackSelectionView(viewModel: viewModel)
        }
        .transition(.opacity)
    }
}
