import SwiftUI

private enum ShuffleOverlayFocusTarget: Hashable {
    case poster(String)
    case actionLibrary
    case actionRandom
    case actionGenres
    case pickerLibrary(String)
    case pickerGenre(String)
}

@MainActor
private final class ShuffleOverlayViewModel: ObservableObject {
    enum Mode {
        case main
        case libraries
        case genres
    }

    enum LoadTrigger {
        case initial
        case random
        case library
        case genre
    }

    @Published var mode: Mode = .main
    @Published private(set) var previewItems: [ServerItem] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingGenres = false
    @Published private(set) var selectedItemId: String?
    @Published private(set) var loadError: String?
    @Published private(set) var activeLibraryId: String?
    @Published private(set) var activeGenreName: String?
    @Published private(set) var activeLoadTrigger: LoadTrigger = .initial

    private let fetchGenresAction: (_ libraryId: String?) async -> [String]
    private let fetchPreviewItemsAction: (_ libraryId: String?, _ genreName: String?) async -> [ServerItem]
    private var loadTask: Task<Void, Never>?
    private var genresTask: Task<Void, Never>?

    init(
        fetchGenres: @escaping (_ libraryId: String?) async -> [String],
        fetchPreviewItems: @escaping (_ libraryId: String?, _ genreName: String?) async -> [ServerItem]
    ) {
        self.fetchGenresAction = fetchGenres
        self.fetchPreviewItemsAction = fetchPreviewItems
    }

    deinit {
        loadTask?.cancel()
        genresTask?.cancel()
    }

    var selectedItem: ServerItem? {
        guard let selectedItemId else { return previewItems.first }
        return previewItems.first(where: { $0.id == selectedItemId }) ?? previewItems.first
    }

    func onAppear() {
        if previewItems.isEmpty {
            reloadPreview(trigger: .initial, requestInitialSelection: true)
        }
    }

    func onDisappear() {
        loadTask?.cancel()
        genresTask?.cancel()
    }

    func scopeLabel(libraries: [ServerItem]) -> String {
        if let activeGenreName, !activeGenreName.isEmpty {
            return "\(Strings.genreSingular): \(activeGenreName)"
        }
        if let activeLibraryId,
           let libraryName = libraries.first(where: { $0.id == activeLibraryId })?.name,
           !libraryName.isEmpty {
            return "\(Strings.librarySingular): \(libraryName)"
        }
        return Strings.shuffleAll
    }

    func reloadRandomPreview() {
        reloadPreview(trigger: .random, requestInitialSelection: true)
    }

    func openLibraryPicker() {
        mode = .libraries
    }

    func openGenrePicker() {
        mode = .genres
        genres = []
        loadGenres(force: true)
    }

    func selectLibrary(_ libraryId: String) {
        activeLibraryId = libraryId
        activeGenreName = nil
        genres = []
        mode = .main
        reloadPreview(trigger: .library, requestInitialSelection: true)
    }

    func selectGenre(_ genre: String) {
        activeGenreName = genre
        mode = .main
        reloadPreview(trigger: .genre, requestInitialSelection: true)
    }

    func setSelectedItemId(_ itemId: String) {
        guard previewItems.contains(where: { $0.id == itemId }) else { return }
        selectedItemId = itemId
    }

    @discardableResult
    func goBackToMainIfNeeded() -> Bool {
        guard mode != .main else { return false }
        mode = .main
        return true
    }

    private func loadGenres(force: Bool = false) {
        guard !isLoadingGenres else { return }
        if !force, !genres.isEmpty { return }

        isLoadingGenres = true
        let requestedLibraryId = activeLibraryId

        genresTask?.cancel()
        genresTask = Task {
            let fetchedGenres = await fetchGenresAction(requestedLibraryId)
            guard !Task.isCancelled else { return }

            guard requestedLibraryId == activeLibraryId else {
                isLoadingGenres = false
                return
            }

            genres = fetchedGenres
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            isLoadingGenres = false
        }
    }

