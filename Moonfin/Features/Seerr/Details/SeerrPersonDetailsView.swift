import SwiftUI

struct SeerrPersonDetailsView: View {
    @StateObject private var viewModel: SeerrPersonDetailsViewModel
    @EnvironmentObject var theme: MoonfinTheme
    @EnvironmentObject var router: NavigationRouter

    init(personId: Int, seerrRepository: SeerrRepositoryProtocol) {
        _viewModel = StateObject(wrappedValue: SeerrPersonDetailsViewModel(
            personId: personId, seerrRepository: seerrRepository
        ))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            switch viewModel.state {
            case .loading:
                ProgressView().tint(theme.colorScheme.onBackground)
            case .error(let message):
                errorView(message)
            case .loaded:
                contentView
            }
        }
        .onAppear { viewModel.loadDetails() }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            Text(message)
                .font(.titleMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(50)
    }

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.top, 60)

                if viewModel.biography != nil {
                    biographySection
                        .padding(.top, SpaceTokens.spaceLg)
                }

                if !viewModel.appearances.isEmpty {
                    appearancesSection
                        .padding(.top, SpaceTokens.spaceLg)
                }
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 80)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: SpaceTokens.spaceLg) {
            profilePhoto
            personInfo
        }
    }

    private var profilePhoto: some View {
        Group {
            if let urlString = viewModel.profileUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        photoPlaceholder
                    case .empty:
                        photoPlaceholder.shimmering()
                    @unknown default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(Circle())
    }

    private var photoPlaceholder: some View {
        ZStack {
            Circle()
                .fill(theme.colorScheme.surface.opacity(0.3))
            Image(systemName: "person.fill")
                .font(.system(size: 48))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
        }
    }

    private var personInfo: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(viewModel.name)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(theme.colorScheme.onBackground)

            if let knownFor = viewModel.knownFor {
                Text(knownFor)
                    .font(.titleSm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }

            if let birthInfo = viewModel.birthInfo {
                Text(birthInfo)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }

            if let deathInfo = viewModel.deathInfo {
                Text(deathInfo)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
            }
        }
    }

    private var biographySection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(Strings.seerrBiography)
                .font(.titleMd).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)

            if let bio = viewModel.biography {
                Text(bio)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.85))
                    .lineSpacing(4)
                    .lineLimit(viewModel.isBioExpanded ? nil : 4)

                Button(action: { viewModel.isBioExpanded.toggle() }) {
                    Text(viewModel.isBioExpanded ? Strings.seerrShowLess : Strings.seerrShowMore)
                        .font(.bodySm).fontWeight(.semibold)
                        .foregroundColor(theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appearancesSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text(Strings.seerrAppearances)
                .font(.titleMd).fontWeight(.bold)
                .foregroundColor(theme.colorScheme.onBackground)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: SpaceTokens.spaceMd) {
                    ForEach(viewModel.appearances) { item in
                        SeerrItemCard(
                            item: item,
                            posterUrl: item.posterPath.map { SeerrImageUrl.poster($0) },
                            onSelect: {
                                if let json = viewModel.itemJson(item) {
                                    router.navigate(to: .seerrMediaDetails(itemJson: json))
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
        }
    }
}
