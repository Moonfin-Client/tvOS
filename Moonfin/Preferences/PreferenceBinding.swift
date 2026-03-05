import SwiftUI

extension UserPreferences {
    func binding<T>(for preference: Preference<T>) -> Binding<T> {
        Binding(
            get: { self[preference] },
            set: { self[preference] = $0 }
        )
    }
}