    private func reloadPreview(trigger: LoadTrigger, requestInitialSelection: Bool) {
        activeLoadTrigger = trigger
        isLoading = true
        loadError = nil

        let libraryId = activeLibraryId
        let genreName = activeGenreName
        let previousSelection = selectedItemId

        loadTask?.cancel()
        loadTask = Task {
            let items = await fetchPreviewItemsAction(libraryId, genreName)
            guard !Task.isCancelled else { return }

            previewItems = items

            if requestInitialSelection || previousSelection == nil || !items.contains(where: { $0.id == previousSelection }) {
                selectedItemId = items.first?.id
            } else {
                selectedItemId = previousSelection
            }

            if items.isEmpty {
                loadError = Strings.shuffleNoItems
            }

            isLoading = false
        }
    }
}

struct ShuffleOptionsDialog: View {
    let libraries: [ServerItem]
    let onSelectItem: (ServerItem) -> Void
    let onDismiss: () -> Void
    let fetchGenres: (_ libraryId: String?) async -> [String]
    let fetchPreviewItems: (_ libraryId: String?, _ genreName: String?) async -> [ServerItem]
    let fetchRatings: (ServerItem) async -> [(String, Float)]
    let posterUrlForItem: (ServerItem) -> String?
    let enableAdditionalRatings: Bool

    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var theme: MoonfinTheme
    @StateObject private var overlayViewModel: ShuffleOverlayViewModel
    @State private var hasScreensaverLock = false
    @State private var displayRatings: [(String, Float)] = []
    @State private var ratingsTask: Task<Void, Never>?
    @FocusState private var focusedTarget: ShuffleOverlayFocusTarget?

