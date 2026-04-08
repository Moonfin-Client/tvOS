import SwiftUI

struct NextUpOverlay: View {
    let nextItem: ServerItem
    let countdown: Int
    let imageUrl: String?
    let onPlayNext: () -> Void
    let onClose: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    @FocusState private var focusedButton: NextUpButton?

    private enum NextUpButton: Hashable {
        case playNext
        case close
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: SpaceTokens.spaceLg) {
                Text("Up Next")
                    .font(.title2xl)
                    .foregroundColor(.white)

                episodeCard

                HStack(spacing: SpaceTokens.spaceLg) {
                    actionButton(
                        label: countdown > 0 ? "Play Next (\(countdown))" : "Play Next",
                        icon: "play.fill",
                        isAccent: true,
                        focused: $focusedButton,
                        tag: .playNext,
                        action: onPlayNext
                    )

                    actionButton(
                        label: "Close",
                        icon: "xmark",
                        isAccent: false,
                        focused: $focusedButton,
                        tag: .close,
                        action: onClose
                    )
                }
            }
            .padding(SpaceTokens.space3xl)
        }
        .transition(.opacity)
        .onAppear { focusedButton = .playNext }
    }

    private var episodeCard: some View {
        HStack(spacing: SpaceTokens.spaceLg) {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(16/9, contentMode: .fill)
                    default:
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 480, height: 270)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
            }

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                if let series = nextItem.seriesName {
                    Text(series)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.listCaption)
                }

                Text(episodeLabel)
                    .font(.title2xl)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let overview = nextItem.overview {
                    Text(overview)
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.listCaption)
                        .lineLimit(3)
                }

                if let ticks = nextItem.runTimeTicks {
                    let minutes = Int(ticks / 600_000_000)
                    Text("\(minutes) min")
                        .font(.bodySm)
                        .foregroundColor(theme.colorScheme.listCaption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SpaceTokens.spaceLg)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface.opacity(0.6))
        )
        .frame(maxWidth: 900)
    }

    private var episodeLabel: String {
        var label = ""
        if let s = nextItem.parentIndexNumber { label += "S\(s)" }
        if let e = nextItem.indexNumber { label += "E\(e) - " }
        label += nextItem.name
        return label
    }

    private func actionButton(
        label: String,
        icon: String,
        isAccent: Bool,
        focused: FocusState<NextUpButton?>.Binding,
        tag: NextUpButton,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focused.wrappedValue == tag
        return Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(.bodyLg)
            .padding(.horizontal, SpaceTokens.spaceXl)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isAccent ? theme.accent.opacity(isFocused ? 1.0 : 0.85) : theme.colorScheme.surface.opacity(isFocused ? 0.9 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.6 : 0), lineWidth: 2)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .foregroundColor(.white)
        }
        .buttonStyle(CleanButtonStyle())
        .focused(focused, equals: tag)
    }
}
