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
    static let fontSize2xs: CGFloat = 10
    static let fontSizeXs: CGFloat = 12
    static let fontSizeSm: CGFloat = 14
    static let fontSizeMd: CGFloat = 16
    static let fontSizeLg: CGFloat = 18
    static let fontSizeXl: CGFloat = 20
    static let fontSize2xl: CGFloat = 24
    static let fontSize3xl: CGFloat = 32
}

extension Font {
    static let caption2xs = Font.system(size: TypographyTokens.fontSize2xs)
    static let captionXs = Font.system(size: TypographyTokens.fontSizeXs)
    static let captionSm = Font.system(size: 13)
    static let bodySm = Font.system(size: TypographyTokens.fontSizeSm)
    static let bodyMd = Font.system(size: TypographyTokens.fontSizeMd)
    static let bodyLg = Font.system(size: TypographyTokens.fontSizeLg)
    static let titleSm = Font.system(size: TypographyTokens.fontSizeMd, weight: .semibold)
    static let titleMd = Font.system(size: TypographyTokens.fontSizeLg, weight: .semibold)
    static let titleLg = Font.system(size: 22, weight: .semibold)
    static let titleXl = Font.system(size: TypographyTokens.fontSizeXl, weight: .semibold)
    static let title2xl = Font.system(size: TypographyTokens.fontSize2xl, weight: .bold)
    static let title3xl = Font.system(size: TypographyTokens.fontSize3xl, weight: .bold)

    static func token(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
