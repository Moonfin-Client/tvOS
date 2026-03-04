import SwiftUI

struct UserCard: View {
    let name: String
    let imageUrl: String?
    var size: CGFloat = 130

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            ZStack {
                Circle()
                    .fill(theme.colorScheme.surface)

                if let imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            personPlaceholder
                        }
                    }
                    .clipShape(Circle())
                } else {
                    personPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isFocused ? theme.focusBorder.color : theme.colorScheme.surface.opacity(0.3), lineWidth: isFocused ? 3 : 2)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)

            Text(name)
                .font(.bodySm)
                .foregroundColor(isFocused ? theme.colorScheme.onBackground : theme.colorScheme.onBackground.opacity(0.8))
                .lineLimit(1)
                .frame(width: size)
        }
    }

    private var personPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.3))
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
    }
}
