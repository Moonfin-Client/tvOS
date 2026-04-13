import Foundation

final class LibraryPreferences {
    private var store: PreferenceStore
    private let libraryId: String

    init(store: PreferenceStore, libraryId: String) {
        self.store = store
        self.libraryId = libraryId
    }

    private func scoped(_ key: String) -> String {
        "library_\(libraryId)_\(key)"
    }

    var posterSize: PosterSize {
        get { store[Preference(key: scoped("poster_size"), defaultValue: PosterSize.medium)] }
        set { store[Preference(key: scoped("poster_size"), defaultValue: PosterSize.medium)] = newValue }
    }

    var imageType: ImageDisplayType {
        get { store[Preference(key: scoped("image_type"), defaultValue: ImageDisplayType.poster)] }
        set { store[Preference(key: scoped("image_type"), defaultValue: ImageDisplayType.poster)] = newValue }
    }

    var sortBy: ItemSortBy {
        get { store[Preference(key: scoped("sort_by"), defaultValue: ItemSortBy.sortName)] }
        set { store[Preference(key: scoped("sort_by"), defaultValue: ItemSortBy.sortName)] = newValue }
    }

    var sortOrder: SortOrder {
        get { store[Preference(key: scoped("sort_order"), defaultValue: SortOrder.ascending)] }
        set { store[Preference(key: scoped("sort_order"), defaultValue: SortOrder.ascending)] = newValue }
    }

    var filterFavoritesOnly: Bool {
        get { store[Preference(key: scoped("filter_favorites"), defaultValue: false)] }
        set { store[Preference(key: scoped("filter_favorites"), defaultValue: false)] = newValue }
    }

    var filterUnwatchedOnly: Bool {
        get { store[Preference(key: scoped("filter_unwatched"), defaultValue: false)] }
        set { store[Preference(key: scoped("filter_unwatched"), defaultValue: false)] = newValue }
    }

    var gridDirection: GridDirection {
        get { store[Preference(key: scoped("grid_direction"), defaultValue: GridDirection.vertical)] }
        set { store[Preference(key: scoped("grid_direction"), defaultValue: GridDirection.vertical)] = newValue }
    }
}

enum GridDirection: String, StringRepresentableEnum, CaseIterable {
    case vertical
    case horizontal

    var displayName: String {
        switch self {
        case .vertical: return Strings.vertical
        case .horizontal: return Strings.horizontal
        }
    }
}

extension ItemSortBy: StringRepresentableEnum {}
extension SortOrder: StringRepresentableEnum {}
