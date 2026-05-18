import SwiftUI

enum SpaceTokens {
    static let space2xs: CGFloat = 2
    static let spaceXs: CGFloat = 4
    static let spaceSm: CGFloat = 8
    static let spaceMd: CGFloat = 16
    static let spaceLg: CGFloat = 24
    static let spaceXl: CGFloat = 32
    static let space2xl: CGFloat = 40
    static let space3xl: CGFloat = 48
}

enum RadiusTokens {
    static let none: CGFloat = 0
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 28
    static let defaultRadius: CGFloat = 128
    static let circle: CGFloat = 15984
}

enum TypographyTokens {
    static var fontFamily: String?

    static let fontSize2xs: CGFloat = 18
    static let fontSizeXs: CGFloat = 22
    static let fontSizeSm: CGFloat = 26
    static let fontSizeMd: CGFloat = 29
    static let fontSizeLg: CGFloat = 32
    static let fontSizeXl: CGFloat = 36
    static let fontSize2xl: CGFloat = 42
    static let fontSize3xl: CGFloat = 52
}

extension Font {
    static var caption2xs: Font { TypographyTokens.font(TypographyTokens.fontSize2xs) }
    static var captionXs: Font { TypographyTokens.font(TypographyTokens.fontSizeXs) }
    static var captionSm: Font { TypographyTokens.font(TypographyTokens.fontSizeSm) }
    static var bodySm: Font { TypographyTokens.font(TypographyTokens.fontSizeSm) }
    static var bodyMd: Font { TypographyTokens.font(TypographyTokens.fontSizeMd) }
    static var bodyLg: Font { TypographyTokens.font(TypographyTokens.fontSizeLg) }
    static var titleSm: Font { TypographyTokens.font(TypographyTokens.fontSizeMd, weight: .semibold) }
    static var titleMd: Font { TypographyTokens.font(TypographyTokens.fontSizeLg, weight: .semibold) }
    static var titleLg: Font { TypographyTokens.font(TypographyTokens.fontSizeXl, weight: .semibold) }
    static var titleXl: Font { TypographyTokens.font(TypographyTokens.fontSize2xl, weight: .semibold) }
    static var title2xl: Font { TypographyTokens.font(TypographyTokens.fontSize2xl, weight: .bold) }
    static var title3xl: Font { TypographyTokens.font(TypographyTokens.fontSize3xl, weight: .bold) }

    static func token(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        TypographyTokens.font(size, weight: weight)
    }
}

private extension TypographyTokens {
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontFamily {
            return Font.custom(resolvedFontFamily(fontFamily), size: size, relativeTo: .body).weight(weight)
        }
        return Font.system(size: size, weight: weight)
    }

    static func resolvedFontFamily(_ family: String) -> String {
        if family == "NeonPulseDisplay" {
            return "ScienceGothic-Regular"
        }
        return family
    }
}

extension View {
    func neonTextGlow(_ theme: MoonfinTheme, active: Bool = true) -> some View {
        guard active, !theme.activeSpec.textGlow.isEmpty else { return AnyView(self) }
        var view: AnyView = AnyView(self)
        for glow in theme.activeSpec.textGlow {
            view = AnyView(
                view.shadow(
                    color: glow.color.color,
                    radius: glow.blurRadius,
                    x: glow.offsetX,
                    y: glow.offsetY
                )
            )
        }
        return view
    }
}