    init(
        libraries: [ServerItem],
        onSelectItem: @escaping (ServerItem) -> Void,
        onDismiss: @escaping () -> Void,
        fetchGenres: @escaping (_ libraryId: String?) async -> [String],
        fetchPreviewItems: @escaping (_ libraryId: String?, _ genreName: String?) async -> [ServerItem],
        fetchRatings: @escaping (ServerItem) async -> [(String, Float)],
        posterUrlForItem: @escaping (ServerItem) -> String?,
        enableAdditionalRatings: Bool
    ) {
        self.libraries = libraries
        self.onSelectItem = onSelectItem
        self.onDismiss = onDismiss
        self.fetchGenres = fetchGenres
        self.fetchPreviewItems = fetchPreviewItems
        self.fetchRatings = fetchRatings
        self.posterUrlForItem = posterUrlForItem
        self.enableAdditionalRatings = enableAdditionalRatings
        _overlayViewModel = StateObject(
            wrappedValue: ShuffleOverlayViewModel(
                fetchGenres: fetchGenres,
                fetchPreviewItems: fetchPreviewItems
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
                topStrip

                switch overlayViewModel.mode {
                case .main:
                    mainContent
                case .libraries, .genres:
                    pickerContent
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 24)
            .frame(maxWidth: dialogMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.extraLarge)
                    .fill(theme.colorScheme.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: RadiusTokens.extraLarge)
                            .stroke(theme.colorScheme.onBackground.opacity(0.18), lineWidth: 1.5)
                    )
            )
            .overlay(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: RadiusTokens.extraLarge)
                    .stroke(theme.effectiveFocusColor.opacity(0.18), lineWidth: 2)
                    .padding(1)
            }
            .padding(.horizontal, 52)
            .padding(.vertical, 34)
        }
        .focusSection()
        .onAppear {
            overlayViewModel.onAppear()
            container.inactivityTracker.notifyInteraction()
            if !hasScreensaverLock {
                hasScreensaverLock = true
                container.inactivityTracker.addLock()
            }
            if focusedTarget == nil {
                focusedTarget = .actionRandom
            }
            reloadRatingsForSelection()
        }
        .onDisappear {
            overlayViewModel.onDisappear()
            ratingsTask?.cancel()
            if hasScreensaverLock {
                hasScreensaverLock = false
                container.inactivityTracker.removeLock()
            }
        }
        .onChange(of: overlayViewModel.mode) { mode in
            switch mode {
            case .main:
                if let selectedId = overlayViewModel.selectedItemId {
                    focusedTarget = .poster(selectedId)
                } else {
                    focusedTarget = .actionRandom
                }
            case .libraries:
                focusedTarget = libraries.first.map { .pickerLibrary($0.id) }
            case .genres:
                focusedTarget = overlayViewModel.genres.first.map { .pickerGenre($0) }
            }
        }
        .onChange(of: overlayViewModel.previewItems.map(\.id)) { itemIds in
            guard overlayViewModel.mode == .main,
                  let firstId = itemIds.first
            else { return }
            focusedTarget = .poster(firstId)
        }
        .onChange(of: overlayViewModel.genres) { genres in
            guard overlayViewModel.mode == .genres,
                  let firstGenre = genres.first
            else { return }
            focusedTarget = .pickerGenre(firstGenre)
        }
        .onChange(of: overlayViewModel.selectedItemId) { selectedId in
            reloadRatingsForSelection()

            guard overlayViewModel.mode == .main,
                let selectedId,
                isPosterFocusTarget(focusedTarget)
            else { return }
            focusedTarget = .poster(selectedId)
        }
        .onChange(of: focusedTarget) { newValue in
            guard case .poster(let id) = newValue else { return }
            overlayViewModel.setSelectedItemId(id)
        }
        .onExitCommand {
            if overlayViewModel.goBackToMainIfNeeded() {
                if let selectedId = overlayViewModel.selectedItemId {
                    focusedTarget = .poster(selectedId)
                }
                return
            }
            onDismiss()
        }
    }

    private var topStrip: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.shuffleBy)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(theme.colorScheme.onBackground)

                Text(overlayViewModel.scopeLabel(libraries: libraries))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.72))
            }

            Spacer(minLength: SpaceTokens.spaceMd)
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            if overlayViewModel.isLoading {
                HStack(spacing: SpaceTokens.spaceSm) {
                    ProgressView()
                    Text(Strings.loading)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            carouselRow
                .padding(.top, -20)

            if let selectedItem = overlayViewModel.selectedItem {
                detailsPanel(for: selectedItem)
            } else {
                Text(overlayViewModel.loadError ?? Strings.shuffleNoItems)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
            }

            actionCards
        }
    }

    private var dialogMaxWidth: CGFloat {
        overlayViewModel.mode == .main ? 1520 : 1360
    }

    private var carouselRow: some View {
        HStack(spacing: 60) {
            if overlayViewModel.previewItems.isEmpty {
                RoundedRectangle(cornerRadius: RadiusTokens.large)
                    .fill(theme.colorScheme.surface.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay(
                        Text(overlayViewModel.loadError ?? Strings.shuffleNoItems)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    )
            } else {
                ForEach(overlayViewModel.previewItems) { item in
                    let target = ShuffleOverlayFocusTarget.poster(item.id)
                    let isFocused = focusedTarget == target
                    let isSelected = overlayViewModel.selectedItemId == item.id

                    ShufflePosterCard(
                        imageUrl: posterUrlForItem(item),
                        isFocused: isFocused,
                        isSelected: isSelected,
                        onSelect: {
                            if isSelected {
                                onSelectItem(item)
                            } else {
                                overlayViewModel.setSelectedItemId(item.id)
                            }
                        }
                    )
                    .focused($focusedTarget, equals: target)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(minHeight: 280, alignment: .top)
    }

    private func detailsPanel(for item: ServerItem) -> some View {
        let overviewText = descriptionText(for: item)

        return VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(item.name)
                .font(.titleLg)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(2)

            metadataRow(for: item)

            let ratings = displayRatings.isEmpty ? ratingsFor(item) : displayRatings
            if !ratings.isEmpty {
                MediaBarRatingsRow(
                    ratings: ratings,
                    enableAdditionalRatings: enableAdditionalRatings
                )
            }

            Text(overviewText)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.82))
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .stroke(theme.colorScheme.onBackground.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var actionCards: some View {
        HStack(spacing: 12) {
            ShuffleActionCard(
                title: Strings.selectLibrary.uppercased(),
                subtitle: Strings.librarySingular,
                systemIcon: "books.vertical.fill",
                isFocused: focusedTarget == .actionLibrary,
                isLoading: overlayViewModel.isLoading && overlayViewModel.activeLoadTrigger == .library,
                onSelect: { overlayViewModel.openLibraryPicker() }
            )
            .focused($focusedTarget, equals: .actionLibrary)

            ShuffleActionCard(
                title: Strings.quickShuffle.uppercased(),
                subtitle: Strings.random,
                systemIcon: "shuffle",
                isFocused: focusedTarget == .actionRandom,
                isLoading: overlayViewModel.isLoading && overlayViewModel.activeLoadTrigger == .random,
                isPrimary: true,
                onSelect: { overlayViewModel.reloadRandomPreview() }
            )
            .focused($focusedTarget, equals: .actionRandom)

            ShuffleActionCard(
                title: Strings.selectGenre.uppercased(),
                subtitle: Strings.genreSingular,
                systemIcon: "theatermasks.fill",
                isFocused: focusedTarget == .actionGenres,
                isLoading: overlayViewModel.isLoading && overlayViewModel.activeLoadTrigger == .genre,
                onSelect: { overlayViewModel.openGenrePicker() }
            )
            .focused($focusedTarget, equals: .actionGenres)
        }
    }

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(pickerTitle)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SpaceTokens.spaceXs) {
                    switch overlayViewModel.mode {
                    case .libraries:
                        if libraries.isEmpty {
                            Text(Strings.noItems)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.65))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, SpaceTokens.spaceMd)
                        } else {
                            ForEach(libraries, id: \.id) { library in
                                let target = ShuffleOverlayFocusTarget.pickerLibrary(library.id)
                                ShufflePickerRow(
                                    title: library.name,
                                    isFocused: focusedTarget == target,
                                    onSelect: { overlayViewModel.selectLibrary(library.id) }
                                )
                                .focused($focusedTarget, equals: target)
                            }
                        }
                    case .genres:
                        if overlayViewModel.isLoadingGenres {
                            HStack(spacing: SpaceTokens.spaceSm) {
                                ProgressView()
                                Text(Strings.loadingGenres)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, SpaceTokens.spaceMd)
                        } else if overlayViewModel.genres.isEmpty {
                            Text(Strings.noGenresFound)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(theme.colorScheme.onBackground.opacity(0.65))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, SpaceTokens.spaceMd)
                        } else {
                            ForEach(overlayViewModel.genres, id: \.self) { genre in
                                let target = ShuffleOverlayFocusTarget.pickerGenre(genre)
                                ShufflePickerRow(
                                    title: genre,
                                    isFocused: focusedTarget == target,
                                    onSelect: { overlayViewModel.selectGenre(genre) }
                                )
                                .focused($focusedTarget, equals: target)
                            }
                        }
                    case .main:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: 470)
        }
    }

    private var pickerTitle: String {
        switch overlayViewModel.mode {
        case .libraries:
            return Strings.selectLibrary
        case .genres:
            return Strings.selectGenre
        case .main:
            return Strings.shuffleBy
        }
    }

    private func isPosterFocusTarget(_ target: ShuffleOverlayFocusTarget?) -> Bool {
        guard let target else { return false }
        if case .poster = target {
            return true
        }
        return false
    }

    private func metadataEntries(for item: ServerItem) -> [ShuffleMetadataEntry] {
        var entries: [ShuffleMetadataEntry] = []

        if let year = year(for: item) {
            entries.append(.text(String(year)))
        }

        if let officialRating = officialRating(for: item) {
            entries.append(.badge(officialRating))
        }

        if let runtime = runtimeText(for: item) {
            entries.append(.text(runtime))
        }

        if let firstGenre = item.genres?.first, !firstGenre.isEmpty {
            entries.append(.text(firstGenre))
        }

        return entries
    }

    @ViewBuilder
    private func metadataRow(for item: ServerItem) -> some View {
        let entries = metadataEntries(for: item)

        if !entries.isEmpty {
            HStack(spacing: SpaceTokens.spaceSm) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if index > 0 {
                        metadataSeparator
                    }
                    switch entry {
                    case .text(let value):
                        metadataText(value)
                    case .badge(let value):
                        metadataBadge(value)
                    }
                }
            }
        }
    }

    private var metadataSeparator: some View {
        Text("\u{2022}")
            .font(.captionXs)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.captionXs)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.72))
    }

    private func metadataBadge(_ text: String) -> some View {
        Text(text)
            .font(.captionXs)
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.82))
            .padding(.horizontal, SpaceTokens.spaceXs)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.extraSmall)
                    .stroke(theme.colorScheme.onBackground.opacity(0.3), lineWidth: 1)
            )
    }

    private func descriptionText(for item: ServerItem) -> String {
        if let overview = item.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
            return overview
        }

        if let tagline = item.taglines?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return tagline
        }

        return " "
    }

    private func reloadRatingsForSelection() {
        guard let selectedItem = overlayViewModel.selectedItem else {
            ratingsTask?.cancel()
            displayRatings = []
            return
        }

        let selectedId = selectedItem.id
        displayRatings = ratingsFor(selectedItem)

        guard enableAdditionalRatings else {
            ratingsTask?.cancel()
            return
        }

        ratingsTask?.cancel()
        ratingsTask = Task {
            let fetchedRatings = await fetchRatings(selectedItem)
            guard !Task.isCancelled,
                  overlayViewModel.selectedItem?.id == selectedId
            else { return }

            displayRatings = fetchedRatings
        }
    }

    private func year(for item: ServerItem) -> Int? {
        if let productionYear = item.productionYear, productionYear > 0 {
            return productionYear
        }
        if let premiereDate = item.premiereDate {
            return Calendar.current.component(.year, from: premiereDate)
        }
        return nil
    }

    private func runtimeText(for item: ServerItem) -> String? {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return nil }
        return RuntimeFormatter.format(ticks: ticks)
    }

    private func officialRating(for item: ServerItem) -> String? {
        guard let value = item.officialRating?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func ratingsFor(_ item: ServerItem) -> [(String, Float)] {
        var ratings: [(String, Float)] = []

        if let community = item.communityRating, community > 0 {
            ratings.append(("stars", Float(community)))
        }

        if let critic = item.criticRating, critic > 0 {
            ratings.append(("tomatoes", Float(critic / 100.0)))
        }

        return ratings
    }
}

