import SwiftUI

enum FocusBorderColor: String, CaseIterable, Identifiable {
    case white
    case neonPink
    case black
    case gray
    case darkBlue
    case purple
    case teal
    case navy
    case charcoal
    case brown
    case darkRed
    case darkGreen
    case slate
    case indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white:     return Color(hex: 0xFFFFFF)
        case .neonPink:  return Color(hex: 0xFF2E92)
        case .black:     return Color(hex: 0x000000)
        case .gray:      return Color(hex: 0x9E9E9E)
        case .darkBlue:  return Color(hex: 0x42A5F5)
        case .purple:    return Color(hex: 0xAB47BC)
        case .teal:      return Color(hex: 0x26A69A)
        case .navy:      return Color(hex: 0x3F51B5)
        case .charcoal:  return Color(hex: 0x78909C)
        case .brown:     return Color(hex: 0x8D6E63)
        case .darkRed:   return Color(hex: 0xEF5350)
        case .darkGreen: return Color(hex: 0x66BB6A)
        case .slate:     return Color(hex: 0x90A4AE)
        case .indigo:    return Color(hex: 0x7986CB)
        }
    }

    var displayName: String {
        switch self {
        case .white:     return "White"
        case .neonPink:  return "Neon Pink"
        case .black:     return "Black"
        case .gray:      return "Gray"
        case .darkBlue:  return "Dark Blue"
        case .purple:    return "Purple"
        case .teal:      return "Teal"
        case .navy:      return "Navy"
        case .charcoal:  return "Charcoal"
        case .brown:     return "Brown"
        case .darkRed:   return "Dark Red"
        case .darkGreen: return "Dark Green"
        case .slate:     return "Slate"
        case .indigo:    return "Indigo"
        }
    }
}
