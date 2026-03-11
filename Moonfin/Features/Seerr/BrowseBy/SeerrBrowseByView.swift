import SwiftUI

struct SeerrBrowseByView: View {
    @StateObject private var viewModel: SeerrBrowseByViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    private let columns = Array(repeating: GridItem(.fixed(150), spacing: SpaceTokens.spaceMd), count: 7)

    init(filterId: Int, filterName: String, mediaType: String, filterType: String,
         seerrRepository: SeerrRepositoryProtocol) {
        _viewModel = StateObject(wrappedValue: SeerrBrowseByViewModel(
            filterId: filterId, filterName: filterName,
            mediaType: mediaType, filterType: filterType,
            seerrRepository: seerrRepository
        ))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView().tint(theme.colorScheme.onBackground)
            } else if viewModel.items.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                contentView
            }
        }
        .onAppear { viewModel.loadInitial() }
        .sheet(isPresented: $viewModel.showSortPicker) { sortPickerSheet }
        .sheet(isPresented: $viewModel.showFilterPicker) { filterPickerSheet }
    }

    private var emptyView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            Text("No results found")
                .font(.titleMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
        }
        .padding(50)
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
                .padding(.horizontal, 50)
                .padding(.top, 40)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: SpaceTokens.spaceLg) {
                    ForEach(viewModel.items) { item in
                        SeerrItemCard(
                            item: item,
                            posterUrl: item.posterPath.map { SeerrImageUrl.poster($0) },
                            onSelect: {
                                if let json = viewModel.itemJson(item) {
                                    router.navigate(to: .seerrMediaDetails(itemJson: json))
                                }
                            }
                        )
                        .onAppear {
                            if item.id == viewModel.items.last?.id {
                                viewModel.loadMore()
                            }
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, 80)

                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(theme.colorScheme.onBackground)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text(viewModel.filterName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)
                Text(viewModel.resultCountText)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            }

            Spacer()

            HStack(spacing: SpaceTokens.spaceMd) {
                Button(action: { viewModel.showFilterPicker = true }) {
                    Label(viewModel.activeFilter.displayName, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.bodySm)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.showSortPicker = true }) {
                    Label(viewModel.sortOption.displayName, systemImage: "arrow.up.arrow.down")
                        .font(.bodySm)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortPickerSheet: some View {
        pickerSheet(title: "Sort By", items: SeerrBrowseSortOption.allCases,
                    label: \.displayName, isSelected: { $0 == viewModel.sortOption }) {
            viewModel.changeSortOption($0)
            viewModel.showSortPicker = false
        }
    }

    private var filterPickerSheet: some View {
        pickerSheet(title: "Filter", items: SeerrBrowseFilter.allCases,
                    label: \.displayName, isSelected: { $0 == viewModel.activeFilter }) {
            viewModel.changeFilter($0)
            viewModel.showFilterPicker = false
        }
    }

    private func pickerSheet<T: Hashable>(title: String, items: [T], label: KeyPath<T, String>,
                                          isSelected: @escaping (T) -> Bool,
                                          onSelect: @escaping (T) -> Void) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Text(title)
                .font(.title2xl).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)
                .padding(.top, SpaceTokens.spaceLg)

            ForEach(items, id: \.self) { item in
                Button(action: { onSelect(item) }) {
                    HStack {
                        Text(item[keyPath: label])
                            .foregroundColor(theme.colorScheme.onBackground)
                        Spacer()
                        if isSelected(item) {
                            Image(systemName: "checkmark")
                                .foregroundColor(theme.colorScheme.accent)
                        }
                    }
                    .padding(.horizontal, SpaceTokens.spaceLg)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(theme.colorScheme.surface.ignoresSafeArea())
    }
}
