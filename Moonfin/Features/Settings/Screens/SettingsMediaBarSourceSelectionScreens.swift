import SwiftUI

private struct SourceChoice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct SettingsMediaBarLibrariesSelectionScreen: View {
    @EnvironmentObject var container: AppContainer

    @State private var choices: [SourceChoice] = []
    @State private var selectedIds = Set<String>()
    @State private var isLoading = true

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Source Libraries") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else if choices.isEmpty {
                Text("No libraries available")
                    .font(.bodyMd)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceMd)
            } else {
                ForEach(choices) { choice in
                    SourceMultiSelectRow(
                        label: choice.name,
                        selected: selectedIds.contains(choice.id)
                    ) {
                        toggle(choice.id)
                    }
                }
            }
        }
        .task { await loadChoices() }
    }

    @MainActor
    private func loadChoices() async {
        isLoading = true
        selectedIds = Set(prefs[UserPreferences.mediaBarLibraryIds])

        let views = await container.userViewsService.awaitLoaded()
        choices = views.map { SourceChoice(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        isLoading = false
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        prefs[UserPreferences.mediaBarLibraryIds] = Array(selectedIds).sorted()
    }
}

struct SettingsMediaBarCollectionsSelectionScreen: View {
    @EnvironmentObject var container: AppContainer

    @State private var choices: [SourceChoice] = []
    @State private var selectedIds = Set<String>()
    @State private var isLoading = true

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Source Collections") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else if choices.isEmpty {
                Text("No collections available")
                    .font(.bodyMd)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceMd)
            } else {
                ForEach(choices) { choice in
                    SourceMultiSelectRow(
                        label: choice.name,
                        selected: selectedIds.contains(choice.id)
                    ) {
                        toggle(choice.id)
                    }
                }
            }
        }
        .task { await loadChoices() }
    }

    @MainActor
    private func loadChoices() async {
        isLoading = true
        selectedIds = Set(prefs[UserPreferences.mediaBarCollectionIds])

        guard let session = container.sessionRepository.currentSession.value,
              let server = container.serverRepository.currentServer.value else {
            choices = []
            isLoading = false
            return
        }

        do {
            let client = container.serverClientFactory.client(for: server)
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                userId: session.userId.uuidString,
                recursive: true,
                includeItemTypes: [.boxSet],
                sortBy: [.sortName],
                sortOrder: .ascending,
                limit: 500
            ))

            choices = result.items
                .map { SourceChoice(id: $0.id, name: $0.name) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            choices = []
        }

        isLoading = false
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        prefs[UserPreferences.mediaBarCollectionIds] = Array(selectedIds).sorted()
    }
}

struct SettingsMediaBarExcludedGenresSelectionScreen: View {
    @EnvironmentObject var container: AppContainer

    @State private var choices: [SourceChoice] = []
    @State private var selectedNames = Set<String>()
    @State private var isLoading = true

    private var prefs: UserPreferences { container.userPreferences }

    var body: some View {
        SettingsScreenLayout(title: "Excluded Genres") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceLg)
            } else if choices.isEmpty {
                Text("No genres available")
                    .font(.bodyMd)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceMd)
            } else {
                ForEach(choices) { choice in
                    SourceMultiSelectRow(
                        label: choice.name,
                        selected: selectedNames.contains(choice.name)
                    ) {
                        toggle(choice.name)
                    }
                }
            }
        }
        .task { await loadChoices() }
    }

    @MainActor
    private func loadChoices() async {
        isLoading = true
        selectedNames = Set(prefs[UserPreferences.mediaBarExcludedGenres])

        guard let session = container.sessionRepository.currentSession.value,
              let server = container.serverRepository.currentServer.value else {
            choices = []
            isLoading = false
            return
        }

        do {
            let client = container.serverClientFactory.client(for: server)
            let result = try await client.itemsApi.getItems(request: GetItemsRequest(
                userId: session.userId.uuidString,
                recursive: true,
                includeItemTypes: [.movie, .series],
                fields: [.genres],
                limit: 500
            ))

            let genres = Set(result.items.flatMap { $0.genres ?? [] })
            choices = genres
                .map { SourceChoice(id: $0.lowercased(), name: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            choices = []
        }

        isLoading = false
    }

    private func toggle(_ name: String) {
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
        prefs[UserPreferences.mediaBarExcludedGenres] = Array(selectedNames).sorted()
    }
}

private struct SourceMultiSelectRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceMd) {
                Text(label)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? theme.colorScheme.listHeadlineFocused : theme.colorScheme.listHeadline)

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.bodyMd)
                    .foregroundColor(selected
                        ? (isFocused ? theme.colorScheme.listHeadlineFocused : theme.accent)
                        : (isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption))
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small, style: .continuous)
                    .fill(isFocused ? theme.colorScheme.listButtonFocused : theme.colorScheme.listButton)
            )
        }
        .buttonStyle(CleanButtonStyle())
    }
}