private struct ShufflePosterCard: View {
    let imageUrl: String?
    let isFocused: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    private var baseWidth: CGFloat { 138 }
    private var cardHeight: CGFloat { baseWidth / (2.0 / 3.0) }
    private var selectionScale: CGFloat { isSelected ? 1.75 : 0.94 }
    private var focusScale: CGFloat { isFocused ? 1.05 : 1.0 }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                if let imageUrl {
                    CachedImage(urlString: imageUrl, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle()
                        .fill(theme.colorScheme.surface.opacity(0.42))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: baseWidth, height: cardHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .stroke(isFocused ? theme.effectiveFocusColor : Color.white.opacity(isSelected ? 0.24 : 0.08), lineWidth: isFocused ? 2.5 : 1)
            )
            .shadow(color: isFocused ? theme.effectiveFocusColor.opacity(0.45) : .clear, radius: 14, x: 0, y: 0)
            .scaleEffect(selectionScale * focusScale)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
            .animation(.easeInOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(CleanButtonStyle())
    }
}

private enum ShuffleMetadataEntry: Hashable {
    case text(String)
    case badge(String)
}

private struct ShuffleActionCard: View {
    let title: String
    let subtitle: String
    let systemIcon: String
    let isFocused: Bool
    let isLoading: Bool
    var isPrimary: Bool = false
    let onSelect: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: systemIcon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(foregroundColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 24, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(foregroundColor.opacity(0.82))
                }

