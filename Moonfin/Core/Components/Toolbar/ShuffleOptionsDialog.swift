import SwiftUI

struct ShuffleOptionsDialog: View {
    let libraries: [ServerItem]
    let onQuickShuffle: () -> Void
    let onLibraryShuffle: (String) -> Void
    let onGenreShuffle: (String) -> Void
    let onDismiss: () -> Void
    let fetchGenres: () async -> [String]

    @EnvironmentObject private var theme: MoonfinTheme
    @State private var mode: ShuffleMode = .main
    @State private var genres: [String] = []
    @State private var isLoadingGenres = false

    private enum ShuffleMode {
        case main, libraries, genres
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.top, SpaceTokens.spaceLg)
                .padding(.bottom, SpaceTokens.spaceMd)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: SpaceTokens.spaceXs) {
                    switch mode {
                    case .main:
                        mainContent
                    case .libraries:
                        libraryContent
                    case .genres:
                        genreContent
                    }
                }
                .padding(.horizontal, SpaceTokens.spaceSm)
            }
            .frame(maxHeight: 500)

            HStack {
                Spacer()
                FocusableDialogButton(title: Strings.cancel, action: onDismiss)
                Spacer()
            }
            .padding(.vertical, SpaceTokens.spaceMd)
        }
        .frame(width: 500)
        .background(theme.colorScheme.surface)
        .cornerRadius(RadiusTokens.large)
        .onExitCommand {
            switch mode {
            case .main: onDismiss()
            case .libraries, .genres: mode = .main
            }
        }
    }

    private var header: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if mode != .main {
                Button(action: { mode = .main }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                }
                .buttonStyle(CleanButtonStyle())
            }

            Text(headerTitle)
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)
        }
    }

    private var headerTitle: String {
        switch mode {
        case .main: return Strings.shuffleBy
        case .libraries: return Strings.selectLibrary
        case .genres: return Strings.selectGenre
        }
    }

    private var mainContent: some View {
        Group {
            FocusableTrackSelectorRow(
                label: Strings.quickShuffle,
                detail: nil,
                isSelected: false,
                action: { onQuickShuffle() }
            )
            FocusableTrackSelectorRow(
                label: Strings.librarySingular,
                detail: nil,
                isSelected: false,
                action: { mode = .libraries }
            )
            FocusableTrackSelectorRow(
                label: Strings.genreSingular,
                detail: nil,
                isSelected: false,
                action: {
                    mode = .genres
                    if genres.isEmpty {
                        loadGenres()
                    }
                }
            )
        }
    }

    private var libraryContent: some View {
        ForEach(libraries, id: \.id) { library in
            FocusableTrackSelectorRow(
                label: library.name,
                detail: nil,
                isSelected: false,
                action: { onLibraryShuffle(library.id) }
            )
        }
    }

    @ViewBuilder
    private var genreContent: some View {
        if isLoadingGenres {
            HStack(spacing: SpaceTokens.spaceSm) {
                ProgressView()
                Text(Strings.loadingGenres)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, SpaceTokens.spaceMd)
        } else if genres.isEmpty {
            Text(Strings.noGenresFound)
                .font(.bodySm)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .padding(.vertical, SpaceTokens.spaceMd)
        } else {
            ForEach(genres, id: \.self) { genre in
                FocusableTrackSelectorRow(
                    label: genre,
                    detail: nil,
                    isSelected: false,
                    action: { onGenreShuffle(genre) }
                )
            }
        }
    }

    private func loadGenres() {
        isLoadingGenres = true
        Task {
            genres = await fetchGenres()
            isLoadingGenres = false
        }
    }
}
