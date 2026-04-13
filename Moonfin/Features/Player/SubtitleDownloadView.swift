import SwiftUI

struct SubtitleDownloadDialog: View {
    let defaultLanguage: String
    let onSearch: (String) async throws -> [RemoteSubtitleResult]
    let onDownload: (String) async throws -> Void
    let onDismiss: () -> Void
    let onDownloaded: () -> Void

    @State private var isLoading = true
    @State private var results: [RemoteSubtitleResult] = []
    @State private var error: String?
    @State private var isDownloading = false
    @State private var downloadedId: String?

    @EnvironmentObject private var theme: MoonfinTheme

    var body: some View {
        PlayerDialogShell(title: Strings.playerDownloadSubtitlesTitle, onDismiss: onDismiss) {
            if isLoading {
                HStack(spacing: SpaceTokens.spaceSm) {
                    ProgressView()
                    Text(Strings.playerSearching)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, SpaceTokens.spaceMd)
            } else if let error {
                Text(error)
                    .font(.bodySm)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, SpaceTokens.spaceMd)
                    .padding(.horizontal, SpaceTokens.spaceMd)
            } else if results.isEmpty {
                Text(Strings.playerNoSubtitlesFound(defaultLanguage.uppercased()))
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    .padding(.vertical, SpaceTokens.spaceMd)
            } else {
                ForEach(results) { result in
                    FocusableTrackSelectorRow(
                        label: result.displayName,
                        detail: result.subtitleDetail,
                        isSelected: downloadedId == result.id,
                        action: { download(result) }
                    )
                    .disabled(isDownloading)
                }
            }
        }
        .task { await search() }
    }

    private func search() async {
        isLoading = true
        error = nil
        do {
            results = try await onSearch(defaultLanguage)
            if results.isEmpty && defaultLanguage != "eng" {
                results = (try? await onSearch("eng")) ?? []
            }
        } catch {
            self.error = Strings.playerSubtitleSearchFailed
        }
        isLoading = false
    }

    private func download(_ result: RemoteSubtitleResult) {
        guard !isDownloading else { return }
        isDownloading = true
        Task {
            do {
                try await onDownload(result.id)
                downloadedId = result.id
                try? await Task.sleep(nanoseconds: 500_000_000)
                onDownloaded()
            } catch {
                self.error = Strings.playerSubtitleDownloadFailed
                isDownloading = false
            }
        }
    }
}
