import Foundation
import UIKit

enum AppConstants {
    static let appName = "Moonfin"
    static let clientName = "Moonfin Apple TV"
    static let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    static let deviceName = UIDevice.current.name
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
