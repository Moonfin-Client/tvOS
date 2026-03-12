import Foundation

enum SupportedLocale: String, CaseIterable, Identifiable {
    case system = "system"
    case af, ar, be, bg, bn, ca, cs, cy, da, de
    case el, en, enGB = "en-GB", eo, es
    case esAR = "es-AR", esDO = "es-DO", esMX = "es-MX", es419 = "es-419"
    case et, fa, fi, fr, gl, he, hi, hr, hu
    case id, it, ja, kk, kn, ko
    case lt, lv, mk, ml, mn, nb, nl
    case pa, pl, pt, ptBR = "pt-BR", ptPT = "pt-PT"
    case ro, ru, si, sk, sl, sq, sr
    case sv, sw, ta, te, th, tl, tr
    case ug, uk, vi
    case zhHans = "zh-Hans", zhHant = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        if self == .system { return "System Default" }
        let name = Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var nativeName: String {
        if self == .system { return "" }
        let locale = Locale(identifier: rawValue)
        let name = locale.localizedString(forIdentifier: rawValue) ?? rawValue
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    var isRTL: Bool {
        switch self {
        case .ar, .fa, .he, .ug: return true
        default: return false
        }
    }

    static var rtlLocales: Set<String> { ["ar", "fa", "he", "ug"] }
}
