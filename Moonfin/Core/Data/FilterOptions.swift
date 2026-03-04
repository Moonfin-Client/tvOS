import Foundation

struct FilterOptions: Equatable {
    var isFavoriteOnly = false
    var isUnwatchedOnly = false

    var itemFilters: [ItemFilter] {
        var result: [ItemFilter] = []
        if isFavoriteOnly { result.append(.isFavorite) }
        if isUnwatchedOnly { result.append(.isUnplayed) }
        return result
    }

    var isEmpty: Bool { !isFavoriteOnly && !isUnwatchedOnly }
}
