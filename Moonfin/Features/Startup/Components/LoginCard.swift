import SwiftUI

struct LoginCard<Content: View>: View {
    let maxWidth: CGFloat
    let content: () -> Content

    init(maxWidth: CGFloat = 800, @ViewBuilder content: @escaping () -> Content) {
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 44)
        .frame(maxWidth: maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: 0x111528, opacity: 0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
