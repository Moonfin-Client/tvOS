import SwiftUI
import Nuke

struct HomeScreen: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var previewManager: PreviewPlayerManager
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter
    let mainNamespace: Namespace.ID
    @Binding var contentReady: Bool
    @Binding var suppressTopNavbarInRows: Bool
    let sidebarEntryToken: Int
    let sidebarHandoffToken: Int
    let onRequestTopNavbarHomeFocus: (() -> Void)?
    @State private var isMediaBarMode = true
    @State private var focusedRowId: String?
    @State private var scrollTrigger: Int = 0
    @State private var lastFocusedRowId: String?
    @State private var lastFocusedItemId: String?
    @State private var navigatedFromMediaBar = false
    @State private var isRestoringPosition = false
    @State private var mediaBarRequestFocus = false
    @State private var focusTask: Task<Void, Never>?
    @State private var restoreTask: Task<Void, Never>?
    @State private var mediaBarTrailerPreviewTask: Task<Void, Never>?
    @State private var lastPreviewedMediaBarItemId: String?
    @StateObject private var inlineTrailerPlayer = InlineTrailerPlayerManager()
    @Environment(\.resetFocus) private var resetFocus
    @State private var focusFirstRowTrigger: Int = 0
    @State private var restoreRowFocusTrigger: Int = 0
    @State private var restoreScrollTrigger: Int = 0
    @Namespace private var rowsNamespace
    @State private var suppressTopNavbarUntilMediaBarFocus = false
    @State private var lastContentAreaWasMediaBar = false
    @State private var sidebarEntryRowId: String?
    @State private var sidebarEntryItemId: String?
    @State private var sidebarEntryWasMediaBar = false
    @State private var hasInitiallyFocusedFirstRow = false
    @State private var appWasBackgrounded = false
    @State private var lastMoveCommandDirection = "none"
    @State private var lastMoveCommandAt: TimeInterval = 0
    @State private var lastFocusEventAt: TimeInterval = 0
    @State private var mediaBarDownHandoffInProgress = false
    @State private var mediaBarDownHandoffStartedAt: TimeInterval = 0
    @State private var mediaBarDownHandoffTargetRowId: String?
    @State private var mediaBarDownHandoffTargetItemId: String?
    @State private var mediaBarDownHandoffTargetReason: String = "none"
    @State private var mediaBarDownHandoffToken: Int = 0
    @State private var verticalTransitionToken: Int = 0
    @State private var lastFocusedItemIndexByRowId: [String: Int] = [:]
    @State private var lastSyncedMakdBackdropUrl: String?

    private var navbarIsLeft: Bool {
        container.userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var contentLeading: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 50
    }

    private var isHomeRowsV2Mode: Bool {
        container.userPreferences[UserPreferences.homeRowsStyle] == .v2
    }

    private var posterSizePreference: PosterSize {
        container.userPreferences[UserPreferences.homePosterSize]
    }

    private var shouldShowMediaBarReturnSentinel: Bool {
        guard viewModel.mediaBarViewModel.isEnabled,
              viewModel.isMediaBarActive,
              !isMediaBarMode,
              !mediaBarDownHandoffInProgress,
              let firstRowId = viewModel.visibleRows.first?.id
        else { return false }

        let currentRowId = focusedRowId ?? lastFocusedRowId
        return currentRowId == firstRowId
    }

    private var seasonalSurprise: SeasonalSurprise {
        container.userPreferences[UserPreferences.seasonalSurprise]
    }

    init(
        container: AppContainer,
        mainNamespace: Namespace.ID,
        contentReady: Binding<Bool> = .constant(true),
        sidebarEntryToken: Int = 0,
        sidebarHandoffToken: Int = 0,
        suppressTopNavbarInRows: Binding<Bool> = .constant(false),
        onRequestTopNavbarHomeFocus: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(container: container))
        self.mainNamespace = mainNamespace
        self._contentReady = contentReady
        self.sidebarEntryToken = sidebarEntryToken
        self.sidebarHandoffToken = sidebarHandoffToken
        self._suppressTopNavbarInRows = suppressTopNavbarInRows
        self.onRequestTopNavbarHomeFocus = onRequestTopNavbarHomeFocus
    }

    private func debugLog(_ event: String, details: String = "") {
#if DEBUG
        guard ProcessInfo.processInfo.environment["MOONFIN_HOME_FOCUS_DEBUG"] == "1" else {
            return
        }
        let timestamp = Date().timeIntervalSinceReferenceDate
        if details.isEmpty {
            print("[HomeNav] [\(timestamp)] \(event)")
        } else {
            print("[HomeNav] [\(timestamp)] \(event) | \(details)")
        }
#endif
    }

    private func directionLabel(_ direction: MoveCommandDirection) -> String {
        switch direction {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        default: return "unknown"
        }
    }

    private func recordMoveCommand(_ direction: MoveCommandDirection, source: String) {
        let now = Date().timeIntervalSinceReferenceDate
        let repeatDeltaMs = lastMoveCommandAt > 0 ? Int((now - lastMoveCommandAt) * 1000) : -1
        lastMoveCommandDirection = directionLabel(direction)
        lastMoveCommandAt = now
        debugLog(
            "move_command",
            details: "source=\(source) direction=\(lastMoveCommandDirection) repeat_delta_ms=\(repeatDeltaMs) is_media_bar_mode=\(isMediaBarMode) focused_row=\(focusedRowId ?? "nil")"
        )
    }

    private func rowTypeLabel(_ rowType: HomeRowType) -> String {
        switch rowType {
        case .continueWatching: return "continueWatching"
        case .nextUp: return "nextUp"
        case .latestMedia(let libraryId): return "latestMedia(\(libraryId))"
        case .myMedia: return "myMedia"
        case .myMediaSmall: return "myMediaSmall"
        case .resumeAudio: return "resumeAudio"
        case .playlists: return "playlists"
        case .liveTvButtons: return "liveTvButtons"
        case .liveTvOnNow: return "liveTvOnNow"
        case .liveTvComingUp: return "liveTvComingUp"
        }
    }

    private func isMusicItem(_ item: ServerItem) -> Bool {
        switch item.type {
        case .audio, .musicAlbum, .musicArtist, .musicVideo, .musicGenre:
            return true
        default:
            return false
        }
    }

    private func isMusicRow(_ row: HomeRow) -> Bool {
        switch row.rowType {
        case .resumeAudio, .playlists:
            return true
        case .latestMedia:
            if row.isMusicLibraryRow { return true }
            guard let first = row.items.first else { return false }
            return isMusicItem(first)
        default:
            return false
        }
    }

    private func posterTypeLabel(for row: HomeRow) -> String {
        if isMusicRow(row) {
            return "poster(music_forced)"
        }

        switch row.rowType {
        case .continueWatching:
            return container.userPreferences[UserPreferences.homeImageTypeContinueWatching].rawValue
        case .nextUp:
            return container.userPreferences[UserPreferences.homeImageTypeNextUp].rawValue
        case .myMedia:
            return container.userPreferences[UserPreferences.homeImageTypeMyMedia].rawValue
        case .liveTvOnNow, .liveTvComingUp:
            return container.userPreferences[UserPreferences.homeImageTypeLiveTv].rawValue
        case .myMediaSmall:
            return "fixed_library_action"
        case .liveTvButtons:
            return "fixed_livetv_button"
        default:
            return container.userPreferences[UserPreferences.homeImageTypeLibraries].rawValue
        }
    }

    private func safeDimension(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
        if value.isFinite, value >= 0 {
            return value
        }
        debugLog("invalid_dimension_sanitized", details: "value=\(value) fallback=\(fallback)")
        return fallback
    }

    private func resolveFocus(delay: UInt64 = 50_000_000) {
        focusTask?.cancel()
        focusTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if mediaBarDownHandoffInProgress {
                debugLog("resolve_focus_skipped", details: "reason=media_bar_down_handoff")
                return
            }
            if isRestoringPosition, lastFocusedRowId != nil {
                restoreScrollTrigger += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                resetFocus(in: rowsNamespace)
                return
            }
            if isRestoringPosition {
                isRestoringPosition = false
            }
            if isMediaBarMode && viewModel.isMediaBarActive {
                mediaBarRequestFocus = true
            } else if navbarIsLeft {
                DispatchQueue.main.async {
                    focusFirstRowTrigger += 1
                }
            } else {
                resetFocus(in: mainNamespace)
            }
        }
    }

    private func handleAppDidBecomeActive() {
        focusTask?.cancel()
        restoreTask?.cancel()
        mediaBarRequestFocus = false

        if let restoreRowId = lastFocusedRowId {
            isMediaBarMode = false
            focusedRowId = restoreRowId
            isRestoringPosition = true
            hasInitiallyFocusedFirstRow = true
            resolveFocus(delay: 100_000_000)
            scheduleSidebarRowRestore(delay: 150_000_000)
            return
        }

        isRestoringPosition = false

        if viewModel.isMediaBarActive {
            isMediaBarMode = true
            viewModel.mediaBarViewModel.resume()
            requestMediaBarFocus(after: 0)
            return
        }

        if viewModel.hasFocusableContent {
            isMediaBarMode = false
            focusFirstRowTrigger += 1
            scheduleSidebarRowRestore(delay: 100_000_000)
        }
    }

    private func scheduleSidebarRowRestore(delay: UInt64 = 100_000_000) {
        restoreTask?.cancel()
        restoreTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard !mediaBarDownHandoffInProgress else {
                debugLog("restore_row_focus_skipped", details: "reason=media_bar_down_handoff")
                return
            }
            restoreRowFocusTrigger += 1
        }
    }

    private func requestMediaBarFocus(after delay: Double = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            mediaBarRequestFocus = true
            if suppressTopNavbarUntilMediaBarFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressTopNavbarUntilMediaBarFocus = false
                    syncTopNavbarSuppression()
                }
            }
        }
    }

    private func syncTopNavbarSuppression() {
        let mediaBarEnabled = viewModel.mediaBarViewModel.isEnabled
        suppressTopNavbarInRows = mediaBarEnabled && (!isMediaBarMode || suppressTopNavbarUntilMediaBarFocus)
    }

    private func shouldApplyRestorationDefaultFocus(for rowId: String) -> Bool {
        isRestoringPosition
            && !mediaBarDownHandoffInProgress
            && lastFocusedRowId == rowId
    }

    private func resolveMediaBarDownTarget(for row: HomeRow) -> (itemId: String?, itemIndex: Int?, reason: String) {
        guard !row.items.isEmpty else { return (nil, nil, "empty_row") }

        if let rememberedIndex = lastFocusedItemIndexByRowId[row.id] {
            let clampedIndex = max(0, min(rememberedIndex, row.items.count - 1))
            let reason = clampedIndex == rememberedIndex ? "same_column" : "nearest_valid"
            return (row.items[clampedIndex].id, clampedIndex, reason)
        }

        if let lastFocusedRowId,
           lastFocusedRowId == row.id,
           let lastFocusedItemId,
           let resolvedIndex = row.items.firstIndex(where: { $0.id == lastFocusedItemId }) {
            return (row.items[resolvedIndex].id, resolvedIndex, "restored_item")
        }

        return (row.items.first?.id, row.items.isEmpty ? nil : 0, "first_item")
    }

    private func retargetMediaBarDownHandoff(rowId: String, itemId: String?, reason: String) {
        mediaBarDownHandoffTargetRowId = rowId
        mediaBarDownHandoffTargetItemId = itemId
        mediaBarDownHandoffTargetReason = reason
        mediaBarDownHandoffToken += 1
        debugLog(
            "media_bar_down_handoff_retarget",
            details: "token=\(mediaBarDownHandoffToken) reason=\(reason) target_row=\(rowId) target_item=\(itemId ?? "nil")"
        )
    }

    private func moveFocusToFirstRowFromMediaBar() {
        guard let firstVisibleRow = viewModel.visibleRows.first else {
            debugLog("media_bar_down_handoff_aborted", details: "reason=no_visible_rows")
            return
        }

        let firstVisibleRowId = firstVisibleRow.id
        let resolvedTarget = resolveMediaBarDownTarget(for: firstVisibleRow)
        let firstVisibleItemId = resolvedTarget.itemId
        mediaBarDownHandoffToken += 1
        let handoffToken = mediaBarDownHandoffToken
        mediaBarDownHandoffInProgress = true
        mediaBarDownHandoffStartedAt = Date().timeIntervalSinceReferenceDate
        mediaBarDownHandoffTargetRowId = firstVisibleRowId
        mediaBarDownHandoffTargetItemId = firstVisibleItemId
        mediaBarDownHandoffTargetReason = resolvedTarget.reason

        isMediaBarMode = false
        isRestoringPosition = false
        focusedRowId = firstVisibleRowId

        // Force a deterministic handoff target to avoid media-bar down skipping to the next row.
        lastFocusedRowId = firstVisibleRowId
        lastFocusedItemId = firstVisibleItemId
        if let resolvedIndex = resolvedTarget.itemIndex {
            lastFocusedItemIndexByRowId[firstVisibleRowId] = resolvedIndex
        }
        scrollTrigger += 1

        debugLog(
            "media_bar_down_handoff_start",
            details: "token=\(handoffToken) target_row=\(firstVisibleRowId) target_item=\(firstVisibleItemId ?? "nil") target_index=\(resolvedTarget.itemIndex.map(String.init) ?? "nil") target_reason=\(resolvedTarget.reason) visible_rows=\(viewModel.visibleRows.count)"
        )

        DispatchQueue.main.async {
            guard handoffToken == mediaBarDownHandoffToken else { return }
            resetFocus(in: rowsNamespace)
            debugLog("media_bar_down_handoff_reset_focus", details: "namespace=rows attempt=0")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            if handoffToken == mediaBarDownHandoffToken, mediaBarDownHandoffInProgress {
                resetFocus(in: rowsNamespace)
                debugLog("media_bar_down_handoff_retry", details: "attempt=1 token=\(handoffToken)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            if handoffToken == mediaBarDownHandoffToken, mediaBarDownHandoffInProgress {
                mediaBarDownHandoffInProgress = false
                mediaBarDownHandoffTargetRowId = nil
                mediaBarDownHandoffTargetItemId = nil
                mediaBarDownHandoffTargetReason = "timeout"
                debugLog("media_bar_down_handoff_timeout_clear", details: "duration_ms=12000")
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
                        inlineTrailerPlayer: inlineTrailerPlayer,
                        onItemSelected: { item in
                            cancelMediaBarTrailerPreview()
                            navigatedFromMediaBar = true
                            router.navigateToItem(item)
                        },
                        onPlayTrailer: { item in
                            cancelMediaBarTrailerPreview()
                            Task { await playTrailerFromMediaBar(item) }
                        },
                        onFocusedItemChanged: { item in
                            lastContentAreaWasMediaBar = item != nil
                            syncMakdBackdrop(for: item)
                            scheduleMediaBarTrailerPreview(for: item)
                        },
                        onNavigateDown: {
                            recordMoveCommand(.down, source: "media_bar")
                            cancelMediaBarTrailerPreview()
                            moveFocusToFirstRowFromMediaBar()
                        },
                        onNavigateUp: {
                            recordMoveCommand(.up, source: "media_bar")
                            onRequestTopNavbarHomeFocus?()
                        },
                        requestFocus: $mediaBarRequestFocus
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                    .zIndex(1)
                }

                if !viewModel.isInitialLoad {
                    if !mediaBarPresented {
                        HomeBackdropView(backgroundService: viewModel.backgroundService)
                        gradientOverlay
                        if !isHomeRowsV2Mode {
                            HomeInfoAreaView(
                                infoState: viewModel.infoState,
                                ratingsViewModel: viewModel.mediaBarRatingsViewModel,
                                contentLeading: contentLeading
                            )
                            .allowsHitTesting(false)
                            .zIndex(1)
                        }
                    }
                    rowsContent(screenHeight: geo.size.height)
                        .disabled(mediaBarPresented)
                        .opacity(mediaBarPresented ? 0 : 1)
                        .offset(y: mediaBarPresented ? 28 : 0)
                        .zIndex(0)

                }
            }
            .animation(.interactiveSpring(response: 0.55, dampingFraction: 0.9, blendDuration: 0.3), value: mediaBarPresented)
        }
        .ignoresSafeArea()
        .environmentObject(viewModel.backgroundService)
        .onAppear {
            viewModel.loadContent()
            suppressTopNavbarUntilMediaBarFocus = viewModel.mediaBarViewModel.isEnabled && lastFocusedRowId == nil
            syncTopNavbarSuppression()
            hasInitiallyFocusedFirstRow = false
            if navigatedFromMediaBar {
                isMediaBarMode = true
                navigatedFromMediaBar = false
                viewModel.mediaBarViewModel.resume()
            } else if lastFocusedRowId != nil {
                isMediaBarMode = false
                isRestoringPosition = true
                hasInitiallyFocusedFirstRow = true
                resolveFocus(delay: 100_000_000)
            } else if viewModel.isMediaBarActive {
                isMediaBarMode = true
                requestMediaBarFocus(after: 0)
            }
        }
        .onDisappear {
            focusTask?.cancel()
            cancelMediaBarTrailerPreview()
            viewModel.mediaBarViewModel.cleanup()
            suppressTopNavbarUntilMediaBarFocus = false
            suppressTopNavbarInRows = false
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appWasBackgrounded = true
                focusTask?.cancel()
                restoreTask?.cancel()
                cancelMediaBarTrailerPreview()
            case .active:
                guard appWasBackgrounded else { return }
                appWasBackgrounded = false
                handleAppDidBecomeActive()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.isMediaBarActive) { active in
            if active && lastFocusedRowId == nil {
                isMediaBarMode = true
                requestMediaBarFocus()
            }
        }
        .onChange(of: viewModel.isInitialLoad) { loading in
            guard !loading else { return }
            if !contentReady && !viewModel.hasFocusableContent {
                contentReady = true
            }
        }
        .onChange(of: isMediaBarMode) { mode in
            syncTopNavbarSuppression()
            if mode { previewManager.stop() }
            if !mode { clearMakdBackdropSync() }
        }
        .onChange(of: viewModel.mediaBarViewModel.currentItemBackdropUrl) { _ in
            syncMakdBackdrop(for: viewModel.mediaBarViewModel.currentItem)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if container.userPreferences[UserPreferences.mediaBarMode] == .makd {
                syncMakdBackdrop(for: viewModel.mediaBarViewModel.currentItem)
            } else {
                clearMakdBackdropSync()
            }
        }
        .onChange(of: container.inactivityTracker.isScreensaverVisible) { visible in
            if visible { previewManager.stop() }
        }
        .onChange(of: viewModel.hasFocusableContent) { ready in
            if ready {
                if !contentReady { contentReady = true }
                guard !mediaBarDownHandoffInProgress else { return }
                if !isRestoringPosition && !hasInitiallyFocusedFirstRow {
                    hasInitiallyFocusedFirstRow = true
                    if isMediaBarMode && viewModel.isMediaBarActive {
                        mediaBarRequestFocus = true
                    } else {
                        focusFirstRowTrigger += 1
                        scheduleSidebarRowRestore(delay: 100_000_000)
                    }
                }
            } else if !viewModel.isInitialLoad {
                if !contentReady { contentReady = true }
            }
        }
        .onChange(of: sidebarHandoffToken) { _ in
            guard viewModel.hasFocusableContent else { return }
            guard !mediaBarDownHandoffInProgress else {
                debugLog("sidebar_handoff_skipped", details: "reason=media_bar_down_handoff")
                return
            }
            let restoreMediaBar = sidebarEntryWasMediaBar || (viewModel.isMediaBarActive && lastContentAreaWasMediaBar)
            let restoreRowId = sidebarEntryRowId ?? lastFocusedRowId
            let restoreItemId = sidebarEntryItemId ?? lastFocusedItemId

            if viewModel.isMediaBarActive && restoreMediaBar {
                isMediaBarMode = true
                requestMediaBarFocus(after: 0)
                sidebarEntryWasMediaBar = false
                sidebarEntryRowId = nil
                sidebarEntryItemId = nil
                return
            }

            isMediaBarMode = false
            if !navbarIsLeft {
                focusFirstRowTrigger += 1
            } else {
                if let restoreRowId {
                    focusedRowId = restoreRowId
                    lastFocusedRowId = restoreRowId
                    lastFocusedItemId = restoreItemId
                    isRestoringPosition = true
                    hasInitiallyFocusedFirstRow = true
                    scrollTrigger += 1
                    scheduleSidebarRowRestore()
                } else {
                    resolveFocus(delay: 0)
                }
            }

            sidebarEntryWasMediaBar = false
            sidebarEntryRowId = nil
            sidebarEntryItemId = nil
        }
        .onChange(of: sidebarEntryToken) { _ in
            guard navbarIsLeft else { return }
            if isMediaBarMode && viewModel.isMediaBarActive {
                sidebarEntryWasMediaBar = true
                sidebarEntryRowId = nil
                sidebarEntryItemId = nil
                return
            }

            sidebarEntryWasMediaBar = false
            sidebarEntryRowId = focusedRowId ?? lastFocusedRowId
            if let rowId = sidebarEntryRowId, rowId == lastFocusedRowId {
                sidebarEntryItemId = lastFocusedItemId
            } else {
                sidebarEntryItemId = nil
            }
        }
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

            if seasonalSurprise != .none {
                seasonalTintOverlay
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var seasonalTintOverlay: some View {
        let tint: Color = {
            switch seasonalSurprise {
            case .none: return .clear
            case .winter: return Color.blue.opacity(0.12)
            case .spring: return Color.green.opacity(0.10)
            case .summer: return Color.orange.opacity(0.12)
            case .halloween: return Color.orange.opacity(0.18)
            case .fall: return Color(red: 0.64, green: 0.30, blue: 0.10).opacity(0.16)
            }
        }()

        LinearGradient(
            stops: [
                .init(color: tint, location: 0),
                .init(color: .clear, location: 0.55),
                .init(color: tint.opacity(0.7), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func rowsContent(screenHeight: CGFloat) -> some View {
        let rowsTop = safeDimension(screenHeight * (isHomeRowsV2Mode ? 0.14 : 0.50))
        let rowsBottomPadding = safeDimension(screenHeight * (isHomeRowsV2Mode ? 0.70 : 0.48))

        return VStack(spacing: 0) {
            Spacer()
                .frame(height: rowsTop)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if shouldShowMediaBarReturnSentinel {
                            MediaBarReturnSentinel(
                                hasContent: !viewModel.visibleRows.isEmpty,
                                onReturn: {
                                    recordMoveCommand(.up, source: "media_bar_return_sentinel")
                                    isMediaBarMode = true
                                    requestMediaBarFocus(after: 0)
                                    debugLog("row_vertical_move_to_media_bar", details: "source=media_bar_return_sentinel")
                                }
                            )
                            .frame(height: 1)
                        }

                        VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                            ForEach(viewModel.visibleRows) { row in
                                ContentRow(
                                    row: row,
                                    viewModel: viewModel,
                                    watchedIndicator: viewModel.watchedIndicator,
                                    titleTopPadding: viewModel.visibleRows.first?.id == row.id ? 4 : 0,
                                    onRowFocused: {
                                        let rowIndex = viewModel.visibleRows.firstIndex(where: { $0.id == row.id }) ?? -1
                                        focusedRowId = row.id

                                        let now = Date().timeIntervalSinceReferenceDate
                                        let focusDeltaMs = lastFocusEventAt > 0 ? Int((now - lastFocusEventAt) * 1000) : -1
                                        lastFocusEventAt = now

                                        debugLog(
                                            "row_focused",
                                            details: "row_id=\(row.id) row_index=\(rowIndex) row_type=\(rowTypeLabel(row.rowType)) focus_delta_ms=\(focusDeltaMs) move_direction=\(lastMoveCommandDirection)"
                                        )

                                        if isRestoringPosition {
                                            if row.id == lastFocusedRowId {
                                                isRestoringPosition = false
                                                debugLog("restore_position_complete", details: "row_id=\(row.id) row_index=\(rowIndex)")
                                            }
                                        }
                                    },
                                    onItemFocused: { item in
                                        lastContentAreaWasMediaBar = false

                                        let rowIndex = viewModel.visibleRows.firstIndex(where: { $0.id == row.id }) ?? -1
                                        let itemIndex = row.items.firstIndex(where: { $0.id == item.id }) ?? -1
                                        let now = Date().timeIntervalSinceReferenceDate
                                        let focusLatencyMs = lastMoveCommandAt > 0 ? Int((now - lastMoveCommandAt) * 1000) : -1
                                        let focusDeltaMs = lastFocusEventAt > 0 ? Int((now - lastFocusEventAt) * 1000) : -1
                                        lastFocusEventAt = now
                                        let previousFocusedRowId = focusedRowId
                                        if itemIndex >= 0 {
                                            lastFocusedItemIndexByRowId[row.id] = itemIndex
                                        }
                                        let activeHandoffToken = mediaBarDownHandoffToken

                                        if mediaBarDownHandoffInProgress {
                                            let targetRowId = mediaBarDownHandoffTargetRowId
                                                ?? viewModel.visibleRows.first?.id
                                            let targetItemId = mediaBarDownHandoffTargetItemId
                                                ?? viewModel.visibleRows.first?.items.first?.id

                                            if let targetRowId, row.id != targetRowId {
                                                focusedRowId = targetRowId
                                                lastFocusedRowId = targetRowId
                                                lastFocusedItemId = targetItemId
                                                scrollTrigger += 1
                                                retargetMediaBarDownHandoff(rowId: targetRowId, itemId: targetItemId, reason: "corrective_refocus")
                                                resetFocus(in: rowsNamespace)
                                                debugLog(
                                                    "media_bar_down_handoff_corrective_refocus",
                                                    details: "token=\(activeHandoffToken) focused_row=\(row.id) focused_row_index=\(rowIndex) corrective_target_row=\(targetRowId) corrective_target_item=\(targetItemId ?? "nil") move_direction=\(lastMoveCommandDirection) focus_latency_ms=\(focusLatencyMs)"
                                                )
                                                return
                                            }

                                            if let targetItemId, item.id != targetItemId {
                                                if mediaBarDownHandoffTargetReason == "first_item" {
                                                    mediaBarDownHandoffTargetItemId = item.id
                                                    mediaBarDownHandoffTargetReason = "native_landing_adopted"
                                                    lastFocusedItemId = item.id
                                                    debugLog(
                                                        "media_bar_down_handoff_adopt_native_item",
                                                        details: "token=\(activeHandoffToken) row_id=\(row.id) row_index=\(rowIndex) item_id=\(item.id) item_index=\(itemIndex)"
                                                    )
                                                } else {
                                                    focusedRowId = targetRowId
                                                    lastFocusedRowId = targetRowId
                                                    lastFocusedItemId = targetItemId
                                                    if let targetRowId,
                                                       let targetRow = viewModel.visibleRows.first(where: { $0.id == targetRowId }),
                                                       let targetIndex = targetRow.items.firstIndex(where: { $0.id == targetItemId }) {
                                                        lastFocusedItemIndexByRowId[targetRowId] = targetIndex
                                                    }
                                                    if let targetRowId {
                                                        retargetMediaBarDownHandoff(rowId: targetRowId, itemId: targetItemId, reason: "corrective_item")
                                                    }
                                                    debugLog(
                                                        "media_bar_down_handoff_corrective_item",
                                                        details: "token=\(activeHandoffToken) row_id=\(row.id) row_index=\(rowIndex) current_item=\(item.id) corrective_item=\(targetItemId)"
                                                    )
                                                    return
                                                }
                                            }

                                            mediaBarDownHandoffInProgress = false
                                            mediaBarDownHandoffTargetRowId = nil
                                            mediaBarDownHandoffTargetItemId = nil
                                            mediaBarDownHandoffTargetReason = "complete"
                                            let handoffDurationMs = mediaBarDownHandoffStartedAt > 0 ? Int((now - mediaBarDownHandoffStartedAt) * 1000) : -1
                                            debugLog(
                                                "media_bar_down_handoff_complete",
                                                details: "token=\(activeHandoffToken) row_id=\(row.id) row_index=\(rowIndex) item_id=\(item.id) item_index=\(itemIndex) handoff_duration_ms=\(handoffDurationMs)"
                                            )
                                        }

                                        let didEnterDifferentRow = previousFocusedRowId != row.id

                                        focusedRowId = row.id

                                        debugLog(
                                            "item_focused",
                                            details: "row_id=\(row.id) row_index=\(rowIndex) item_id=\(item.id) item_index=\(itemIndex) row_type=\(rowTypeLabel(row.rowType)) poster_type=\(posterTypeLabel(for: row)) poster_size=\(posterSizePreference.rawValue) poster_scale=\(posterSizePreference.scaleFactor) is_v2_mode=\(isHomeRowsV2Mode) move_direction=\(lastMoveCommandDirection) focus_latency_ms=\(focusLatencyMs) focus_delta_ms=\(focusDeltaMs)"
                                        )

                                        if !isRestoringPosition {
                                            lastFocusedRowId = row.id

                                            if didEnterDifferentRow {
                                                let previousRowIndex = previousFocusedRowId.flatMap { previousRowId in
                                                    viewModel.visibleRows.firstIndex(where: { $0.id == previousRowId })
                                                } ?? -1
                                                let sourceItemId = previousFocusedRowId != nil ? lastFocusedItemId : nil
                                                let sourceItemIndex = previousFocusedRowId.flatMap { previousRowId in
                                                    lastFocusedItemIndexByRowId[previousRowId]
                                                }
                                                let direction: String = {
                                                    guard previousRowIndex >= 0, rowIndex >= 0 else { return "unknown" }
                                                    if rowIndex > previousRowIndex { return "down" }
                                                    if rowIndex < previousRowIndex { return "up" }
                                                    return "unknown"
                                                }()
                                                verticalTransitionToken += 1
                                                scrollTrigger += 1
                                                debugLog(
                                                    "vertical_transition_land",
                                                    details: "token=\(verticalTransitionToken) source_row=\(previousFocusedRowId ?? "nil") source_row_index=\(previousRowIndex) source_item=\(sourceItemId ?? "nil") source_item_index=\(sourceItemIndex.map(String.init) ?? "nil") direction=\(direction) target_row=\(row.id) target_row_index=\(rowIndex) target_item=\(item.id) target_item_index=\(itemIndex) scroll_trigger=\(scrollTrigger)"
                                                )
                                            }

                                            lastFocusedItemId = item.id
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
                                            router.navigateToItem(item, serverId: item.effectiveServerId)
                                        }
                                    },
                                    onToggleWatched: viewModel.toggleWatched,
                                    onToggleFavorite: viewModel.toggleFavorite,
                                    restoredItemId: lastFocusedRowId == row.id ? lastFocusedItemId : nil,
                                    preferredItemId: mediaBarDownHandoffTargetRowId == row.id ? mediaBarDownHandoffTargetItemId : nil,
                                    focusTrigger: {
                                        if lastFocusedRowId == row.id {
                                            return restoreRowFocusTrigger
                                        }
                                        if viewModel.visibleRows.first?.id == row.id {
                                            return focusFirstRowTrigger
                                        }
                                        return 0
                                    }(),
                                    transitionToken: mediaBarDownHandoffTargetRowId == row.id ? mediaBarDownHandoffToken : 0,
                                    isRowFocused: focusedRowId == row.id
                                )
                                .id(row.id)
                                .prefersDefaultFocus(shouldApplyRestorationDefaultFocus(for: row.id), in: rowsNamespace)
                            }
                        }
                        .focusScope(rowsNamespace)
                        .padding(.bottom, rowsBottomPadding)
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
                        .frame(height: 80)

                        Color.black
                    }
                )
                .onChange(of: scrollTrigger) { _ in
                    guard let id = focusedRowId else { return }
                    debugLog("scroll_to_focused_row", details: "row_id=\(id) trigger=\(scrollTrigger)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
                .onChange(of: restoreScrollTrigger) { _ in
                    guard let rowId = lastFocusedRowId else { return }
                    debugLog("scroll_restore_row", details: "row_id=\(rowId) trigger=\(restoreScrollTrigger)")
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(rowId, anchor: .top)
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

    private func scheduleMediaBarTrailerPreview(for item: MediaBarSlideItem?) {
        cancelMediaBarTrailerPreview()
        guard container.userPreferences[UserPreferences.mediaBarTrailerPreview] else { return }
        guard isMediaBarMode, let item else { return }
        guard lastPreviewedMediaBarItemId != item.id else { return }

        mediaBarTrailerPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            guard isMediaBarMode else { return }
            guard container.userPreferences[UserPreferences.mediaBarTrailerPreview] else { return }
            await playTrailerFromMediaBar(item)
        }
    }

    private func cancelMediaBarTrailerPreview() {
        mediaBarTrailerPreviewTask?.cancel()
        mediaBarTrailerPreviewTask = nil
        inlineTrailerPlayer.stop()
    }

    private func resolvePreviewStreamWithTimeout(
        videoId: String,
        timeoutSeconds: Double = 8
    ) async -> YouTubeStreamResolver.ResolveResult? {
        await withTaskGroup(of: YouTubeStreamResolver.ResolveResult?.self) { group in
            group.addTask {
                await YouTubeStreamResolver.resolveStream(videoId: videoId, mode: .full)
            }
            group.addTask {
                let nanos = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func configureMediaBarPreview(isYouTube: Bool) {
        let muted = !container.userPreferences[UserPreferences.mediaBarTrailerAudio]
        inlineTrailerPlayer.setMuted(muted)

        if isYouTube {
            inlineTrailerPlayer.setProperty(
                "user-agent",
                value: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
            )
            inlineTrailerPlayer.setProperty(
                "referrer",
                value: "https://www.youtube.com/"
            )
        }
    }

    private func playTrailerFromMediaBar(_ slideItem: MediaBarSlideItem) async {
        guard let server = container.serverRepository.currentServer.value else { return }
        let client = container.serverClientFactory.client(for: server)
        guard let item = try? await client.userLibraryApi.getItem(itemId: slideItem.id) else { return }

        if let localTrailers = try? await client.userLibraryApi.getLocalTrailers(itemId: item.id),
           let localTrailer = localTrailers.first {
            let resolver = ServerStreamResolver(client: client, requestedBackend: .mpv)
            let mediaSourceId = localTrailer.mediaSources?.first?.id
            if let stream = try? await resolver.resolve(
                item: localTrailer,
                mediaSourceId: mediaSourceId,
                maxBitrate: nil,
                maxAudioChannels: nil,
                atmosPassthroughEnabled: false,
                audioStreamIndex: nil,
                subtitleStreamIndex: nil,
                startTimeTicks: nil
            ) {
                guard !Task.isCancelled, isMediaBarMode else { return }
                configureMediaBarPreview(isYouTube: false)
                await inlineTrailerPlayer.play(streamUrl: stream.url)
                lastPreviewedMediaBarItemId = slideItem.id
                return
            }
        }

        guard let videoId = TrailerPlaybackHelper.firstYouTubeVideoId(from: item.remoteTrailers) else { return }
        guard let result = await resolvePreviewStreamWithTimeout(videoId: videoId) else { return }
        guard let streamInfo = result.stream else { return }
        guard !Task.isCancelled, isMediaBarMode else { return }

        configureMediaBarPreview(isYouTube: true)
        await inlineTrailerPlayer.play(url: streamInfo.url)
        lastPreviewedMediaBarItemId = slideItem.id
    }

    private func syncMakdBackdrop(for item: MediaBarSlideItem?) {
        guard isMediaBarMode else { return }
        guard container.userPreferences[UserPreferences.mediaBarMode] == .makd else {
            clearMakdBackdropSync()
            return
        }
        guard let backdropUrl = item?.backdropUrl, !backdropUrl.isEmpty else { return }
        guard backdropUrl != lastSyncedMakdBackdropUrl else { return }

        viewModel.backgroundService.setBackground(url: backdropUrl, context: .browsing)
        lastSyncedMakdBackdropUrl = backdropUrl
    }

    private func clearMakdBackdropSync() {
        lastSyncedMakdBackdropUrl = nil
    }
}

// MARK: - Home Backdrop View

private struct HomeBackdropView: View {
    @ObservedObject var backgroundService: BackgroundService
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        GeometryReader { geo in
            if backgroundService.enabled,
               let urlString = backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                CachedImage(
                    url: url,
                    processors: [
                        ImageProcessors.Resize(size: CGSize(width: geo.size.width, height: geo.size.height), contentMode: .aspectFill),
                        ImageProcessors.GaussianBlur(radius: Int(backgroundService.blurAmount))
                    ]
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup()
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: BackgroundService.transitionDuration), value: backgroundService.currentBackdropUrl)
        .background(theme.colorScheme.background)
    }
}

// MARK: - Home Info Area View

private struct HomeInfoAreaView: View {
    private static let logoReservedHeight: CGFloat = 128
    private static let logoMaxWidth: CGFloat = 560
    private static let metaReservedHeight: CGFloat = 54
    private static let ratingsReservedHeight: CGFloat = 54
    private static let summaryReservedHeight: CGFloat = 120
    private static let totalHeight: CGFloat =
        logoReservedHeight + metaReservedHeight + ratingsReservedHeight + summaryReservedHeight + (3 * SpaceTokens.spaceSm)

    @ObservedObject var infoState: HomeInfoState
    @ObservedObject var ratingsViewModel: MediaBarRatingsViewModel
    let contentLeading: CGFloat
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            ZStack(alignment: .leading) {
                if let logoUrl = infoState.selectedItemState.logoUrl,
                   let url = URL(string: logoUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: Self.logoMaxWidth, maxHeight: 120, alignment: .leading)
                        } else {
                            Color.clear
                        }
                    }
                } else if !infoState.selectedItemState.title.isEmpty {
                    Text(infoState.selectedItemState.title)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(height: Self.logoReservedHeight, alignment: .leading)

            SimpleInfoRow(
                item: infoState.selectedItemState.item,
                metadataSummary: infoState.selectedItemState.metadataSummary,
                sizeVariant: .small
            )
                .frame(height: Self.metaReservedHeight, alignment: .leading)

            ZStack(alignment: .leading) {
                MediaBarRatingsRow(
                    ratings: ratingsViewModel.ratings,
                    enableAdditionalRatings: ratingsViewModel.enableAdditionalRatings
                )
            }
            .frame(height: Self.ratingsReservedHeight, alignment: .leading)
            .opacity(ratingsViewModel.ratings.isEmpty ? 0 : 1)

            ZStack(alignment: .topLeading) {
                Text(infoState.selectedItemState.summary)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(4)
            }
            .frame(height: Self.summaryReservedHeight, alignment: .topLeading)
            .opacity(infoState.selectedItemState.summary.isEmpty ? 0 : 1)
        }
        .padding(.leading, contentLeading)
        .padding(.trailing, 50)
        .padding(.top, 80)
        .frame(height: Self.totalHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    override var canBecomeFocused: Bool { hasContent }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isFocused, context.focusHeading.contains(.up) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onReturnToMediaBar?()
        }
    }
}

