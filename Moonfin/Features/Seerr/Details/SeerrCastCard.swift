import SwiftUI

struct SeerrCastCard: View {
    let member: SeerrCastMemberDto
    var onSelect: (() -> Void)?

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let photoSize: CGFloat = 100

    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(spacing: SpaceTokens.spaceSm) {
                profileImage
                    .frame(width: photoSize, height: photoSize)
                    .clipShape(Circle())

                VStack(spacing: 2) {
                    Text(member.name)
                        .font(.captionXs)
                        .foregroundColor(theme.colorScheme.onBackground)
                        .lineLimit(1)
                    if let character = member.character, !character.isEmpty {
                        Text(character)
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .frame(width: photoSize)
            }
        }
        .buttonStyle(ItemCardButtonStyle(
            isFocused: isFocused,
            cornerRadius: photoSize / 2,
            focusBorderColor: theme.focusBorder.color
        ))
        .focused($isFocused)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let path = member.profilePath, let url = URL(string: SeerrImageUrl.profile(path)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    profilePlaceholder
                case .empty:
                    profilePlaceholder.shimmering()
                @unknown default:
                    profilePlaceholder
                }
            }
            .frame(width: photoSize, height: photoSize)
        } else {
            profilePlaceholder
        }
    }

    private var profilePlaceholder: some View {
        ZStack {
            Circle()
                .fill(theme.colorScheme.surface.opacity(0.3))
            Image(systemName: "person.fill")
                .font(.system(size: 32))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
        }
        .frame(width: photoSize, height: photoSize)
    }
}
