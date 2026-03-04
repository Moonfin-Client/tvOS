import SwiftUI

struct HomeScreen: View {
    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(container: container))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdropLayer
            gradientOverlay
            infoArea
            contentRowsPlaceholder
        }
        .ignoresSafeArea()
        .environmentObject(viewModel.backgroundService)
    }

    // MARK: - Background Layer

    private var backdropLayer: some View {
        GeometryReader { geo in
            if let urlString = viewModel.backgroundService.currentBackdropUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: viewModel.backgroundService.blurAmount)
                    case .failure:
                        Color.clear
                    case .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .transition(.opacity)
                .id(urlString)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: viewModel.backgroundService.currentBackdropUrl)
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

    // MARK: - Info Area

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            if let logoUrl = viewModel.selectedItemState.logoUrl,
               let url = URL(string: logoUrl) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 60)
                    }
                }
            } else if !viewModel.selectedItemState.title.isEmpty {
                Text(viewModel.selectedItemState.title)
                    .font(.title3xl)
                    .fontWeight(.bold)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
            }

            SimpleInfoRow(item: viewModel.selectedItemState.item)

            if !viewModel.selectedItemState.summary.isEmpty {
                Text(viewModel.selectedItemState.summary)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(4)
                    .frame(maxWidth: 600, alignment: .leading)
            }
        }
        .padding(.leading, 50)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedItemState.title)
    }

    // MARK: - Content Rows Area

    private var contentRowsPlaceholder: some View {
        VStack {
            Spacer()
                .frame(height: 243)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                    ForEach(0..<5, id: \.self) { index in
                        PlaceholderRow(index: index)
                    }
                }
                .padding(.horizontal, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PlaceholderRow: View {
    let index: Int
    @EnvironmentObject var theme: MoonfinTheme

    private var rowTitle: String {
        switch index {
        case 0: return "Continue Watching"
        case 1: return "Next Up"
        case 2: return "Latest Movies"
        case 3: return "Latest TV Shows"
        case 4: return "Libraries"
        default: return "Row \(index)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(rowTitle)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<8, id: \.self) { cardIndex in
                        PlaceholderCard(rowIndex: index, cardIndex: cardIndex)
                    }
                }
            }
        }
    }
}

private struct PlaceholderCard: View {
    let rowIndex: Int
    let cardIndex: Int
    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var aspectRatio: CGFloat {
        rowIndex <= 1 ? 16.0 / 9.0 : 2.0 / 3.0
    }

    private var cardWidth: CGFloat {
        rowIndex <= 1 ? 280 : 150
    }

    var body: some View {
        RoundedRectangle(cornerRadius: RadiusTokens.small)
            .fill(theme.colorScheme.surface.opacity(isFocused ? 0.6 : 0.3))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: cardWidth)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(
                        isFocused ? theme.accent : Color.clear,
                        lineWidth: isFocused ? 3 : 0
                    )
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
    }
}
