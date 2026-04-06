import SwiftUI
import Nuke

struct MediaBarView: View {
    @ObservedObject var viewModel: MediaBarViewModel
    @ObservedObject var ratingsViewModel: MediaBarRatingsViewModel
    let userPreferences: UserPreferences
    let screenHeight: CGFloat
    let onItemSelected: (MediaBarSlideItem) -> Void
    let onPlayTrailer: (MediaBarSlideItem) -> Void
    let onFocusedItemChanged: (MediaBarSlideItem?) -> Void
    let onNavigateDown: () -> Void
    let onNavigateUp: () -> Void
    @Binding var requestFocus: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool
    @ObservedObject var inlineTrailerPlayer: MpvPlayerWrapper
    @State private var inlineVideoOpacity: Double = 0

    init(
        viewModel: MediaBarViewModel,
        ratingsViewModel: MediaBarRatingsViewModel,
        userPreferences: UserPreferences,
        screenHeight: CGFloat,
        inlineTrailerPlayer: MpvPlayerWrapper,
        onItemSelected: @escaping (MediaBarSlideItem) -> Void,
        onPlayTrailer: @escaping (MediaBarSlideItem) -> Void,
        onFocusedItemChanged: @escaping (MediaBarSlideItem?) -> Void,
        onNavigateDown: @escaping () -> Void,
        onNavigateUp: @escaping () -> Void,
        requestFocus: Binding<Bool>
    ) {
        self.viewModel = viewModel
        self.ratingsViewModel = ratingsViewModel
        self.userPreferences = userPreferences
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

    var body: some View {
        switch viewModel.state {
        case .ready(let items) where !items.isEmpty:
            mediaBarContent(items: items)
        case .loading:
            ZStack {
                loadingPlaceholder

                VStack(spacing: 0) {
                    Spacer().frame(height: navbarClearance)
                    Button(action: {}) {
                        Color.white.opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(MediaBarButtonStyle())
                    .focused($isFocused)
                    .padding(.leading, sidebarInset)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: screenHeight)
            .onChange(of: viewModel.state) { newState in
                if case .loading = newState { return }
                if case .ready = newState { return }
                onNavigateDown()
            }
        default:
            EmptyView()
        }
    }

    private func mediaBarContent(items: [MediaBarSlideItem]) -> some View {
        ZStack(alignment: .top) {
            backdropLayer(items: items)
            overlayGradient
            logoOverlay

            VStack(spacing: 0) {
                Spacer()

                infoCardContent
                    .padding(.horizontal, 100)
                    .padding(.bottom, 40)
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.medium)
                            .fill(overlayColor.opacity(overlayOpacity))
                            .padding(.horizontal, 100)
                    )

                indicatorDots(items: items)
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)

            VStack {
                Spacer().frame(height: navbarClearance + 20)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .frame(height: screenHeight - navbarClearance - 120)
                    .focusable()
                    .focused($isFocused)
                    .padding(.leading, sidebarInset)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left:  viewModel.goToPrevious()
                        case .right: viewModel.goToNext()
                        case .up:    onNavigateUp()
                        case .down:  onNavigateDown()
                        default:     break
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.01) {
                        if let item = viewModel.currentItem {
                            onItemSelected(item)
                        }
                    }
                    .onPlayPauseCommand {
                        if let item = viewModel.currentItem {
                            onPlayTrailer(item)
                        }
                    }
                    .onChange(of: isFocused) { focused in
                        viewModel.setFocused(focused)
                        onFocusedItemChanged(focused ? viewModel.currentItem : nil)
                    }
                    .onChange(of: viewModel.currentIndex) { _ in
                        if isFocused {
                            onFocusedItemChanged(viewModel.currentItem)
                        }
                    }
                    .onChange(of: requestFocus) { shouldFocus in
                        if shouldFocus {
                            isFocused = true
                            requestFocus = false
                        }
                    }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: screenHeight)
        .clipped()
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

            PlaybackSurfaceView(player: inlineTrailerPlayer)
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
    private var infoCardContent: some View {
        if let item = viewModel.currentItem {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                mediaBarMetadata(item: item)

                if !ratingsViewModel.ratings.isEmpty {
                    MediaBarRatingsRow(
                        ratings: ratingsViewModel.ratings,
                        enableAdditionalRatings: ratingsViewModel.enableAdditionalRatings
                    )
                }

                Text(item.overview ?? " ")
                    .font(.bodyMd)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
            .padding(.vertical, SpaceTokens.spaceMd)
            .padding(.horizontal, SpaceTokens.spaceXl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
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
            .font(.bodySm)
            .foregroundColor(.white.opacity(0.4))
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.bodySm)
            .foregroundColor(.white.opacity(0.7))
    }

    private func metadataBadge(_ text: String) -> some View {
        Text(text)
            .font(.bodySm)
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, SpaceTokens.spaceXs)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
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

    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(theme.colorScheme.surface.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: screenHeight)
    }
}

private struct MediaBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}


