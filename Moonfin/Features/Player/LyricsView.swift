import SwiftUI

struct LyricsView: View {
    let lyrics: [LyricLine]
    let currentTime: TimeInterval
    let duration: TimeInterval

    var body: some View {
        if isSynced {
            syncedLyrics
        } else {
            unsyncedLyrics
        }
    }

    private var isSynced: Bool {
        lyrics.first?.start != nil
    }

    private var activeLineIndex: Int {
        let currentTicks = Int64(currentTime * 10_000_000)
        return lyrics.lastIndex(where: { ($0.start ?? 0) <= currentTicks }) ?? 0
    }

    private var syncedLyrics: some View {
        GeometryReader { geo in
            let lineHeight: CGFloat = 44
            let spacing = SpaceTokens.spaceSm
            let stride = lineHeight + spacing
            let centerY = geo.size.height / 2
            let activeIndex = activeLineIndex
            let offset = centerY - (CGFloat(activeIndex) * stride) - lineHeight / 2

            VStack(spacing: SpaceTokens.spaceSm) {
                ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                    Text(line.text)
                        .font(.bodyLg)
                        .foregroundColor(.white.opacity(index == activeIndex ? 1.0 : 0.4))
                        .scaleEffect(index == activeIndex ? 1.05 : 1.0)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: lineHeight)
                }
            }
            .offset(y: offset)
            .animation(.easeInOut(duration: 0.4), value: activeIndex)
        }
        .clipped()
    }

    private var unsyncedLyrics: some View {
        GeometryReader { geo in
            let progress = duration > 0 ? currentTime / duration : 0
            let lineHeight: CGFloat = 36
            let spacing = SpaceTokens.spaceXs
            let stride = lineHeight + spacing
            let totalHeight = CGFloat(lyrics.count) * stride - spacing
            let visibleHeight = geo.size.height
            let scrollRange = max(totalHeight - visibleHeight, 0)
            let offset = -CGFloat(progress) * scrollRange

            VStack(spacing: SpaceTokens.spaceXs) {
                ForEach(Array(lyrics.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.bodyMd)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: lineHeight)
                }
            }
            .offset(y: offset)
            .animation(.easeInOut(duration: 0.8), value: offset)
        }
        .clipped()
    }
}
