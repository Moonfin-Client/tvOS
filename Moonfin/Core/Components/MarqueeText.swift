import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let maxWidth: CGFloat
    var isFocused: Bool = false

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > maxWidth + 1 }
    private var scrollDistance: CGFloat { max(0, textWidth - maxWidth) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        textWidth = geo.size.width
                    }
                }
            )
            .offset(x: offset)
            .frame(width: maxWidth, alignment: .leading)
            .clipped()
            .onChange(of: isFocused) { focused in
                if focused && overflows {
                    let duration = max(1.0, Double(scrollDistance) / 30.0)
                    withAnimation(.linear(duration: duration).delay(0.5)) {
                        offset = -scrollDistance
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = 0
                    }
                }
            }
    }
}
