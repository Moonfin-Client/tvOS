import SwiftUI

struct VideoPlayerScreen: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @ObservedObject private var segmentHandler: MediaSegmentHandler
    @ObservedObject private var nextUpManager: NextUpManager
    @EnvironmentObject var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @State private var remoteInputFocusToken = UUID()

    init(
        playbackManager: PlaybackManager,
        isLiveTV: Bool = false,
        onLiveTvChannelUp: (() async -> Void)? = nil,
        onLiveTvChannelDown: (() async -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(
            playbackManager: playbackManager,
            isLiveTV: isLiveTV,
            onLiveTvChannelUp: onLiveTvChannelUp,
            onLiveTvChannelDown: onLiveTvChannelDown
        ))
        _segmentHandler = ObservedObject(wrappedValue: playbackManager.segmentHandler)
        _nextUpManager = ObservedObject(wrappedValue: playbackManager.nextUpManager)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlaybackSurfaceView(player: viewModel.player)
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

            if viewModel.subtitleDownloadVisible {
                trackDialogOverlay {
                    SubtitleDownloadDialog(
                        defaultLanguage: viewModel.playbackManager.currentEntry.flatMap { entry in
                            let streams = entry.item.mediaSources?.first?.mediaStreams ?? []
                            return streams.first(where: { $0.type == .subtitle })?.language
                                ?? streams.first(where: { $0.type == .audio })?.language
                        } ?? "eng",
                        onSearch: { lang in try await viewModel.playbackManager.searchRemoteSubtitles(language: lang) },
                        onDownload: { id in try await viewModel.playbackManager.downloadRemoteSubtitle(subtitleId: id) },
                        onDismiss: { viewModel.hideSubtitleDownload() },
                        onDownloaded: { viewModel.hideSubtitleDownload() }
                    )
                }
            }

            if !viewModel.isLiveTV, let action = segmentHandler.activeSkipPrompt {
                SkipSegmentOverlay(action: action)
            }

            if !viewModel.isLiveTV {
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
                        .focusSection()
                        .onExitCommand { nextUpManager.dismiss() }
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
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.audioSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.subtitleSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.speedSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.chapterSelectionVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.castListVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.playbackInfoVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.subtitleDownloadVisible)
        .animation(.easeInOut(duration: 0.3), value: segmentHandler.activeSkipPrompt != nil)
        .animation(.easeInOut(duration: 0.3), value: nextUpManager.promptState)
        .onAppear {
            viewModel.showOverlay()
        }
        .onChange(of: viewModel.overlayVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.trackSelectionVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.chapterSelectionVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.castListVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.playbackInfoVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.subtitleDownloadVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
    }

    private var isNextUpOrStillWatchingVisible: Bool {
        nextUpManager.promptState != .hidden
    }

    private var gestureLayer: some View {
        RemoteInputView(
            onSelect: {
                if segmentHandler.activeSkipPrompt != nil {
                    segmentHandler.confirmSkip()
                    return
                }
                if !viewModel.overlayVisible {
                    viewModel.togglePlayPause()
                    viewModel.showOverlay()
                }
            },
            onDirection: { direction in
                if viewModel.isLiveTV && !viewModel.overlayVisible {
                    switch direction {
                    case .upArrow:
                        viewModel.channelUp()
                        viewModel.showOverlay()
                        return
                    case .downArrow:
                        viewModel.channelDown()
                        viewModel.showOverlay()
                        return
                    default:
                        break
                    }
                }
                if !viewModel.overlayVisible {
                    viewModel.showOverlay()
                }
            },
            onPlayPause: {
                viewModel.togglePlayPause()
                if !viewModel.overlayVisible { viewModel.showOverlay() }
            },
            onMenu: {
                if segmentHandler.activeSkipPrompt != nil {
                    segmentHandler.dismissPrompt()
                    return
                }
                if viewModel.overlayVisible || viewModel.trackSelectionVisible
                    || viewModel.chapterSelectionVisible || viewModel.castListVisible
                    || viewModel.playbackInfoVisible || viewModel.subtitleDownloadVisible {
                    return
                }
                dismiss()
            },
            focusToken: remoteInputFocusToken
        )
        .allowsHitTesting(!viewModel.overlayVisible && !viewModel.trackSelectionVisible
            && !viewModel.chapterSelectionVisible && !viewModel.castListVisible
            && !viewModel.playbackInfoVisible && !viewModel.subtitleDownloadVisible
            && !isNextUpOrStillWatchingVisible)
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
                guard let personId = person.id else { return }
                let serverId = viewModel.playbackManager.currentEntry?.item.serverId
                viewModel.hideCastList()
                dismiss()
                DispatchQueue.main.async {
                    router.navigate(to: .itemDetails(itemId: personId, serverId: serverId))
                }
            }
        }
        .transition(.opacity)
        .onExitCommand {
            viewModel.hideCastList()
        }
    }
}
