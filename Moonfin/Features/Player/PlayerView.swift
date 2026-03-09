import SwiftUI

struct VideoPlayerScreen: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @ObservedObject private var segmentHandler: MediaSegmentHandler
    @ObservedObject private var nextUpManager: NextUpManager
    @Environment(\.dismiss) private var dismiss

    init(playbackManager: PlaybackManager) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(playbackManager: playbackManager))
        _segmentHandler = ObservedObject(wrappedValue: playbackManager.segmentHandler)
        _nextUpManager = ObservedObject(wrappedValue: playbackManager.nextUpManager)
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

            if let action = segmentHandler.activeSkipPrompt {
                SkipSegmentOverlay(
                    action: action,
                    onSkip: { segmentHandler.confirmSkip() }
                )
            }

            switch nextUpManager.promptState {
            case .nextUp(let remaining):
                if let nextItem = viewModel.nextQueueItem {
                    NextUpOverlay(
                        nextItem: nextItem,
                        countdown: remaining,
                        imageUrl: viewModel.nextItemImageUrl,
                        onPlayNext: { nextUpManager.confirmPlayNext() },
                        onClose: { nextUpManager.dismiss() }
                    )
                }
            case .stillWatching:
                StillWatchingOverlay(
                    onContinue: {
                        nextUpManager.confirmStillWatching()
                        viewModel.playbackManager.resume()
                    },
                    onStop: {
                        nextUpManager.dismiss()
                        Task { await viewModel.playbackManager.stop() }
                        dismiss()
                    }
                )
            case .hidden:
                EmptyView()
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.trackSelectionVisible)
        .animation(.easeInOut(duration: 0.3), value: segmentHandler.activeSkipPrompt != nil)
        .animation(.easeInOut(duration: 0.3), value: nextUpManager.promptState)
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
