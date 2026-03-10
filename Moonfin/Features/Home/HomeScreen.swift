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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if isMediaBarMode && viewModel.mediaBarViewModel.isEnabled && (viewModel.isMediaBarActive || viewModel.isMediaBarLoading) {
                    MediaBarView(
                        viewModel: viewModel.mediaBarViewModel,
                        ratingsViewModel: viewModel.mediaBarRatingsViewModel,
                        userPreferences: container.userPreferences,
                        screenHeight: geo.size.height,
                        focusNamespace: mainNamespace,
                        onItemSelected: { item in
                            navigatedFromMediaBar = true
                            router.navigate(to: .itemDetails(itemId: item.id))
                        },
                        onNavigateDown: {
                            sentinelEnabled = false
                            isMediaBarMode = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                sentinelEnabled = true
                            }
                        }
                    )
                } else if !viewModel.isInitialLoad {
                    backdropLayer
                    gradientOverlay
                    infoArea
                        .allowsHitTesting(false)
                        .zIndex(1)
                    rowsContent(screenHeight: geo.size.height)
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
            } else if lastFocusedRowId != nil {
                isMediaBarMode = false
                isRestoringPosition = true
                sentinelEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard isRestoringPosition else { return }
                    isRestoringPosition = false
                    lastFocusedRowId = nil
                    lastFocusedItemId = nil
                    sentinelEnabled = viewModel.isMediaBarActive
                    resetFocus(in: mainNamespace)
                }
            }
        }
        .onDisappear { viewModel.mediaBarViewModel.cleanup() }
        .onChange(of: viewModel.isMediaBarActive) { active in
            if active && lastFocusedRowId == nil { isMediaBarMode = true }
        }
        .onChange(of: viewModel.hasFocusableContent) { ready in
            if ready && !isRestoringPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    resetFocus(in: mainNamespace)
                }
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
                            MediaBarReturnSentinel {
                                isMediaBarMode = true
                            }
                            .frame(height: 1)
                        }

                        LazyVStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
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
                                        if row.rowType == .libraryTiles {
                                            navigateToLibrary(item)
                                        } else if row.rowType == .liveTvButtons {
                                            navigateToLiveTvAction(item)
                                        } else if row.rowType == .liveTvOnNow || row.rowType == .liveTvComingUp {
                                            if let channelId = item.channelId {
                                                router.navigate(to: .liveTvPlayer(channelId: channelId))
                                            }
                                        } else {
                                            router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId))
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
    let onReturn: () -> Void

    func makeUIView(context: Context) -> SentinelFocusView {
        let view = SentinelFocusView()
        view.onReturnToMediaBar = onReturn
        return view
    }

    func updateUIView(_ uiView: SentinelFocusView, context: Context) {
        uiView.onReturnToMediaBar = onReturn
    }
}

private class SentinelFocusView: UIView {
    var onReturnToMediaBar: (() -> Void)?
    private var isFocusEnabled = true

    override var canBecomeFocused: Bool { isFocusEnabled }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isFocused else { return }

        if context.focusHeading.contains(.up) {
            DispatchQueue.main.async { [weak self] in
                self?.onReturnToMediaBar?()
            }
        } else {
            isFocusEnabled = false
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isFocusEnabled = true
            }
        }
    }
}
