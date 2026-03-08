import SwiftUI

struct ItemCardOverlays: View {
    let item: ServerItem

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        ZStack {
            if item.userData?.isFavorite ?? false {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0xFF4757))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
            }

            if let count = item.userData?.unplayedItemCount, count > 0 {
                Text("\(count)")
                    .font(.caption2xs)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accent)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            } else if item.userData?.played ?? false {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.colorGreen500)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }

            if let progress = item.userData?.playedPercentage, progress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .frame(height: 4)
                            Rectangle()
                                .fill(theme.accent)
                                .frame(width: geo.size.width * CGFloat(progress / 100.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