                Spacer(minLength: 0)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 106)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.large)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.large)
                    .stroke(borderColor, lineWidth: isFocused ? 2.5 : 1)
            )
            .shadow(color: isFocused ? theme.effectiveFocusColor.opacity(0.35) : .clear, radius: 14)
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
    }

    private var foregroundColor: Color {
        if isFocused {
            return .white
        }
        return theme.colorScheme.onBackground.opacity(isPrimary ? 0.95 : 0.85)
    }

    private var backgroundColor: Color {
        if isFocused {
            return theme.effectiveFocusColor.opacity(isPrimary ? 0.5 : 0.34)
        }
        return theme.colorScheme.surface.opacity(isPrimary ? 0.78 : 0.58)
    }

    private var borderColor: Color {
        if isFocused {
            return theme.effectiveFocusColor
        }
        return theme.colorScheme.onBackground.opacity(0.2)
    }
}

private struct ShufflePickerRow: View {
    let title: String
    let isFocused: Bool
    let onSelect: () -> Void

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.72))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .stroke(isFocused ? theme.effectiveFocusColor : Color.white.opacity(0.16), lineWidth: isFocused ? 2.2 : 1)
            )
            .animation(.easeOut(duration: 0.14), value: isFocused)
        }
        .buttonStyle(CleanButtonStyle())
    }
}