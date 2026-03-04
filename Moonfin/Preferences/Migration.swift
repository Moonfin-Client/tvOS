import Foundation

struct Migration {
    let toVersion: Int
    let body: (MigrationEditor) -> Void
}

final class MigrationEditor {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func getString(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ key: String, value: String) {
        defaults.set(value, forKey: key)
    }

    func getInt(_ key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func setInt(_ key: String, value: Int) {
        defaults.set(value, forKey: key)
    }

    func getBool(_ key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func setBool(_ key: String, value: Bool) {
        defaults.set(value, forKey: key)
    }

    func remove(_ key: String) {
        defaults.removeObject(forKey: key)
    }

    func rename(from oldKey: String, to newKey: String) {
        guard let value = defaults.object(forKey: oldKey) else { return }
        defaults.set(value, forKey: newKey)
        defaults.removeObject(forKey: oldKey)
    }
}

final class MigrationRunner {
    private let migrations: [Migration]

    init(migrations: [Migration]) {
        self.migrations = migrations
    }

    func apply(currentVersion: Int, editor: MigrationEditor) -> Int {
        guard !migrations.isEmpty else { return currentVersion }

        let highVersion = migrations.map(\.toVersion).max() ?? -1

        if currentVersion >= highVersion { return currentVersion }
        if currentVersion == -1 { return highVersion }

        let pending = migrations
            .filter { $0.toVersion > currentVersion }
            .sorted { $0.toVersion < $1.toVersion }

        for migration in pending {
            migration.body(editor)
        }

        return max(highVersion, currentVersion)
    }
}
