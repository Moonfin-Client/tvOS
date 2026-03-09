import SwiftUI

struct ContentRow: View {
    let row: HomeRow
    let viewModel: HomeViewModel
    var watchedIndicator: WatchedIndicatorBehavior = .always
    var onRowFocused: (() -> Void)?
    var onItemSelected: ((ServerItem) -> Void)?
    var restoredItemId: String?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        if row.isLoading {
            loadingRow
        } else if !row.items.isEmpty {
            itemRow
        }
    }

    private var rowTitle: some View {
        Text(row.title)
            .font(.bodyLg)
            .fontWeight(.semibold)
            .foregroundColor(theme.colorScheme.onBackground)
    }

    private var loadingRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.surface.opacity(0.2))
                            .aspectRatio(row.rowType.aspectRatio, contentMode: .fit)
                            .frame(width: row.rowType.cardWidth)
                            .shimmering()
                    }
                }
            }
        }
    }

    private var itemRow: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            rowTitle

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: SpaceTokens.spaceMd) {
                        ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                            cardView(for: item)
                                .id(item.id)
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(row: row, currentIndex: index)
                                }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .modifier(ScrollClipDisabledModifier())
                .onAppear {
                    if let targetId = restoredItemId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollProxy.scrollTo(targetId, anchor: .leading)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(for item: ServerItem) -> some View {
        if row.rowType == .libraryTiles {
            LibraryCard(
                item: item,
                imageUrl: viewModel.thumbImageUrl(for: item),
                cardWidth: row.rowType.cardWidth,
                onFocused: { item in
                    viewModel.onItemFocused(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        } else {
            ItemPreview(
                item: item,
                imageUrl: imageUrl(for: item),
                aspectRatio: row.rowType.aspectRatio,
                cardWidth: row.rowType.cardWidth,
                watchedIndicator: watchedIndicator,
                onFocused: { item in
                    viewModel.onItemFocused(item)
                    onRowFocused?()
                },
                onSelect: { onItemSelected?(item) }
            )
        }
    }

    private func imageUrl(for item: ServerItem) -> String? {
        switch row.rowType {
        case .continueWatching, .nextUp, .liveTv:
            return viewModel.thumbImageUrl(for: item)
        default:
            return viewModel.posterImageUrl(for: item)
        }
    }
}

private struct ScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(tvOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, phase - 0.3)),
                        .init(color: .white.opacity(0.1), location: phase),
                        .init(color: .clear, location: min(1, phase + 0.3)),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
