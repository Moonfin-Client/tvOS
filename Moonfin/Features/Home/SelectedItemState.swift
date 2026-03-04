import Foundation

struct SelectedItemState: Equatable {
    let title: String
    let summary: String
    let item: ServerItem?
    let logoUrl: String?
    let backdropUrl: String?

    static let empty = SelectedItemState(title: "", summary: "", item: nil, logoUrl: nil, backdropUrl: nil)

    static func == (lhs: SelectedItemState, rhs: SelectedItemState) -> Bool {
        lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.item?.id == rhs.item?.id
            && lhs.logoUrl == rhs.logoUrl
            && lhs.backdropUrl == rhs.backdropUrl
    }
}
