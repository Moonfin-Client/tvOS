import SwiftUI

struct MediaBarSlideItem: Identifiable, Equatable {
    let id: String
    let serverId: String?
    let title: String
    let overview: String?
    let backdropUrl: String?
    let logoUrl: String?
    let year: Int?
    let genres: [String]
    let runtime: String?
    let officialRating: String?
    let communityRating: Double?
    let criticRating: Double?
    let itemType: ItemType
    let providerIds: [String: String]?

    var tmdbId: String? { providerIds?["Tmdb"] }

    static func == (lhs: MediaBarSlideItem, rhs: MediaBarSlideItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum MediaBarState: Equatable {
    case loading
    case ready([MediaBarSlideItem])
    case error(String)
    case disabled

    static func == (lhs: MediaBarState, rhs: MediaBarState) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading), (.disabled, .disabled):
            return true
        case (.ready(let a), .ready(let b)):
            return a.map(\.id) == b.map(\.id)
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum MediaBarOverlayColor: String, StringRepresentableEnum, CaseIterable {
    case gray
    case black
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

    var color: Color {
        switch self {
        case .gray:      return Color(hex: 0x808080)
        case .black:     return Color(hex: 0x000000)
        case .darkBlue:  return Color(hex: 0x1A2332)
        case .purple:    return Color(hex: 0x4A148C)
        case .teal:      return Color(hex: 0x00695C)
        case .navy:      return Color(hex: 0x0D1B2A)
        case .charcoal:  return Color(hex: 0x36454F)
        case .brown:     return Color(hex: 0x3E2723)
        case .darkRed:   return Color(hex: 0x8B0000)
        case .darkGreen: return Color(hex: 0x0B4F0F)
        case .slate:     return Color(hex: 0x475569)
        case .indigo:    return Color(hex: 0x1E3A8A)
        }
    }

    var displayName: String {
        switch self {
        case .gray:      return "Gray"
        case .black:     return "Black"
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

enum MediaBarContentType: String, StringRepresentableEnum, CaseIterable {
    case movies
    case tvShows
    case both

    var itemTypes: [ItemType] {
        switch self {
        case .movies:  return [.movie]
        case .tvShows: return [.series]
        case .both:    return [.movie, .series]
        }
    }

    var collectionTypes: Set<String> {
        switch self {
        case .movies:  return ["movies"]
        case .tvShows: return ["tvshows"]
        case .both:    return ["movies", "tvshows"]
        }
    }

    var displayName: String {
        switch self {
        case .movies:  return "Movies"
        case .tvShows: return "TV Shows"
        case .both:    return "Both"
        }
    }
}

enum MediaBarItemCount: String, StringRepresentableEnum, CaseIterable {
    case five = "5"
    case ten = "10"
    case fifteen = "15"
    case twenty = "20"

    var count: Int { Int(rawValue) ?? 10 }

    var displayName: String { rawValue }
}
