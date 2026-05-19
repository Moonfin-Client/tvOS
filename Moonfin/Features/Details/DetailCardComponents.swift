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
    var onFocused: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            Button(action: onSelect) {
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
                        .stroke(isFocused ? theme.effectiveFocusColor : .clear, lineWidth: isFocused ? 3 : 0)
                )
            }
            .buttonStyle(CleanButtonStyle())
            .focused($isFocused)
            .onChange(of: isFocused) { focused in
                if focused {
                    onFocused?()
                }
            }
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: item.name,
                    font: .bodySm,
                    fontSize: TypographyTokens.fontSizeSm,
                    color: theme.colorScheme.listHeadline,
                    maxWidth: cardWidth,
                    isFocused: isFocused
                )
                .neonTextGlow(theme, active: theme.isNeonPulseTheme)

                if !item.cardSubtitle.isEmpty {
                    MarqueeText(
                        text: item.cardSubtitle,
                        font: .captionXs,
                        fontSize: TypographyTokens.fontSizeXs,
                        color: theme.colorScheme.listCaption,
                        maxWidth: cardWidth,
                        isFocused: isFocused
                    )
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
    }
}

// MARK: - Cast Card

struct FocusableCastCard: View {
    let person: ServerPerson
    let imageUrl: String?
    let onSelect: () -> Void
    var onFocused: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: SpaceTokens.spaceXs) {
                CachedImage(urlString: imageUrl)
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())
                    .background(
                        Circle().fill(theme.colorScheme.surface)
                    )
                    .overlay(
                        Circle()
                            .stroke(isFocused ? theme.effectiveFocusColor : .clear, lineWidth: isFocused ? 3 : 0)
                    )

                Text(person.name)
                    .font(.bodySm)
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonPrimaryColor : theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .neonTextGlow(theme, active: theme.isNeonPulseTheme)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2xs)
                        .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : theme.colorScheme.listCaption)
                        .lineLimit(1)
                }
            }
            .frame(width: 200)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused {
                onFocused?()
            }
        }
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Episode Card

