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
            contentRows
        }
        .ignoresSafeArea()
        .environmentObject(viewModel.backgroundService)
        .onAppear { viewModel.loadContent() }
    }

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

    private var contentRows: some View {
        VStack {
            Spacer()
                .frame(height: 243)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                    let visibleRows = viewModel.rows.filter { !$0.isEmpty }
                    ForEach(visibleRows) { row in
                        ContentRow(row: row, viewModel: viewModel, watchedIndicator: viewModel.watchedIndicator)
                    }
                }
                .padding(.horizontal, 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
