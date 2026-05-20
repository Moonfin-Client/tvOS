import SwiftUI
import Nuke

struct MediaBarView: View {
    @ObservedObject var viewModel: MediaBarViewModel
    @ObservedObject var ratingsViewModel: MediaBarRatingsViewModel
    @ObservedObject var userPreferences: UserPreferences
    let screenHeight: CGFloat
    let onItemSelected: (MediaBarSlideItem) -> Void
    let onPlayTrailer: (MediaBarSlideItem) -> Void
    let onFocusedItemChanged: (MediaBarSlideItem?) -> Void
    let onNavigateDown: () -> Void
    let onNavigateUp: () -> Void
    @Binding var requestFocus: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool
    @ObservedObject var inlineTrailerPlayer: InlineTrailerPlayerManager
    @State private var inlineVideoOpacity: Double = 0
    @State private var lastMoveCommandAt: TimeInterval = 0
    @State private var makdBackdropScale: CGFloat = 1.0

    init(
        viewModel: MediaBarViewModel,
        ratingsViewModel: MediaBarRatingsViewModel,
        userPreferences: UserPreferences,
        screenHeight: CGFloat,
        inlineTrailerPlayer: InlineTrailerPlayerManager,
        onItemSelected: @escaping (MediaBarSlideItem) -> Void,
        onPlayTrailer: @escaping (MediaBarSlideItem) -> Void,
        onFocusedItemChanged: @escaping (MediaBarSlideItem?) -> Void,
        onNavigateDown: @escaping () -> Void,
        onNavigateUp: @escaping () -> Void,
        requestFocus: Binding<Bool>
    ) {
        self.viewModel = viewModel
        self.ratingsViewModel = ratingsViewModel
        self._userPreferences = ObservedObject(wrappedValue: userPreferences)
        self.screenHeight = screenHeight
        self.inlineTrailerPlayer = inlineTrailerPlayer
        self.onItemSelected = onItemSelected
        self.onPlayTrailer = onPlayTrailer
        self.onFocusedItemChanged = onFocusedItemChanged
        self.onNavigateDown = onNavigateDown
        self.onNavigateUp = onNavigateUp
        self._requestFocus = requestFocus
    }

    private let navbarClearance: CGFloat = 120

    private var sidebarInset: CGFloat {
        navbarIsLeft ? LeftSidebar.sidebarInset : 0
    }

    private var navbarIsLeft: Bool {
        userPreferences[UserPreferences.navbarPosition] == .left
    }

    private var overlayColor: Color {
        userPreferences[UserPreferences.mediaBarOverlayColor].color
    }

    private var overlayOpacity: Double {
        Double(userPreferences[UserPreferences.mediaBarOverlayOpacity]) / 100.0
    }

    private var mediaBarMode: MediaBarMode {
        userPreferences[UserPreferences.mediaBarMode]
    }

    private var isInlineTrailerActive: Bool {
        switch inlineTrailerPlayer.state {
        case .opening, .buffering, .playing, .paused:
            return true
        default:
            return false
        }
    }

