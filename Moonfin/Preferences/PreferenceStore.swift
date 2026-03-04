import Foundation

struct Preference<T> {
    let key: String
    let defaultValue: T
}

protocol PreferenceStore {
    func get<T>(_ preference: Preference<T>) -> T
    func set<T>(_ preference: Preference<T>, value: T)
}
