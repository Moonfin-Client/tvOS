import SwiftUI

// MARK: - Progress Bar

struct ProgressBarOverlay: View {
    let progress: Double

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack {
            Spacer()
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: 4)
                GeometryReader { geo in
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: geo.size.width * CGFloat(progress / 100.0), height: 4)
                }
                .frame(height: 4)
            }
        }
    }
}

// MARK: - Item Card

struct FocusableItemCard: View {
    let item: ServerItem
    let imageUrl: String?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                ZStack {
                    CachedImage(urlString: imageUrl)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .background(theme.colorScheme.surface)

                    ItemCardOverlays(item: item)
                }
                .cornerRadius(RadiusTokens.small)
                .overlay(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                )

                Text(item.name)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Cast Card

struct FocusableCastCard: View {
    let person: ServerPerson
    let imageUrl: String?
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SpaceTokens.spaceXs) {
                CachedImage(urlString: imageUrl)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .background(
                        Circle().fill(theme.colorScheme.surface)
                    )
                    .overlay(
                        Circle()
                            .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
                    )

                Text(person.name)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2xs)
                        .foregroundColor(theme.colorScheme.listCaption)
                        .lineLimit(1)
                }
            }
            .frame(width: 130)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Episode Card

struct FocusableEpisodeCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let thumbWidth: CGFloat = 280
    private let thumbHeight: CGFloat = 158

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: SpaceTokens.spaceMd) {
                thumbnailView
                episodeInfoView
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var thumbnailView: some View {
        ZStack {
            CachedImage(urlString: imageUrl, contentMode: .fill)

            if let progress = item.userData?.playedPercentage, progress > 0,
               !(item.userData?.played ?? false) {
                ProgressBarOverlay(progress: progress)
            }

            if item.userData?.played ?? false {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.colorGreen500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .clipped()
        .cornerRadius(RadiusTokens.small)
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .stroke(isFocused ? theme.focusBorder.color : .clear, lineWidth: isFocused ? 3 : 0)
        )
    }

    private var episodeInfoView: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            if let num = item.indexNumber {
                Text("Episode \(num)")
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            }

            Text(item.name)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.colorScheme.onBackground)
                .lineLimit(1)

            if let ticks = item.runTimeTicks, ticks > 0 {
                Text(RuntimeFormatter.format(ticks: ticks))
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
            }

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SpaceTokens.spaceXs)
    }
}

// MARK: - Track Row

struct FocusableTrackRow: View {
    let track: ServerItem
    let onSelect: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if let num = track.indexNumber {
                    Text("\(num)")
                        .font(.bodyMd)
                        .foregroundColor(isFocused ? .white : theme.colorScheme.listCaption)
                        .frame(width: 40, alignment: .trailing)
                }
                Text(track.name)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground)
                    .lineLimit(1)
                Spacer()
                if let ticks = track.runTimeTicks {
                    Text(RuntimeFormatter.format(ticks: ticks))
                        .font(.bodySm)
                        .foregroundColor(isFocused ? .white.opacity(0.7) : theme.colorScheme.listCaption)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? theme.accent : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}

// MARK: - Season Card

struct FocusableSeasonCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth / (2.0 / 3.0) }

    var body: some View {
        FocusableItemCard(
            item: item,
            imageUrl: imageUrl,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            onSelect: onSelect
        )
    }
}

// MARK: - Focus-First Scroll Row

struct FocusFirstRow<Content: View>: View {
    let firstItemId: String?
    let content: (FocusState<String?>.Binding) -> Content

    @FocusState private var focusedId: String?
    @State private var hasEnteredFocus = false

    init(firstItemId: String?, @ViewBuilder content: @escaping (FocusState<String?>.Binding) -> Content) {
        self.firstItemId = firstItemId
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content($focusedId)
        }
        .onChange(of: focusedId) { newValue in
            if newValue != nil && !hasEnteredFocus {
                hasEnteredFocus = true
                if let firstId = firstItemId, newValue != firstId {
                    DispatchQueue.main.async {
                        focusedId = firstId
                    }
                }
            } else if newValue == nil {
                hasEnteredFocus = false
            }
        }
    }
}

// MARK: - Expandable Bio

struct ExpandableBioText: View {
    let text: String
    @Binding var isExpanded: Bool

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                Text(text)
                    .font(.bodyLg)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(isExpanded ? nil : 6)
                    .padding(.horizontal, SpaceTokens.spaceSm)

                if !isExpanded {
                    Text("Press to expand")
                        .font(.captionXs)
                        .foregroundColor(isFocused ? .white.opacity(0.7) : theme.colorScheme.onBackground.opacity(0.4))
                        .padding(.horizontal, SpaceTokens.spaceSm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SpaceTokens.spaceSm)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
    }
}
