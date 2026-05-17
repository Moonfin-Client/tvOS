import Foundation

final class ThemeRegistry {
    static let moonfinId = "moonfin"
    static let neonPulseId = "neon_pulse"
    static let builtInIds: Set<String> = [moonfinId, neonPulseId]

    static let shared = ThemeRegistry()

    private let builtIns: [String: ThemeSpec]
    private var customThemes: [String: ThemeSpec]

    private init() {
        self.builtIns = [
            ThemeRegistry.moonfinId: .moonfin,
            ThemeRegistry.neonPulseId: .neonPulse
        ]
        self.customThemes = [:]
    }

    var availableThemes: [String: ThemeSpec] {
        builtIns.merging(customThemes) { _, custom in custom }
    }

    var customThemeList: [ThemeSpec] {
        customThemes.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func resolveById(_ id: String) -> ThemeSpec {
        availableThemes[id] ?? .moonfin
    }

    func registerCustom(_ spec: ThemeSpec) throws {
        if Self.builtInIds.contains(spec.id) {
            throw ThemeSpecValidationError.invalidField("id")
        }
        customThemes[spec.id] = spec
        NotificationCenter.default.post(name: .themeRegistryDidChange, object: nil)
    }

    func replaceCustomThemes(_ specs: [ThemeSpec]) {
        var next: [String: ThemeSpec] = [:]
        for spec in specs where !Self.builtInIds.contains(spec.id) {
            next[spec.id] = spec
        }
        customThemes = next
        NotificationCenter.default.post(name: .themeRegistryDidChange, object: nil)
    }

    func removeCustom(id: String) {
        customThemes.removeValue(forKey: id)
        NotificationCenter.default.post(name: .themeRegistryDidChange, object: nil)
    }

    func clearCustomThemes() {
        customThemes.removeAll()
        NotificationCenter.default.post(name: .themeRegistryDidChange, object: nil)
    }
}
