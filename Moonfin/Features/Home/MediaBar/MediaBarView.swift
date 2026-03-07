import SwiftUI

struct MediaBarView: View {
    @ObservedObject var viewModel: MediaBarViewModel
    let userPreferences: UserPreferences
    let screenHeight: CGFloat
    let focusNamespace: Namespace.ID
    let onItemSelected: (MediaBarSlideItem) -> Void
    let onNavigateDown: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

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
                    .prefersDefaultFocus(in: focusNamespace)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: screenHeight)
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
                FocusableMediaBarControl(
                    isFocused: $isFocused,
                    navbarIsLeft: navbarIsLeft,
                    onSelect: {
                        if let item = viewModel.currentItem {
                            onItemSelected(item)
                        }
                    },
                    onLeft: { viewModel.goToPrevious() },
                    onRight: { viewModel.goToNext() },
                    onDown: onNavigateDown
                )
                .frame(height: screenHeight - navbarClearance - 120)
                .padding(.leading, sidebarInset)
                .prefersDefaultFocus(in: focusNamespace)
                .onChange(of: isFocused) { focused in
                    viewModel.setFocused(focused)
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
                if let urlString = item.backdropUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                    .opacity(index == viewModel.currentIndex ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: viewModel.currentIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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
           let logoUrl = item.logoUrl,
           let url = URL(string: logoUrl) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 250, maxHeight: 100)
                }
            }
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

                Text(item.overview ?? " ")
                    .font(.titleXl)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
            .padding(.vertical, SpaceTokens.spaceMd)
            .padding(.horizontal, SpaceTokens.spaceXl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
        }
    }

    private func mediaBarMetadata(item: MediaBarSlideItem) -> some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if let year = item.year, year > 0 {
                metadataText(String(year))
            }

            if let rating = item.officialRating, !rating.isEmpty {
                metadataBadge(rating)
            }

            if let runtime = item.runtime {
                metadataText(runtime)
            }

            if let community = item.communityRating, community > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.colorYellow500)
                    metadataText(String(format: "%.1f", community))
                }
            }

            if let critic = item.criticRating, critic > 0 {
                let fresh = critic >= 60
                HStack(spacing: 4) {
                    Image(systemName: fresh ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .font(.system(size: 15))
                        .foregroundColor(fresh ? .colorGreen500 : .colorRed500)
                    metadataText("\(Int(critic))%")
                }
            }

            if !item.genres.isEmpty {
                metadataText(item.genres.prefix(3).joined(separator: ", "))
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.bodyMd)
            .foregroundColor(.white.opacity(0.7))
    }

    private func metadataBadge(_ text: String) -> some View {
        Text(text)
            .font(.bodyMd)
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

// MARK: - Focusable Media Bar Control

private struct FocusableMediaBarControl: UIViewRepresentable {
    var isFocused: FocusState<Bool>.Binding
    let navbarIsLeft: Bool
    let onSelect: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void
    let onDown: () -> Void

    func makeUIView(context: Context) -> FocusablePressView {
        let view = FocusablePressView()
        view.coordinator = context.coordinator
        view.navbarIsLeft = navbarIsLeft
        return view
    }

    func updateUIView(_ uiView: FocusablePressView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onLeft = onLeft
        context.coordinator.onRight = onRight
        context.coordinator.onDown = onDown
        context.coordinator.isFocused = isFocused
        uiView.navbarIsLeft = navbarIsLeft
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isFocused: isFocused, onSelect: onSelect, onLeft: onLeft, onRight: onRight, onDown: onDown)
    }

    final class Coordinator {
        var isFocused: FocusState<Bool>.Binding
        var onSelect: () -> Void
        var onLeft: () -> Void
        var onRight: () -> Void
        var onDown: () -> Void

        init(isFocused: FocusState<Bool>.Binding, onSelect: @escaping () -> Void, onLeft: @escaping () -> Void, onRight: @escaping () -> Void, onDown: @escaping () -> Void) {
            self.isFocused = isFocused
            self.onSelect = onSelect
            self.onLeft = onLeft
            self.onRight = onRight
            self.onDown = onDown
        }
    }
}

private class FocusablePressView: UIView {
    weak var coordinator: FocusableMediaBarControl.Coordinator?
    var navbarIsLeft = false

    override var canBecomeFocused: Bool { true }

    private var consumedTypes: Set<UIPress.PressType> {
        var types: Set<UIPress.PressType> = [.rightArrow, .select, .downArrow]
        if !navbarIsLeft { types.insert(.leftArrow) }
        return types
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        DispatchQueue.main.async { [weak self] in
            self?.coordinator?.isFocused.wrappedValue = self?.isFocused ?? false
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .leftArrow where !navbarIsLeft:
                coordinator?.onLeft()
            case .rightArrow: coordinator?.onRight()
            case .select:     coordinator?.onSelect()
            case .downArrow:  coordinator?.onDown()
            default: break
            }
        }
        if !isConsumedPress(presses) {
            super.pressesBegan(presses, with: event)
        }
    }

    private func isConsumedPress(_ presses: Set<UIPress>) -> Bool {
        let consumed = consumedTypes
        return presses.contains { consumed.contains($0.type) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !isConsumedPress(presses) {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !isConsumedPress(presses) {
            super.pressesCancelled(presses, with: event)
        }
    }
}