    private func debugLog(_ event: String, details: String = "") {
#if DEBUG
        guard ProcessInfo.processInfo.environment["MOONFIN_HOME_FOCUS_DEBUG"] == "1" else {
            return
        }
        let timestamp = Date().timeIntervalSinceReferenceDate
        if details.isEmpty {
            print("[MediaBarNav] [\(timestamp)] \(event)")
        } else {
            print("[MediaBarNav] [\(timestamp)] \(event) | \(details)")
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

    private func safeFocusSurfaceHeight(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        if value.isFinite, value > 1 {
            return value
        }
        return fallback
    }

    var body: some View {
        let safeScreenHeight = max(screenHeight, 1)
        switch viewModel.state {
        case .ready(let items) where !items.isEmpty:
            switch mediaBarMode {
            case .off:
                EmptyView()
            case .moonfin:
                mediaBarContent(items: items, safeScreenHeight: safeScreenHeight)
            case .makd:
                makdMediaBarContent(items: items, safeScreenHeight: safeScreenHeight)
            }
        case .loading:
            if mediaBarMode == .off {
                EmptyView()
            } else {
            ZStack {
                loadingPlaceholder

                VStack(spacing: 0) {
                    Spacer().frame(height: navbarClearance)
                    mediaBarFocusSurface(
                        height: safeFocusSurfaceHeight(max(safeScreenHeight - navbarClearance, 1)),
                        activateOnSelect: false
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: safeScreenHeight)
            .onChange(of: viewModel.state) { newState in
                if case .loading = newState { return }
                if case .ready = newState { return }
                onNavigateDown()
            }
            }
        default:
            EmptyView()
        }
    }

    private func mediaBarContent(items: [MediaBarSlideItem], safeScreenHeight: CGFloat) -> some View {
        let compactInfo = isInlineTrailerActive

        return ZStack(alignment: .top) {
            backdropLayer(items: items)
            overlayGradient
            logoOverlay

            VStack(spacing: 0) {
                Spacer()

                infoCardContent(compact: compactInfo)
                    .padding(.horizontal, 100)
                    .padding(.bottom, compactInfo ? 16 : 40)
                    .background(
                        Group {
                            if !compactInfo {
                                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                                    .fill(overlayColor.opacity(overlayOpacity))
                                    .padding(.horizontal, 100)
                            }
                        }
                    )
                    .animation(.easeInOut(duration: 0.25), value: compactInfo)

                indicatorDots(items: items)
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)

            navigationArrows(items: items, rightInset: 0)

            VStack {
                Spacer().frame(height: navbarClearance + 20)
                mediaBarFocusSurface(
                    height: safeFocusSurfaceHeight(max(safeScreenHeight - navbarClearance - 120, 1)),
                    activateOnSelect: true
                )
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: safeScreenHeight)
        .clipped()
    }

    private func makdMediaBarContent(items: [MediaBarSlideItem], safeScreenHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let contentHeight = max(geo.size.height, 1)
            let contentWidth = max(geo.size.width, 1)

            ZStack(alignment: .topLeading) {
                makdBackdropLayer(items: items)
                makdGradientOverlay
                makdLogoOverlay(contentHeight: contentHeight, contentWidth: contentWidth)
                makdInfoContent(
                    contentWidth: contentWidth,
                    contentHeight: contentHeight,
                    compact: isInlineTrailerActive
                )

                VStack {
                    Spacer().frame(height: navbarClearance + 20)
                    mediaBarFocusSurface(
                        height: safeFocusSurfaceHeight(max(contentHeight - navbarClearance - 120, 1)),
                        activateOnSelect: true
                    )
                    Spacer()
                }

                if items.count > 1 {
                    makdDots(items: items)
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                }

                navigationArrows(items: items, rightInset: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: safeScreenHeight)
        .clipped()
    }

    private func mediaBarFocusSurface(height: CGFloat, activateOnSelect: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .frame(height: safeFocusSurfaceHeight(height))
            .focusable()
            .focused($isFocused)
            .padding(.leading, sidebarInset)
            .onTapGesture {
                if activateOnSelect {
                    debugLog("tap_select", details: "index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil")")
                    selectCurrentItem()
                }
            }
            .onMoveCommand { direction in
                guard isFocused else {
                    debugLog("move_command_ignored", details: "reason=not_focused direction=\(directionLabel(direction))")
                    return
                }
                let now = Date().timeIntervalSinceReferenceDate
                let repeatDeltaMs = lastMoveCommandAt > 0 ? Int((now - lastMoveCommandAt) * 1000) : -1
                lastMoveCommandAt = now
                debugLog(
                    "move_command",
                    details: "direction=\(directionLabel(direction)) repeat_delta_ms=\(repeatDeltaMs) index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil") focused=\(isFocused)"
                )
                switch direction {
                case .left:  viewModel.goToPrevious()
                case .right: viewModel.goToNext()
                case .up:    onNavigateUp()
                case .down:  onNavigateDown()
                default:     break
                }
            }
            .onPlayPauseCommand {
                debugLog("play_pause_command", details: "index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil")")
                if let item = viewModel.currentItem {
                    onPlayTrailer(item)
                }
            }
            .onChange(of: isFocused) { focused in
                debugLog("focus_surface_changed", details: "focused=\(focused) index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil")")
                viewModel.setFocused(focused)
                onFocusedItemChanged(focused ? viewModel.currentItem : nil)
            }
            .onChange(of: viewModel.currentIndex) { _ in
                debugLog("current_index_changed", details: "index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil") focused=\(isFocused)")
                if isFocused {
                    onFocusedItemChanged(viewModel.currentItem)
                }
            }
            .onChange(of: requestFocus) { shouldFocus in
                if shouldFocus {
                    debugLog("request_focus_received", details: "index=\(viewModel.currentIndex) item_id=\(viewModel.currentItem?.id ?? "nil")")
                    isFocused = true
                    requestFocus = false
                }
            }
    }

    private func selectCurrentItem() {
        if let item = viewModel.currentItem {
            onItemSelected(item)
        }
    }

    private func backdropLayer(items: [MediaBarSlideItem]) -> some View {
        ZStack {
            let visible = visibleIndices(current: viewModel.currentIndex, total: items.count)
            ForEach(visible, id: \.self) { index in
                let item = items[index]
                CachedImage(
                    urlString: item.backdropUrl,
                    processors: [
                        ImageProcessors.Resize(
                            size: CGSize(width: 1920, height: 1080),
                            contentMode: .aspectFill
                        )
                    ]
                )
                .opacity(index == viewModel.currentIndex ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: viewModel.currentIndex)
            }

            InlineTrailerSurfaceHost(manager: inlineTrailerPlayer)
                .opacity(inlineVideoOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: inlineTrailerPlayer.state) { newState in
            switch newState {
            case .playing:
                withAnimation(.easeInOut(duration: 1.5)) { inlineVideoOpacity = 1.0 }
            case .stopped, .ended, .idle, .error:
                withAnimation(.easeInOut(duration: 0.6)) { inlineVideoOpacity = 0 }
            default:
                break
            }
        }
        .onChange(of: viewModel.currentIndex) { _ in
            withAnimation(.easeInOut(duration: 0.4)) { inlineVideoOpacity = 0 }
        }
    }

    private func makdBackdropLayer(items: [MediaBarSlideItem]) -> some View {
        ZStack {
            let visible = visibleIndices(current: viewModel.currentIndex, total: items.count)
            ForEach(visible, id: \.self) { index in
                let item = items[index]
                let isCurrent = index == viewModel.currentIndex

                CachedImage(
                    urlString: item.backdropUrl,
                    processors: [
                        ImageProcessors.Resize(
                            size: CGSize(width: 1920, height: 1080),
                            contentMode: .aspectFill
                        )
                    ]
                )
                .scaleEffect(isCurrent ? makdBackdropScale : 1.0)
                .opacity(isCurrent ? 1 : 0)
                .animation(.easeInOut(duration: 0.8), value: viewModel.currentIndex)
            }

            InlineTrailerSurfaceHost(manager: inlineTrailerPlayer)
                .opacity(inlineVideoOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            restartMakdKenBurns()
        }
        .onChange(of: inlineTrailerPlayer.state) { newState in
            switch newState {
            case .playing:
                withAnimation(.easeInOut(duration: 1.5)) { inlineVideoOpacity = 1.0 }
            case .stopped, .ended, .idle, .error:
                withAnimation(.easeInOut(duration: 0.6)) { inlineVideoOpacity = 0 }
            default:
                break
            }
        }
        .onChange(of: viewModel.currentIndex) { _ in
            withAnimation(.easeInOut(duration: 0.4)) { inlineVideoOpacity = 0 }
            restartMakdKenBurns()
        }
    }

    private func restartMakdKenBurns() {
        makdBackdropScale = 1.0
        withAnimation(.easeOut(duration: 10)) {
            makdBackdropScale = 1.08
        }
    }

    private func visibleIndices(current: Int, total: Int) -> [Int] {
        guard total > 0 else { return [] }
        if total <= 3 { return Array(0..<total) }
        let prev = (current - 1 + total) % total
        let next = (current + 1) % total
        return [prev, current, next]
    }

    private var overlayGradient: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.4),
                    .init(color: overlayColor.opacity(overlayOpacity * 0.5), location: 0.75),
                    .init(color: overlayColor.opacity(overlayOpacity * 0.8), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: overlayColor.opacity(overlayOpacity * 0.3), location: 0),
                    .init(color: .clear, location: 0.35)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var makdGradientOverlay: some View {
        let scrim = theme.colorScheme.scrim
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: scrim.opacity(0.78), location: 0.0),
                    .init(color: scrim.opacity(0.46), location: 0.46),
                    .init(color: scrim.opacity(0.06), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: scrim.opacity(0.12), location: 0.0),
                    .init(color: scrim.opacity(0.28), location: 0.48),
                    .init(color: scrim.opacity(0.78), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var logoOverlay: some View {
        if let item = viewModel.currentItem,
           let logoUrl = item.logoUrl {
            CachedImage(
                urlString: logoUrl,
                contentMode: .fit,
                processors: [
                    ImageProcessors.Resize(
                        size: CGSize(width: 250, height: 100),
                        contentMode: .aspectFit
                    )
                ]
            )
            .frame(maxWidth: 250, maxHeight: 100)
            .padding(.top, 150)
            .padding(.leading, 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
        }
    }

    @ViewBuilder
    private func makdLogoOverlay(contentHeight: CGFloat, contentWidth: CGFloat) -> some View {
        if let item = viewModel.currentItem,
           let logoUrl = item.logoUrl {
            let logoWidth = min(max(contentWidth * 0.45, 220), 640)
            let logoHeight = min(max(contentHeight * 0.35, 90), 300)

            CachedImage(
                urlString: logoUrl,
                contentMode: .fit,
                processors: [
                    ImageProcessors.Resize(
                        size: CGSize(width: logoWidth, height: logoHeight),
                        contentMode: .aspectFit
                    )
                ]
            )
            .frame(width: logoWidth, height: logoHeight, alignment: .leading)
            .padding(.leading, 50 + sidebarInset)
            .padding(.top, contentHeight * 0.22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func infoCardContent(compact: Bool) -> some View {
        if let item = viewModel.currentItem {
            VStack(alignment: .leading, spacing: compact ? SpaceTokens.spaceXs : SpaceTokens.spaceSm) {
                mediaBarMetadata(item: item)

                if !compact, !ratingsViewModel.ratings.isEmpty {
                    MediaBarRatingsRow(
                        ratings: ratingsViewModel.ratings,
                        enableAdditionalRatings: ratingsViewModel.enableAdditionalRatings
                    )
                }

                if !compact {
                    Text(item.overview ?? " ")
                        .font(.bodySm)
                        .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.85))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                }
            }
            .padding(.vertical, compact ? SpaceTokens.spaceSm : SpaceTokens.spaceMd)
            .padding(.horizontal, compact ? SpaceTokens.spaceLg : SpaceTokens.spaceXl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
            .animation(.easeInOut(duration: 0.25), value: compact)
            .onChange(of: viewModel.currentIndex) { _ in
                if let item = viewModel.currentItem {
                    ratingsViewModel.loadRatings(for: item)
                }
            }
            .onAppear {
                ratingsViewModel.loadRatings(for: item)
            }
        }
    }

    @ViewBuilder
    private func makdInfoContent(contentWidth: CGFloat, contentHeight: CGFloat, compact: Bool) -> some View {
        if let item = viewModel.currentItem {
            let blockWidth = min(max(contentWidth * 0.5, 320), 960)
            let infoMinHeight = compact
                ? min(max(contentHeight * 0.12, 62), 96)
                : min(max(contentHeight * 0.34, 210), 320)

            VStack(alignment: .leading, spacing: compact ? SpaceTokens.spaceXs : SpaceTokens.spaceSm) {
                mediaBarMetadata(item: item)

                if !compact, !ratingsViewModel.ratings.isEmpty {
                    MediaBarRatingsRow(
                        ratings: ratingsViewModel.ratings,
                        enableAdditionalRatings: ratingsViewModel.enableAdditionalRatings
                    )
                }

                if !compact, let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.bodySm)
                        .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.88))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: blockWidth, alignment: .leading)
            .frame(minHeight: infoMinHeight, alignment: .topLeading)
            .padding(.leading, 34 + sidebarInset)
            .padding(.bottom, compact ? 12 : 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
            .animation(.easeInOut(duration: 0.25), value: compact)
            .onChange(of: viewModel.currentIndex) { _ in
                if let item = viewModel.currentItem {
                    ratingsViewModel.loadRatings(for: item)
                }
            }
            .onAppear {
                ratingsViewModel.loadRatings(for: item)
            }
            .allowsHitTesting(false)
        }
    }

    private func mediaBarMetadata(item: MediaBarSlideItem) -> some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if let year = item.year, year > 0 {
                metadataText(String(year))
            }

            if let rating = item.officialRating, !rating.isEmpty {
                metadataSeparator
                metadataBadge(rating)
            }

            if let runtime = item.runtime {
                metadataSeparator
                metadataText(runtime)
            }

            if !item.genres.isEmpty {
                metadataSeparator
                metadataText(item.genres.prefix(3).joined(separator: ", "))
            }
        }
    }

    private var metadataSeparator: some View {
        Text("\u{2022}")
            .font(.captionXs)
            .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor.opacity(0.7) : .white.opacity(0.4))
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.captionXs)
            .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.7))
    }

    private func metadataBadge(_ text: String) -> some View {
        Text(text)
            .font(.captionXs)
            .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.8))
            .padding(.horizontal, SpaceTokens.spaceXs)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                    .stroke(theme.isNeonPulseTheme ? theme.neonPrimaryColor.opacity(0.85) : .white.opacity(0.3), lineWidth: 1)
            )
    }

    private func indicatorDots(items: [MediaBarSlideItem]) -> some View {
        HStack(spacing: SpaceTokens.spaceXs) {
            ForEach(0..<items.count, id: \.self) { index in
                let isActive = index == viewModel.currentIndex
                Circle()
                    .fill(isActive ? .white : .white.opacity(0.5))
                    .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentIndex)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(overlayColor.opacity(overlayOpacity * 0.6))
        )
    }

    private func makdDots(items: [MediaBarSlideItem]) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<items.count, id: \.self) { index in
                let isActive = index == viewModel.currentIndex
                Circle()
                    .fill(.white.opacity(isActive ? 1 : 0.5))
                    .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentIndex)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(theme.colorScheme.scrim.opacity(0.5))
        )
    }

    @ViewBuilder
    private func navigationArrows(items: [MediaBarSlideItem], rightInset: CGFloat) -> some View {
        if items.count > 1 {
            HStack {
                if !navbarIsLeft {
                    navArrowButton(symbol: "chevron.left")
                }

                Spacer(minLength: 0)

                navArrowButton(symbol: "chevron.right")
            }
            .padding(.leading, sidebarInset + 10)
            .padding(.trailing, rightInset + 10)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func navArrowButton(symbol: String) -> some View {
        let iconColor = theme.isNeonPulseTheme ? theme.neonPrimaryColor : theme.colorScheme.onBackground
        let fillColor = theme.isNeonPulseTheme
            ? theme.colorScheme.surface.opacity(0.52)
            : theme.colorScheme.scrim.opacity(0.42)
        let strokeColor = theme.isNeonPulseTheme
            ? theme.neonSecondaryColor.opacity(0.65)
            : theme.colorScheme.onBackground.opacity(0.3)

        return Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundColor(iconColor)
            .padding(12)
            .background(
                Circle()
                    .fill(fillColor)
            )
            .overlay(
                Circle()
                    .stroke(strokeColor, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(theme.colorScheme.surface.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: max(screenHeight, 1))
    }
}

private class TrailerHostView: UIView {
    var onWindowAttach: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onWindowAttach?()
            onWindowAttach = nil
        }
    }
}

private struct InlineTrailerSurfaceHost: UIViewRepresentable {
    let manager: InlineTrailerPlayerManager

    func makeUIView(context: Context) -> UIView {
        let host = TrailerHostView()
        host.backgroundColor = .clear
        host.clipsToBounds = true
        let surface = manager.surface
        surface.frame = host.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(surface)
        host.onWindowAttach = { [weak manager] in
            manager?.player?.notifySurfaceReady()
        }
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        let surface = manager.surface
        if surface.superview !== host {
            surface.frame = host.bounds
            host.addSubview(surface)
        } else {
            surface.frame = host.bounds
        }
    }
}

