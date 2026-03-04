import Foundation

final class UserDefaultsPreferenceStore: PreferenceStore {
    private let defaults: UserDefaults
    private let migrationRunner: MigrationRunner
    private static let versionPreference = Preference(key: "store_version", defaultValue: -1)

    init(defaults: UserDefaults = .standard, migrations: [Migration] = []) {
        self.defaults = defaults
        self.migrationRunner = MigrationRunner(migrations: migrations)
        runMigrations()
    }

    subscript<T>(preference: Preference<T>) -> T {
        get { getValue(preference) }
        set { setValue(preference, value: newValue) }
    }

    func delete<T>(_ preference: Preference<T>) {
        defaults.removeObject(forKey: preference.key)
    }

    func reset<T>(_ preference: Preference<T>) {
        self[preference] = preference.defaultValue
    }

    private func getValue<T>(_ preference: Preference<T>) -> T {
        guard defaults.object(forKey: preference.key) != nil else {
            return preference.defaultValue
        }

        switch preference.defaultValue {
        case is Int:
            return defaults.integer(forKey: preference.key) as! T
        case is Double:
            return defaults.double(forKey: preference.key) as! T
        case is Float:
            return defaults.float(forKey: preference.key) as! T
        case is Bool:
            return defaults.bool(forKey: preference.key) as! T
        case is String:
            return (defaults.string(forKey: preference.key) ?? preference.defaultValue as! String) as! T
        default:
            return getEnum(preference) ?? preference.defaultValue
        }
    }

    private func setValue<T>(_ preference: Preference<T>, value: T) {
        switch value {
        case let v as Int:
            defaults.set(v, forKey: preference.key)
        case let v as Double:
            defaults.set(v, forKey: preference.key)
        case let v as Float:
            defaults.set(v, forKey: preference.key)
        case let v as Bool:
            defaults.set(v, forKey: preference.key)
        case let v as String:
            defaults.set(v, forKey: preference.key)
        default:
            setEnum(preference, value: value)
        }
    }

    private func getEnum<T>(_ preference: Preference<T>) -> T? {
        guard let raw = defaults.string(forKey: preference.key),
              let enumType = T.self as? any StringRepresentableEnum.Type,
              let result = enumType.init(rawValue: raw) as? T else {
            return nil
        }
        return result
    }

    private func setEnum<T>(_ preference: Preference<T>, value: T) {
        if let rawEnum = value as? any StringRepresentableEnum {
            defaults.set(rawEnum.rawValue, forKey: preference.key)
        }
    }

    private func runMigrations() {
        let currentVersion = self[Self.versionPreference]
        let newVersion = migrationRunner.apply(
            currentVersion: currentVersion,
            editor: MigrationEditor(defaults: defaults)
        )
        if newVersion != currentVersion {
            self[Self.versionPreference] = newVersion
        }
    }
}
