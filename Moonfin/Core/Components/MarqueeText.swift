import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let maxWidth: CGFloat
    var isFocused: Bool = false

    private let textWidth: CGFloat
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > maxWidth + 1 }
    private var scrollDistance: CGFloat { max(0, textWidth - maxWidth) }

    init(text: String, font: Font, fontSize: CGFloat, color: Color, maxWidth: CGFloat, isFocused: Bool = false) {
        self.text = text
        self.font = font
        self.color = color
        self.maxWidth = maxWidth
        self.isFocused = isFocused
        self.textWidth = Self.measureWidth(text, fontSize: fontSize)
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

    private static func measureWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let uiFont = UIFont.systemFont(ofSize: fontSize)
        let size = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: uiFont],
            context: nil
        ).size
        return ceil(size.width)
    }
}