struct FocusableEpisodeCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void
    var onFocused: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private let thumbWidth: CGFloat = 400
    private let thumbHeight: CGFloat = 225

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: SpaceTokens.spaceMd) {
                thumbnailView
                episodeInfoView
            }
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused {
                onFocused?()
            }
        }
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
                .stroke(isFocused ? theme.effectiveFocusColor : .clear, lineWidth: isFocused ? 3 : 0)
        )
    }

    private var episodeInfoView: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
            if let num = item.indexNumber {
                Text(Strings.episodeLabel(num))
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
            }

            Text(item.name)
                .font(.bodyLg)
                .fontWeight(.semibold)
                .foregroundColor(theme.isNeonPulseTheme ? theme.neonPrimaryColor : theme.colorScheme.onBackground)
                .lineLimit(1)
                .neonTextGlow(theme, active: theme.isNeonPulseTheme)

            if let ticks = item.runTimeTicks, ticks > 0 {
                Text(RuntimeFormatter.format(ticks: ticks))
                    .font(.captionXs)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
            }

            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.bodySm)
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : theme.colorScheme.onBackground.opacity(0.6))
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
    let rowIndex: Int
    let focusBinding: FocusState<String?>.Binding
    let focusId: String
    let onSelect: () -> Void
    var onPlayNext: (() -> Void)? = nil
    var onAddToQueue: (() -> Void)? = nil
    var onAddToPlaylist: (() -> Void)? = nil
    var onRemoveFromPlaylist: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var onGoToAlbum: (() -> Void)? = nil
    var onGoToArtist: (() -> Void)? = nil
    var onMoveLeft: (() -> Void)? = nil
    var onMoveRight: (() -> Void)? = nil
    var onFocused: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            if let num = track.indexNumber {
                Text("\(num)")
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? .black.opacity(0.75) : theme.colorScheme.listCaption)
                    .frame(width: 40, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.bodyMd)
                    .foregroundColor(isFocused ? .black : theme.colorScheme.onBackground)
                    .lineLimit(1)

                let artistText = (track.artists?.joined(separator: ", ") ?? track.albumArtist ?? "")
                if !artistText.isEmpty {
                    Text(artistText)
                        .font(.bodySm)
                        .foregroundColor(isFocused ? .black.opacity(0.7) : theme.colorScheme.listCaption)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let ticks = track.runTimeTicks {
                Text(RuntimeFormatter.format(ticks: ticks))
                    .font(.bodySm)
                    .foregroundColor(isFocused ? .black.opacity(0.65) : theme.colorScheme.listCaption)
            }

            Image(systemName: "chevron.right.2")
                .font(.bodySm)
                .foregroundColor(isFocused ? .black.opacity(0.75) : theme.colorScheme.listCaption.opacity(0.75))
        }
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(
                    isFocused
                        ? Color.white
                        : (rowIndex.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.04))
                )
        )
        .contentShape(Rectangle())
        .focusable(true)
        .onTapGesture(perform: onSelect)
        .focused(focusBinding, equals: focusId)
        .onChange(of: focusBinding.wrappedValue) { focused in
            if focused == focusId {
                onFocused?()
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                onMoveLeft?()
            case .right:
                onMoveRight?()
            default:
                break
            }
        }
        .contextMenu {
            Button(Strings.play, action: onSelect)

            if let onPlayNext {
                Button(Strings.playerPlayNext, action: onPlayNext)
            }

            if let onAddToQueue {
                Button(Strings.addToQueue, action: onAddToQueue)
            }

            if let onAddToPlaylist {
                Button(Strings.addToPlaylist, action: onAddToPlaylist)
            }

            if let onRemoveFromPlaylist {
                Button(Strings.deleteFromPlaylist, role: .destructive, action: onRemoveFromPlaylist)
            }

            if let onMoveUp {
                Button(Strings.moveUp, action: onMoveUp)
            }

            if let onMoveDown {
                Button(Strings.moveDown, action: onMoveDown)
            }

            if let onToggleFavorite {
                Button((track.userData?.isFavorite ?? false) ? Strings.removeFromFavorites : Strings.addToFavorites, action: onToggleFavorite)
            }

            if let onGoToAlbum {
                Button(Strings.goToAlbum, action: onGoToAlbum)
            }

            if let onGoToArtist {
                Button(Strings.goToArtist, action: onGoToArtist)
            }
        }
    }

    private var isFocused: Bool {
        focusBinding.wrappedValue == focusId
    }
}

// MARK: - Season Card

struct FocusableSeasonCard: View {
    let item: ServerItem
    let imageUrl: String?
    let onSelect: () -> Void
    var onFocused: (() -> Void)? = nil

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth / (2.0 / 3.0) }

    var body: some View {
        FocusableItemCard(
            item: item,
            imageUrl: imageUrl,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            onSelect: onSelect,
            onFocused: onFocused
        )
    }
}

// MARK: - Focus-First Scroll Row

struct FocusFirstRow<Content: View>: View {
    let firstItemId: String?
    let restoredItemId: String?
    var focusTrigger: Int = 0
    var applyFocusSection: Bool = true
    let content: (FocusState<String?>.Binding) -> Content

    @FocusState private var focusedId: String?

    init(firstItemId: String?, restoredItemId: String? = nil, focusTrigger: Int = 0, applyFocusSection: Bool = true, @ViewBuilder content: @escaping (FocusState<String?>.Binding) -> Content) {
        self.firstItemId = firstItemId
        self.restoredItemId = restoredItemId
        self.focusTrigger = focusTrigger
        self.applyFocusSection = applyFocusSection
        self.content = content
    }

    var body: some View {
        scrollContent
            .defaultFocus($focusedId, restoredItemId ?? firstItemId)
            .onChange(of: focusTrigger) { newValue in
                guard newValue > 0, let target = restoredItemId ?? firstItemId else { return }
                focusedId = target
            }
    }

    @ViewBuilder
    private var scrollContent: some View {
        let scroll = ScrollView(.horizontal, showsIndicators: false) {
            content($focusedId)
        }
        if applyFocusSection {
            scroll.focusSection()
        } else {
            scroll
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
                    Text(Strings.pressToExpand)
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
