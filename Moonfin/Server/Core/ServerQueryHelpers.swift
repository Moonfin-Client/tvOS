import Foundation

extension ItemType {
    var apiValue: String {
        let raw = rawValue
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

func buildQuery(_ items: [(String, String?)]) -> [URLQueryItem]? {
    let filtered = items.compactMap { (key, value) -> URLQueryItem? in
        guard let value else { return nil }
        return URLQueryItem(name: key, value: value)
    }
    return filtered.isEmpty ? nil : filtered
}
