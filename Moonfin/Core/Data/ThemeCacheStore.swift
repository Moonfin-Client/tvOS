import Foundation

struct SavedThemeEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
}

final class ThemeCacheStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func serverKey(for client: HttpClient) -> String {
        let normalized = client.baseURL?
            .absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let sanitized = normalized.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "_",
            options: .regularExpression
        )

        return sanitized.isEmpty ? "default" : sanitized
    }

    func loadCachedThemes(serverKey: String) -> [ThemeSpec] {
        let entries = (try? loadCachedThemeEntries(serverKey: serverKey)) ?? []
        return entries.map(\.spec)
    }

    func listSavedThemes(serverKey: String) -> [SavedThemeEntry] {
        let entries = (try? loadCachedThemeEntries(serverKey: serverKey)) ?? []
        return entries
            .map { SavedThemeEntry(id: $0.spec.id, displayName: $0.spec.displayName) }
            .sorted { lhs, rhs in
                let nameCompare = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if nameCompare != .orderedSame {
                    return nameCompare == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    func writeCachedThemes(_ themeObjects: [[String: Any]], serverKey: String) throws {
        guard let cacheDir = try cacheDirectory(serverKey: serverKey, createIfMissing: true) else {
            return
        }

        var desiredFileNames = Set<String>()

        for map in themeObjects {
            guard let rawId = map["id"] as? String else { continue }
            let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || ThemeRegistry.builtInIds.contains(id) { continue }

            let fileName = "\(sanitizeThemeFileNameStem(id)).json"
            let fileURL = cacheDir.appendingPathComponent(fileName, isDirectory: false)

            let data = try JSONSerialization.data(withJSONObject: map, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)

            desiredFileNames.insert(fileName)
        }

        let existing = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }

        for fileURL in existing where !desiredFileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func deleteCachedTheme(themeId: String, serverKey: String) throws -> Bool {
        let trimmedThemeId = themeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedThemeId.isEmpty else {
            return false
        }

        let entries = try loadCachedThemeEntries(serverKey: serverKey)
        var deleted = false

        for entry in entries where entry.spec.id == trimmedThemeId {
            try? fileManager.removeItem(at: entry.fileURL)
            deleted = true
        }

        if deleted {
            return true
        }

        guard let cacheDir = try cacheDirectory(serverKey: serverKey, createIfMissing: false) else {
            return false
        }

        let fallbackFile = cacheDir.appendingPathComponent(
            "\(sanitizeThemeFileNameStem(trimmedThemeId)).json",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: fallbackFile.path) {
            try? fileManager.removeItem(at: fallbackFile)
            return true
        }

        return false
    }

    private func loadCachedThemeEntries(serverKey: String) throws -> [(spec: ThemeSpec, fileURL: URL)] {
        guard let cacheDir = try cacheDirectory(serverKey: serverKey, createIfMissing: false) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var entries: [(spec: ThemeSpec, fileURL: URL)] = []

        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let raw = try JSONSerialization.jsonObject(with: data)
                guard let map = raw as? [String: Any] else { continue }
                let spec = try ThemeSpec.parse(jsonObject: map)
                if ThemeRegistry.builtInIds.contains(spec.id) {
                    continue
                }
                entries.append((spec: spec, fileURL: fileURL))
            } catch {}
        }

        return entries
    }

    private func cacheDirectory(serverKey: String, createIfMissing: Bool) throws -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let root = base
            .appendingPathComponent("Moonfin", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true)
            .appendingPathComponent(serverKey, isDirectory: true)

        if createIfMissing, !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: root.path) {
            return nil
        }

        return root
    }

    private func sanitizeThemeFileNameStem(_ rawId: String) -> String {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sanitized = trimmed.replacingOccurrences(
            of: "[^a-z0-9_-]+",
            with: "_",
            options: .regularExpression
        )

        return sanitized.isEmpty ? "theme" : sanitized
    }
}
