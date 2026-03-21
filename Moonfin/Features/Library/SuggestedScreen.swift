import SwiftUI
import Nuke

struct SuggestedScreen: View {
    @StateObject private var viewModel: SuggestedViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(container: AppContainer, parentId: String) {
        _viewModel = StateObject(wrappedValue: SuggestedViewModel(
            container: container, parentId: parentId
        ))
    }

    var body: some View {
        ZStack {
            backdropLayer
            overlayLayer

            VStack(spacing: 0) {
                screenHeader
                    .padding(.horizontal, 60)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                if viewModel.isLoading && viewModel.rows.isEmpty {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                } else if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    suggestionRows
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            router.pushNavbarHidden()
            viewModel.initialize()
        }
        .onDisappear {
            router.popNavbarHidden()
        }
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ToolbarIconButton(
                    systemImage: "house",
                    isActive: false,
                    theme: theme,
                    action: { router.goBack() }
                )

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(theme.accent)
                    Text("Suggestions")
                        .font(.titleXl)
                        .foregroundColor(.white)
                }

                Spacer()
            }

            focusedItemInfo
        }
    }

    private var focusedItemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = viewModel.focusedItem {
                Text(item.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                let sub = viewModel.subtitle(for: item)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.bodySm)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 50, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text("No suggestions available")
                .font(.bodyLg)
                .foregroundColor(.white.opacity(0.3))
            Text("Watch some movies to get personalized recommendations")
                .font(.bodySm)
                .foregroundColor(.white.opacity(0.2))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestionRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.rows) { row in
                    suggestionRow(row: row)
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func suggestionRow(row: SuggestionRow) -> some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.bodyLg)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.colorScheme.onBackground)

                Text("(\(row.items.count))")
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(row.items) { item in
                        BrowseItemCard(
                            item: item,
                            imageUrl: viewModel.posterUrl(for: item),
                            subtitle: viewModel.subtitle(for: item),
                            theme: theme,
                            onFocused: { viewModel.setFocusedItem(item) },
                            onTap: { router.navigate(to: .itemDetails(itemId: item.id, serverId: item.serverId)) }
                        )
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 6)
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

    private var overlayLayer: some View {
        let hasBackdrop = viewModel.backgroundService.currentBackdropUrl != nil
        return Color(red: 0.063, green: 0.082, blue: 0.157)
            .opacity(hasBackdrop ? 0.5 : 0.75)
            .ignoresSafeArea()
    }
}
