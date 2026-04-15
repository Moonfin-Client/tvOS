import SwiftUI

struct VideoPlayerScreen: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @ObservedObject private var segmentHandler: MediaSegmentHandler
    @ObservedObject private var nextUpManager: NextUpManager
    @EnvironmentObject var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @State private var remoteInputFocusToken = UUID()
    @FocusState private var jumpToLiveFocused: Bool
    @State private var awaitingFirstFrame = true

    init(
        playbackManager: PlaybackManager,
        isLiveTV: Bool = false,
        syncPlayManager: SyncPlayManager? = nil
    ) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(
            playbackManager: playbackManager,
            isLiveTV: isLiveTV,
            syncPlayManager: syncPlayManager
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

            if isBuffering {
                bufferingOverlay
            }

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

            if viewModel.channelListVisible {
                liveTvChannelListOverlay
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

            if viewModel.isLiveTV, viewModel.canJumpToLive {
                jumpToLiveOverlay
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.channelListVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.playbackInfoVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.subtitleDownloadVisible)
        .animation(.easeInOut(duration: 0.3), value: segmentHandler.activeSkipPrompt != nil)
        .animation(.easeInOut(duration: 0.3), value: viewModel.canJumpToLive)
        .animation(.easeInOut(duration: 0.3), value: nextUpManager.promptState)
        .onAppear {
            viewModel.showOverlay()
            awaitingFirstFrame = true
        }
        .onChange(of: viewModel.player.currentTime) { currentTime in
            if currentTime > 0.1 {
                awaitingFirstFrame = false
            }
        }
        .onChange(of: viewModel.player.state) { state in
            switch state {
            case .idle, .opening, .buffering:
                awaitingFirstFrame = true
            case .playing:
                break
            case .paused:
                if viewModel.player.currentTime > 0.1 {
                    awaitingFirstFrame = false
                }
            case .stopped, .ended, .error:
                awaitingFirstFrame = false
            }
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
        .onChange(of: viewModel.channelListVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.playbackInfoVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.subtitleDownloadVisible) { visible in
            if !visible { remoteInputFocusToken = UUID() }
        }
        .onChange(of: viewModel.canJumpToLive) { canShow in
            jumpToLiveFocused = canShow
        }
    }

    private var isNextUpOrStillWatchingVisible: Bool {
        nextUpManager.promptState != .hidden
    }

    private var isBuffering: Bool {
        if awaitingFirstFrame {
            return true
        }
        if case .buffering = viewModel.player.state {
            return true
        }
        if case .opening = viewModel.player.state {
            return true
        }
        if case .idle = viewModel.player.state {
            return true
        }
        return false
    }

    private var bufferingOverlay: some View {
        ProgressView()
            .tint(.blue)
            .scaleEffect(1.2)
            .padding(18)
            .background(.black.opacity(0.35), in: Circle())
            .allowsHitTesting(false)
    }

    private var jumpToLiveOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Task { await viewModel.jumpToLive() }
                } label: {
                    HStack(spacing: SpaceTokens.spaceSm) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.bodyLg)
                        Text("Jump to Live TV")
                            .font(.bodyLg)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, SpaceTokens.spaceLg)
                    .padding(.vertical, SpaceTokens.spaceMd)
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.medium)
                            .fill(jumpToLiveFocused ? Color.red.opacity(1.0) : Color.red.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.medium)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                    )
                    .foregroundColor(.white)
                    .scaleEffect(jumpToLiveFocused ? 1.04 : 1.0)
                }
                .buttonStyle(.plain)
                .focusable(true)
                .focused($jumpToLiveFocused)
                .padding(.trailing, SpaceTokens.space3xl)
                .padding(.bottom, 260)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var gestureLayer: some View {
        RemoteInputView(
            onSelect: {
                if segmentHandler.activeSkipPrompt != nil {
                    segmentHandler.confirmSkip()
                    return
                }
                if viewModel.canJumpToLive {
                    Task { await viewModel.jumpToLive() }
                    return
                }
                if !viewModel.overlayVisible {
                    viewModel.togglePlayPause()
                    viewModel.showOverlay()
                }
            },
            onDirection: { _ in
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
                if viewModel.canJumpToLive {
                    viewModel.dismissJumpToLivePrompt()
                    return
                }
                if viewModel.overlayVisible || viewModel.trackSelectionVisible
                    || viewModel.chapterSelectionVisible || viewModel.castListVisible
                    || viewModel.channelListVisible
                    || viewModel.playbackInfoVisible || viewModel.subtitleDownloadVisible {
                    return
                }
                dismiss()
            },
            focusToken: remoteInputFocusToken
        )
        .allowsHitTesting(!viewModel.overlayVisible && !viewModel.trackSelectionVisible
            && !viewModel.chapterSelectionVisible && !viewModel.castListVisible
            && !viewModel.channelListVisible
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

    private var liveTvChannelListOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            PlayerLiveTvChannelListOverlayView(viewModel: viewModel)
        }
        .transition(.opacity)
    }
}

private struct PlayerLiveTvChannelListOverlayView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var focusedChannelId: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                Text(Strings.playerChannels)
                    .font(.title2xl)
                    .foregroundColor(.white)
                    .padding(.horizontal, 80)

                if viewModel.isLoadingLiveTvChannels && viewModel.liveTvChannels.isEmpty {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text(Strings.liveTvLoadingGuideData)
                            .font(.bodySm)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, SpaceTokens.spaceMd)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: SpaceTokens.spaceXs) {
                            ForEach(viewModel.liveTvChannels, id: \.id) { channel in
                                channelRow(channel)
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.vertical, SpaceTokens.spaceSm)
                    }
                    .frame(maxHeight: 480)
                    .onAppear {
                        focusedChannelId = viewModel.currentLiveTvChannelId ?? viewModel.liveTvChannels.first?.id
                    }
                }
            }
            .padding(.vertical, 40)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.bottom, -60)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onExitCommand {
            viewModel.hideChannelList()
        }
    }

    private func channelRow(_ channel: ServerItem) -> some View {
        let isFocused = focusedChannelId == channel.id
        let isCurrent = viewModel.currentLiveTvChannelId == channel.id

        return Button {
            Task { @MainActor in
                await viewModel.selectLiveTvChannel(channel)
            }
        } label: {
            HStack(spacing: SpaceTokens.spaceSm) {
                Text(channel.channelNumber ?? "-")
                    .font(.captionXs)
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 44, alignment: .leading)

                Group {
                    if let urlString = viewModel.channelLogoUrl(for: channel),
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Color.clear
                            }
                        }
                    } else {
                        Image(systemName: "tv")
                            .font(.captionXs)
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.bodySm)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(viewModel.currentProgramName(for: channel))
                        .font(.caption2xs)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.captionXs)
                        .foregroundColor(theme.accent)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceSm)
            .padding(.vertical, SpaceTokens.spaceXs)
            .background(theme.colorScheme.surface.opacity(isFocused ? 0.35 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 2.5 : 0)
            )
        }
        .buttonStyle(PopupCardButtonStyle())
        .focused($focusedChannelId, equals: channel.id)
    }
}
