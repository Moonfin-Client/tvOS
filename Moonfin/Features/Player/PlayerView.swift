import SwiftUI

struct VideoPlayerScreen: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @ObservedObject private var segmentHandler: MediaSegmentHandler
    @ObservedObject private var nextUpManager: NextUpManager
    @EnvironmentObject var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @FocusState private var gestureLayerFocused: Bool

    init(playbackManager: PlaybackManager) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(playbackManager: playbackManager))
        _segmentHandler = ObservedObject(wrappedValue: playbackManager.segmentHandler)
        _nextUpManager = ObservedObject(wrappedValue: playbackManager.nextUpManager)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCPlayerView(player: viewModel.player)
                .equatable()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            gestureLayer

            if viewModel.overlayVisible {
                PlayerOverlayView(viewModel: viewModel)
                    .focusSection()
            }

            if viewModel.audioSelectionVisible {
                trackDialogOverlay {
                    PlayerAudioTrackDialog(viewModel: viewModel)
                }
            }

            if viewModel.subtitleSelectionVisible {
                trackDialogOverlay {
                    PlayerSubtitleTrackDialog(viewModel: viewModel)
                }
            }

            if viewModel.speedSelectionVisible {
                trackDialogOverlay {
                    PlayerSpeedDialog(viewModel: viewModel)
                }
            }

            if viewModel.chapterSelectionVisible {
                chapterSelectionOverlay
                    .focusSection()
            }

            if viewModel.castListVisible {
                castListOverlay
                    .focusSection()
            }

            if viewModel.playbackInfoVisible {
                trackDialogOverlay {
                    PlaybackInfoDialog(viewModel: viewModel)
                }
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.audioSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.subtitleSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.speedSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.chapterSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.castListVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.playbackInfoVisible)
        .animation(.easeInOut(duration: 0.3), value: segmentHandler.activeSkipPrompt != nil)
        .animation(.easeInOut(duration: 0.3), value: nextUpManager.promptState)
        .onAppear {
            viewModel.showOverlay()
        }
        .onChange(of: viewModel.overlayVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.audioSelectionVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.subtitleSelectionVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.speedSelectionVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.chapterSelectionVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.castListVisible) { _ in restoreFocusIfNeeded() }
        .onChange(of: viewModel.playbackInfoVisible) { _ in restoreFocusIfNeeded() }
    }

    private func restoreFocusIfNeeded() {
        let anyVisible = viewModel.overlayVisible || viewModel.trackSelectionVisible
            || viewModel.chapterSelectionVisible || viewModel.castListVisible
            || viewModel.playbackInfoVisible
        if !anyVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                gestureLayerFocused = true
            }
        }
    }

    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable()
            .focused($gestureLayerFocused)
            .disabled(viewModel.overlayVisible || viewModel.trackSelectionVisible || viewModel.chapterSelectionVisible || viewModel.castListVisible || viewModel.playbackInfoVisible)
            .onPlayPauseCommand {
                viewModel.togglePlayPause()
                if !viewModel.overlayVisible { viewModel.showOverlay() }
            }
            .onMoveCommand { _ in
                if !viewModel.overlayVisible {
                    viewModel.showOverlay()
                }
            }
            .onExitCommand {
                if viewModel.chapterSelectionVisible {
                    viewModel.hideChapterSelection()
                } else if viewModel.castListVisible {
                    viewModel.hideCastList()
                } else if viewModel.playbackInfoVisible {
                    viewModel.hidePlaybackInfo()
                } else if viewModel.trackSelectionVisible {
                    viewModel.hideTrackSelection()
                } else if viewModel.overlayVisible {
                    viewModel.hideOverlay()
                } else {
                    dismiss()
                }
            }
    }

    private func trackDialogOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            content()
        }
        .transition(.opacity)
        .focusSection()
    }

    private var chapterSelectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            ChapterSelectionView(viewModel: viewModel)
        }
        .transition(.opacity)
    }

    private var castListOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            CastListView(viewModel: viewModel) { person in
                viewModel.hideCastList()
                guard let personId = person.id else { return }
                let serverId = viewModel.playbackManager.currentEntry?.item.serverId
                dismiss()
                router.navigate(to: .itemDetails(itemId: personId, serverId: serverId))
            }
        }
        .transition(.opacity)
    }
}
