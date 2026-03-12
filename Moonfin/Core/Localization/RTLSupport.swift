import SwiftUI

struct RTLAwareHStack<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content
    @EnvironmentObject var localization: LocalizationManager

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(spacing: spacing, content: content)
            .environment(\.layoutDirection, localization.layoutDirection)
    }
}

struct RTLModifier: ViewModifier {
    @EnvironmentObject var localization: LocalizationManager

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, localization.layoutDirection)
    }
}

extension View {
    func rtlAware() -> some View {
        modifier(RTLModifier())
    }

    func flippedForRTL(_ isRTL: Bool) -> some View {
        scaleEffect(x: isRTL ? -1 : 1, y: 1)
    }
}

struct RTLAwareAlignment {
    let layoutDirection: LayoutDirection

    var leading: HorizontalAlignment {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }

    var trailing: HorizontalAlignment {
        layoutDirection == .rightToLeft ? .leading : .trailing
    }

    var leadingEdge: Edge {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }

    var trailingEdge: Edge {
        layoutDirection == .rightToLeft ? .leading : .trailing
    }

    var leadingTextAlignment: TextAlignment {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }
}

extension LayoutDirection {
    var alignment: RTLAwareAlignment {
        RTLAwareAlignment(layoutDirection: self)
    }
}

extension EnvironmentValues {
    var rtlAlignment: RTLAwareAlignment {
        layoutDirection.alignment
    }
}
