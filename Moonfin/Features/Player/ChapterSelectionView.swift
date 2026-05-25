import SwiftUI

struct ChapterSelectionView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedIndex: Int?

    private let cardWidth: CGFloat = 240
    private let cardHeight: CGFloat = 135

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                Text(Strings.chapters)
                    .font(.title2xl)
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonPrimaryColor : .white)
                    .padding(.horizontal, 80)
                    .neonTextGlow(theme, active: theme.isNeonPulseTheme)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SpaceTokens.spaceMd) {
                            ForEach(Array(viewModel.chapters.enumerated()), id: \.offset) { index, chapter in
                                chapterCard(chapter: chapter, index: index)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.vertical, SpaceTokens.spaceSm)
                    }
                    .onAppear {
                        let currentIdx = viewModel.currentChapterIndex()
                        focusedIndex = currentIdx
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentIdx, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: focusedIndex) { newIndex in
                        guard let newIndex else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            .padding(.vertical, 40)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.bottom, -60)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onExitCommand {
            viewModel.hideChapterSelection()
        }
    }

    private func chapterCard(chapter: ServerChapter, index: Int) -> some View {
        let isCurrent = index == viewModel.currentChapterIndex()
        let isFocused = focusedIndex == index

        return Button {
            viewModel.seekToChapter(chapter)
        } label: {
            VStack(alignment: .leading, spacing: SpaceTokens.spaceXs) {
                ZStack {
                    if let urlStr = viewModel.chapterImageUrl(for: chapter),
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color(white: 0.15)
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                    } else {
                        Color(white: 0.15)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.title2xl)
                                    .foregroundColor(.white.opacity(0.3))
                            )
                    }

                    if isCurrent {
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .stroke(theme.accent, lineWidth: 2)
                    }

                    if isFocused {
                        RoundedRectangle(cornerRadius: RadiusTokens.small + 2)
                            .stroke(Color.white.opacity(0.95), lineWidth: 4)
                            .padding(-2)
                    }
                }
                .cornerRadius(RadiusTokens.small)
                .clipped()

                Text(chapter.name ?? Strings.playerChapter(index + 1))
                    .font(.bodySm)
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonPrimaryColor : .white)
                    .lineLimit(1)
                    .frame(width: cardWidth, alignment: .leading)
                    .neonTextGlow(theme, active: theme.isNeonPulseTheme)

                Text(formatChapterTime(ticks: chapter.startPositionTicks))
                    .font(.caption2xs)
                    .foregroundColor(theme.isNeonPulseTheme ? theme.neonSecondaryColor : .white.opacity(0.6))
            }
        }
        .buttonStyle(PopupCardButtonStyle())
        .focused($focusedIndex, equals: index)
    }

    private func formatChapterTime(ticks: Int64) -> String {
        let totalSeconds = Int(ticks / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

struct PopupCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: isFocused ? .white.opacity(0.3) : .clear, radius: 8)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
