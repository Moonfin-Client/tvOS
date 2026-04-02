import Foundation
import KeychainAccess

final class KeychainStore {
    private let keychain: Keychain

    init(service: String = "org.moonfin.app") {
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlock)
    }

    func get(_ key: String) -> String? {
        try? keychain.get(key)
    }

    func set(_ key: String, value: String) {
        try? keychain.set(value, key: key)
    }

    func delete(_ key: String) {
        try? keychain.remove(key)
    }

    func contains(_ key: String) -> Bool {
        (try? keychain.contains(key)) ?? false
    }

    func removeAll() {
        try? keychain.removeAll()
    }
}
