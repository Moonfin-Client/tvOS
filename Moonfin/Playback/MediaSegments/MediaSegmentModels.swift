import Foundation

enum MediaSegmentType: String, Codable {
    case unknown = "Unknown"
    case commercial = "Commercial"
    case preview = "Preview"
    case recap = "Recap"
    case outro = "Outro"
    case intro = "Intro"

    static let supported: [MediaSegmentType] = [.intro, .outro, .preview, .recap, .commercial]

    var displayName: String { rawValue }

    var skipLabel: String {
        self == .unknown ? "Skip" : "Skip \(rawValue)"
    }
}

enum MediaSegmentAction: String, StringRepresentableEnum, CaseIterable {
    case nothing
    case skip
    case askToSkip

    var displayName: String {
        switch self {
        case .nothing: return "Nothing"
        case .skip: return "Skip"
        case .askToSkip: return "Ask to Skip"
        }
    }
}

struct MediaSegmentDto: Codable, Identifiable {
    let id: String
    let itemId: String
    let type: MediaSegmentType
    let startTicks: Int64
    let endTicks: Int64

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case itemId = "ItemId"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }

    var startSeconds: TimeInterval { TimeInterval(startTicks) / 10_000_000.0 }
    var endSeconds: TimeInterval { TimeInterval(endTicks) / 10_000_000.0 }
    var durationSeconds: TimeInterval { max(endSeconds - startSeconds, 0) }
}

struct MediaSegmentQueryResult: Codable {
    let items: [MediaSegmentDto]
    let totalRecordCount: Int
    let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}
