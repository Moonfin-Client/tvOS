import Foundation
import Combine

struct SuggestionRow: Identifiable {
    let id: String
    let sourceItem: ServerItem
    let items: [ServerItem]
    var title: String { "Because you watched \(sourceItem.name)" }
}

@MainActor
final class SuggestedViewModel: ObservableObject {
    @Published private(set) var rows: [SuggestionRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var focusedItem: ServerItem?

    let backgroundService = BackgroundService()

    private let container: AppContainer
    private let parentId: String
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainer, parentId: String) {
        self.container = container
        self.parentId = parentId

        backgroundService.configure(preferences: container.userPreferences)
        backgroundService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var client: MediaServerClient? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: server)
    }

    private var imageApi: ServerImageApi? { client?.imageApi }

    func initialize() {
        guard !isLoading else { return }
        Task { await loadSuggestions() }
    }

    func setFocusedItem(_ item: ServerItem) {
        focusedItem = item
        if let url = imageApi?.itemBackdropUrl(for: item) {
            backgroundService.setBackground(url: url)
        }
    }

    func posterUrl(for item: ServerItem) -> String? {
        imageApi?.itemPosterUrl(for: item)
    }

    func subtitle(for item: ServerItem) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let rating = item.communityRating {
            parts.append(String(format: "%.1f", rating))
        }
        return parts.joined(separator: " · ")
    }

    private func loadSuggestions() async {
        guard let client else { return }
        isLoading = true

        do {
            let recentRequest = GetItemsRequest(
                parentId: parentId,
                recursive: true,
                includeItemTypes: [.movie],
                sortBy: [.datePlayed],
                sortOrder: .descending,
                filters: [.isPlayed],
                limit: 8,
                imageTypeLimit: 1,
                enableTotalRecordCount: false
            )
            let recentResult = try await client.itemsApi.getItems(request: recentRequest)
            let recentMovies = recentResult.items

            var loadedRows: [SuggestionRow] = []
            await withTaskGroup(of: (Int, SuggestionRow?).self) { group in
                for (index, movie) in recentMovies.enumerated() {
                    group.addTask {
                        let similarResult = try? await client.itemsApi.getSimilarItems(
                            itemId: movie.id, limit: 7
                        )
                        guard let similar = similarResult?.items, !similar.isEmpty else { return (index, nil) }
                        return (index, SuggestionRow(id: movie.id, sourceItem: movie, items: similar))
                    }
                }
                var indexed: [(Int, SuggestionRow)] = []
                for await (i, row) in group {
                    if let row { indexed.append((i, row)) }
                }
                loadedRows = indexed.sorted { $0.0 < $1.0 }.map(\.1)
            }

            rows = loadedRows
        } catch {
            rows = []
        }

        isLoading = false
    }
}
