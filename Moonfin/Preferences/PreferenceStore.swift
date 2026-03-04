import Foundation

struct Preference<T> {
    let key: String
    let defaultValue: T
}

protocol StringRepresentableEnum {
    var rawValue: String { get }
    init?(rawValue: String)
}

func enumPreference<T: StringRepresentableEnum>(_ key: String, defaultValue: T) -> Preference<T> {
    Preference(key: key, defaultValue: defaultValue)
}

protocol PreferenceStore {
    subscript<T>(_ preference: Preference<T>) -> T { get set }
    func delete<T>(_ preference: Preference<T>)
    func reset<T>(_ preference: Preference<T>)
}
