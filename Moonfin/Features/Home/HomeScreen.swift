import SwiftUI
import Nuke

struct HomeScreen: View {
    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    let mainNamespace: Namespace.ID
    @State private var isMediaBarMode = true
    @State private var sentinelEnabled = false
    @State private var focusedRowId: String?
    @State private var scrollTrigger: Int = 0
    @State private var lastFocusedRowId: String?
    @State private var lastFocusedItemId: String?
    @State private var navigatedFromMediaBar = false
    @State private var isRestoringPosition = false
    @State private var mediaBarRequestFocus = false
    @State private var focusTask: Task<Void, Never>?
    @State private var sentinelTask: Task<Void, Never>?
    @Environment(\.resetFocus) private var resetFocus

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    init(container: AppContainer, mainNamespace: Namespace.ID) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(container: container))
        self.mainNamespace = mainNamespace
    }

    private func resolveFocus(delay: UInt64 = 50_000_000) {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if isRestoringPosition {
                isRestoringPosition = false
                lastFocusedRowId = nil
                lastFocusedItemId = nil
                sentinelEnabled = viewModel.isMediaBarActive
            }
            if isMediaBarMode && viewModel.isMediaBarActive {
                mediaBarRequestFocus = true
            } else {
                resetFocus(in: mainNamespace)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let showMediaBar = viewModel.mediaBarViewModel.isEnabled && (viewModel.isMediaBarActive || viewModel.isMediaBarLoading)
            let mediaBarPresented = isMediaBarMode && showMediaBar

            ZStack(alignment: .topLeading) {
                if mediaBarPresented {
                    MediaBarView(
                        viewModel: viewModel.mediaBarViewModel,
                        ratingsViewModel: viewModel.mediaBarRatingsViewModel,
                        userPreferences: container.userPreferences,
                        screenHeight: geo.size.height,
                        onItemSelected: { item in
                            navigatedFromMediaBar = true
                            router.navigate(to: .itemDetails(itemId: item.id))
                        },
                        onNavigateDown: {
                            sentinelEnabled = false
                            isMediaBarMode = false
                            sentinelTask?.cancel()
                            sentinelTask = Task {
                                try? await Task.sleep(nanoseconds: 600_000_000)
                                guard !Task.isCancelled else { return }
                                sentinelEnabled = true
                            }
                            resolveFocus(delay: 150_000_000)
                        },
                        requestFocus: $mediaBarRequestFocus
                    )
                    .zIndex(1)
                }

                if !viewModel.isInitialLoad {
                    if !mediaBarPresented {
                        backdropLayer
                        gradientOverlay
                        infoArea
                            .allowsHitTesting(false)
                            .zIndex(1)
                    }
                    rowsContent(screenHeight: geo.size.height)
                        .disabled(mediaBarPresented)
                        .opacity(mediaBarPresented ? 0 : 1)
                        .prefersDefaultFocus(in: mainNamespace)
                        .zIndex(0)
                }
            }
        }
        .ignoresSafeArea()
        .environmentObject(viewModel.backgroundService)
        .onAppear {
            viewModel.loadContent()
            router.hideNavbar = false
            if navigatedFromMediaBar {
                isMediaBarMode = true
                navigatedFromMediaBar = false
                viewModel.mediaBarViewModel.resume()
            } else if lastFocusedRowId != nil {
                isMediaBarMode = false
                isRestoringPosition = true
                sentinelEnabled = false
                resolveFocus(delay: 500_000_000)
            }
        }
        .onDisappear {
            focusTask?.cancel()
            sentinelTask?.cancel()
            viewModel.mediaBarViewModel.cleanup()
        }
        .onReceive(container.pluginSyncService.$syncCompletedCount) { count in
            guard count > 0 else { return }
            viewModel.loadContent(forceReload: true)
        }
        .onChange(of: viewModel.isMediaBarActive) { active in
            if active && lastFocusedRowId == nil { isMediaBarMode = true }
        }
        .onChange(of: viewModel.hasFocusableContent) { ready in
            if ready && !isRestoringPosition {
                resolveFocus()
            }
        }
    }

    private var backdropLayer: some View {
        GeometryReader { geo in
            if viewModel.backgroundService.enabled,
               let urlString = viewModel.backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: CGSize(width: geo.size.width, height: geo.size.height), contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: Int(viewModel.backgroundService.blurAmount))
                    ]
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: BackgroundService.transitionDuration), value: viewModel.backgroundService.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }

    private var gradientOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.colorScheme.background.opacity(0.85), location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.4), location: 0.4),
                    .init(color: theme.colorScheme.background.opacity(0.3), location: 0.6),
                    .init(color: theme.colorScheme.background.opacity(0.7), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: theme.colorScheme.background.opacity(0.6), location: 0.7),
                    .init(color: theme.colorScheme.background.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            if let logoUrl = viewModel.selectedItemState.logoUrl,
               let url = URL(string: logoUrl) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                    }
                }
            } else if !viewModel.selectedItemState.title.isEmpty {
                Text(viewModel.selectedItemState.title)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
            }

            SimpleInfoRow(item: viewModel.selectedItemState.item)

            if !viewModel.mediaBarRatingsViewModel.ratings.isEmpty {
                MediaBarRatingsRow(
                    ratings: viewModel.mediaBarRatingsViewModel.ratings,
                    enableAdditionalRatings: viewModel.mediaBarRatingsViewModel.enableAdditionalRatings
                )
            }

            if !viewModel.selectedItemState.summary.isEmpty {
                Text(viewModel.selectedItemState.summary)
                    .font(.titleXl)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(4)
            }
        }
        .padding(.leading, contentLeading)
        .padding(.trailing, 50)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedItemState.title)
    }

    private func rowsContent(screenHeight: CGFloat) -> some View {
        let rowsTop = screenHeight * 0.38

        return VStack(spacing: 0) {
            Spacer()
                .frame(height: rowsTop)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.isMediaBarActive && sentinelEnabled {
                            MediaBarReturnSentinel(
                                hasContent: viewModel.rows.contains(where: { !$0.isEmpty }),
                                onReturn: {
                                    isMediaBarMode = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        mediaBarRequestFocus = true
                                    }
                                }
                            )
                            .frame(height: 1)
                        }

                        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                            let visibleRows = viewModel.rows.filter { !$0.isEmpty }
                            ForEach(visibleRows) { row in
                                ContentRow(
                                    row: row,
                                    viewModel: viewModel,
                                    watchedIndicator: viewModel.watchedIndicator,
                                    onRowFocused: {
                                        focusedRowId = row.id
                                        if isRestoringPosition {
                                            isRestoringPosition = false
                                            lastFocusedRowId = nil
                                            lastFocusedItemId = nil
                                            sentinelEnabled = true
                                        } else {
                                            scrollTrigger += 1
                                        }
                                    },
                                    onItemSelected: { item in
                                        navigatedFromMediaBar = false
                                        lastFocusedRowId = row.id
                                        lastFocusedItemId = item.id
                                        if row.rowType == .myMedia || row.rowType == .myMediaSmall {
                                            navigateToLibrary(item)
                                        } else if row.rowType == .liveTvButtons {
                                            navigateToLiveTvAction(item)
                                        } else if row.rowType == .liveTvOnNow || row.rowType == .liveTvComingUp {
                                            if let channelId = item.channelId {
                                                router.navigate(to: .liveTvPlayer(channelId: channelId))
                                            }
                                        } else {
                                            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.effectiveServerId))
                                        }
                                    },
                                    restoredItemId: lastFocusedRowId == row.id ? lastFocusedItemId : nil
                                )
                                .id(row.id)
                            }
                        }
                    }
                    .padding(.leading, contentLeading)
                    .padding(.trailing, 50)
                }
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 30)

                        Color.black
                    }
                )
                .onChange(of: scrollTrigger) { _ in
                    guard let id = focusedRowId else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: 0.05))
                    }
                }
                .onAppear {
                    if let rowId = lastFocusedRowId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(rowId, anchor: UnitPoint(x: 0, y: 0.05))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigateToLibrary(_ item: ServerItem) {
        router.navigateToLibrary(item)
    }

    private func navigateToLiveTvAction(_ item: ServerItem) {
        switch item.id {
        case "ltv_guide":
            router.navigate(to: .liveTvGuide)
        case "ltv_recordings":
            router.navigate(to: .liveTvRecordings)
        case "ltv_schedule":
            router.navigate(to: .liveTvSchedule)
        case "ltv_series":
            router.navigate(to: .liveTvSeriesRecordings)
        default:
            break
        }
    }
}

// MARK: - Media Bar Return Sentinel

private struct MediaBarReturnSentinel: UIViewRepresentable {
    let hasContent: Bool
    let onReturn: () -> Void

    func makeUIView(context: Context) -> SentinelFocusView {
        let view = SentinelFocusView()
        view.hasContent = hasContent
        view.onReturnToMediaBar = onReturn
        return view
    }

    func updateUIView(_ uiView: SentinelFocusView, context: Context) {
        uiView.hasContent = hasContent
        uiView.onReturnToMediaBar = onReturn
    }
}

private class SentinelFocusView: UIView {
    var onReturnToMediaBar: (() -> Void)?
    var hasContent = false
    private var passingThrough = false

    override var canBecomeFocused: Bool { hasContent && !passingThrough }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isFocused else { return }

        if context.focusHeading.contains(.up) {
            DispatchQueue.main.async { [weak self] in
                self?.onReturnToMediaBar?()
            }
        } else {
            passingThrough = true
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.passingThrough = false
            }
        }
    }
}
