import SwiftUI

final class LocalizationPreferences {
    private var store: PreferenceStore

    static let appLanguage = Preference(key: "app_language", defaultValue: "system")

    init(store: PreferenceStore) {
        self.store = store
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { store[preference] }
        set { store[preference] = newValue }
    }

    func binding<T>(for preference: Preference<T>) -> Binding<T> {
        Binding(
            get: { self[preference] },
            set: { self[preference] = $0 }
        )
    }
}
