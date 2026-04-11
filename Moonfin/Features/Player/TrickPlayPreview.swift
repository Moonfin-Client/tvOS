import SwiftUI

struct TrickPlayPreview: View {
    let thumbnail: UIImage?
    let position: CGFloat
    let barWidth: CGFloat
    let thumbSize: CGSize

    private let displayScale: CGFloat = 1.5

    var body: some View {
        if let thumbnail {
            let displayWidth = thumbSize.width * displayScale
            let displayHeight = thumbSize.height * displayScale
            let halfWidth = displayWidth / 2
            let maxX = max(halfWidth, barWidth - halfWidth)
            let xPos = min(max(position * barWidth, halfWidth), maxX)

            Image(uiImage: thumbnail)
                .resizable()
                .frame(width: displayWidth, height: displayHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                )
                .shadow(radius: 8)
                .position(x: xPos, y: displayHeight / 2)
        }
    }
}
