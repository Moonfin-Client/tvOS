import SwiftUI

struct NextUpOverlay: View {
    let nextItem: ServerItem
    let countdown: Int
    let imageUrl: String?
    let onPlayNext: () -> Void
    let onClose: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: SpaceTokens.spaceLg) {
                Text("Up Next")
                    .font(.title2xl)
                    .foregroundColor(.white)

                episodeCard

                HStack(spacing: SpaceTokens.spaceMd) {
                    actionButton(
                        label: countdown > 0 ? "Play Next (\(countdown))" : "Play Next",
                        icon: "play.fill",
                        isAccent: true,
                        action: onPlayNext
                    )

                    actionButton(
                        label: "Close",
                        icon: "xmark",
                        isAccent: false,
                        action: onClose
                    )
                }
            }
            .padding(SpaceTokens.space3xl)
        }
        .transition(.opacity)
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
                .frame(width: 320, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: RadiusTokens.medium))
            }

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                if let series = nextItem.seriesName {
                    Text(series)
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.listCaption)
                }

                Text(episodeLabel)
                    .font(.titleXl)
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
        .frame(maxWidth: 700)
    }

    private var episodeLabel: String {
        var label = ""
        if let s = nextItem.parentIndexNumber { label += "S\(s)" }
        if let e = nextItem.indexNumber { label += "E\(e) — " }
        label += nextItem.name
        return label
    }

    private func actionButton(label: String, icon: String, isAccent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .font(.bodyMd)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.medium)
                    .fill(isAccent ? theme.accent.opacity(0.85) : theme.colorScheme.surface.opacity(0.7))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}
