import Foundation

enum AppConstants {
    static let appName = "Moonfin"
    static let clientName = "Moonfin Apple TV"
    static let clientVersion = "1.0.0"
    static let deviceName = Host.current().localizedName ?? "Apple TV"
    static let deviceId: String = {
        let key = "moonfin_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}
