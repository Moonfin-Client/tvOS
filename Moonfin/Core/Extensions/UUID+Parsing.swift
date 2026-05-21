import Foundation

extension UUID {
    static func from(rawId raw: String) -> UUID? {
        if let uuid = UUID(uuidString: raw) {
            return uuid
        }

        let stripped = raw.replacingOccurrences(of: "-", with: "")
        if stripped.count == 32, stripped.allSatisfy({ $0.isHexDigit }) {
            return UUID(uuidString: formatAsUUID(stripped))
        }

        if raw.count <= 32, raw.allSatisfy({ $0.isNumber }) {
            let padded = String(repeating: "0", count: max(0, 32 - raw.count)) + raw
            return UUID(uuidString: formatAsUUID(padded))
        }

        return nil
    }

    private static func formatAsUUID(_ hex32: String) -> String {
        let s = hex32
        let i = s.index(s.startIndex, offsetBy: 8)
        let j = s.index(i, offsetBy: 4)
        let k = s.index(j, offsetBy: 4)
        let l = s.index(k, offsetBy: 4)
        return "\(s[s.startIndex..<i])-\(s[i..<j])-\(s[j..<k])-\(s[k..<l])-\(s[l..<s.endIndex])"
    }
}
