import Foundation
import SwiftUI

enum ThemeSpecValidationError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidRoot
    case missingField(String)
    case invalidField(String)
    case outOfBounds(field: String, min: Double, max: Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported theme schemaVersion \(version)."
        case .invalidRoot:
            return "Theme payload root must be an object."
        case .missingField(let field):
            return "Missing required field '\(field)'."
        case .invalidField(let field):
            return "Invalid field '\(field)'."
        case .outOfBounds(let field, let min, let max):
            return "Field '\(field)' must be between \(min) and \(max)."
        }
    }
}

struct ThemeHexColor: Equatable, Hashable {
    let argb: UInt32

    init(argb: UInt32) {
        self.argb = argb
    }

    init(hexString raw: String, field: String) throws {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        switch hex.count {
        case 3:
            let chars = Array(hex)
            hex = "FF\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
        case 6:
            hex = "FF\(hex)"
        case 8:
            break
        default:
            throw ThemeSpecValidationError.invalidField(field)
        }

        guard let value = UInt32(hex, radix: 16) else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        self.argb = value
    }

    var color: Color {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

struct ThemeShadowSpec: Equatable {
    let color: ThemeHexColor
    let blurRadius: Double
    let spreadRadius: Double
    let offsetX: Double
    let offsetY: Double

    static func parse(
        _ raw: Any,
        field: String,
        allowSpread: Bool
    ) throws -> ThemeShadowSpec {
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        let color = try ThemeParser.requiredColor(map, key: "color", field: "\(field).color")
        let blur = try ThemeParser.optionalDouble(map, key: "blurRadius", defaultValue: 0)
        guard (0...64).contains(blur) else {
            throw ThemeSpecValidationError.outOfBounds(field: "\(field).blurRadius", min: 0, max: 64)
        }

        let spread = try ThemeParser.optionalDouble(map, key: "spreadRadius", defaultValue: 0)
        if !allowSpread, spread != 0 {
            throw ThemeSpecValidationError.invalidField("\(field).spreadRadius")
        }
        if allowSpread, !(-32...32).contains(spread) {
            throw ThemeSpecValidationError.outOfBounds(field: "\(field).spreadRadius", min: -32, max: 32)
        }

        let offsetX = try ThemeParser.optionalDouble(map, key: "offsetX", defaultValue: 0)
        let offsetY = try ThemeParser.optionalDouble(map, key: "offsetY", defaultValue: 0)

        return ThemeShadowSpec(
            color: color,
            blurRadius: blur,
            spreadRadius: spread,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }
}

struct ThemeBorderSideSpec: Equatable {
    let color: ThemeHexColor
    let width: Double

    static func parse(_ raw: Any, field: String) throws -> ThemeBorderSideSpec {
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        let color = try ThemeParser.requiredColor(map, key: "color", field: "\(field).color")
        let width = try ThemeParser.optionalDouble(map, key: "width", defaultValue: 1)
        guard (0...16).contains(width) else {
            throw ThemeSpecValidationError.outOfBounds(field: "\(field).width", min: 0, max: 16)
        }
        return ThemeBorderSideSpec(color: color, width: width)
    }
}

enum ThemeCornerRadiusSpec: Equatable {
    case uniform(Double)
    case corners(topLeft: Double, topRight: Double, bottomLeft: Double, bottomRight: Double)

    static func parse(_ raw: Any, field: String) throws -> ThemeCornerRadiusSpec {
        if let value = raw as? NSNumber {
            let radius = value.doubleValue
            guard (0...9_999).contains(radius) else {
                throw ThemeSpecValidationError.outOfBounds(field: field, min: 0, max: 9_999)
            }
            return .uniform(radius)
        }
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }

        let tl = try ThemeParser.optionalDouble(map, key: "topLeft", defaultValue: 0)
        let tr = try ThemeParser.optionalDouble(map, key: "topRight", defaultValue: 0)
        let bl = try ThemeParser.optionalDouble(map, key: "bottomLeft", defaultValue: 0)
        let br = try ThemeParser.optionalDouble(map, key: "bottomRight", defaultValue: 0)
        for (name, value) in [("topLeft", tl), ("topRight", tr), ("bottomLeft", bl), ("bottomRight", br)] {
            if !(0...9_999).contains(value) {
                throw ThemeSpecValidationError.outOfBounds(field: "\(field).\(name)", min: 0, max: 9_999)
            }
        }
        return .corners(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br)
    }
}

struct ThemeColorTokensSpec: Equatable {
    let background: ThemeHexColor
    let onBackground: ThemeHexColor
    let surface: ThemeHexColor
    let onSurface: ThemeHexColor
    let surfaceVariant: ThemeHexColor
    let scrim: ThemeHexColor
    let accent: ThemeHexColor
    let onAccent: ThemeHexColor
    let buttonNormal: ThemeHexColor
    let buttonFocused: ThemeHexColor
    let buttonDisabled: ThemeHexColor
    let buttonActive: ThemeHexColor
    let onButtonNormal: ThemeHexColor
    let onButtonFocused: ThemeHexColor
    let onButtonDisabled: ThemeHexColor
    let inputBackground: ThemeHexColor
    let inputFocused: ThemeHexColor
    let inputBorder: ThemeHexColor
    let inputBorderFocused: ThemeHexColor
    let rangeTrack: ThemeHexColor
    let rangeProgress: ThemeHexColor
    let rangeThumb: ThemeHexColor
    let seekbarBuffered: ThemeHexColor
    let badgeBackground: ThemeHexColor
    let onBadge: ThemeHexColor
    let badgeUnplayed: ThemeHexColor
    let badgeWatched: ThemeHexColor
    let recordingActive: ThemeHexColor
    let recordingScheduled: ThemeHexColor

    static func parse(_ raw: Any, field: String) throws -> ThemeColorTokensSpec {
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        return ThemeColorTokensSpec(
            background: try ThemeParser.requiredColor(map, key: "background", field: "colors.background"),
            onBackground: try ThemeParser.requiredColor(map, key: "onBackground", field: "colors.onBackground"),
            surface: try ThemeParser.requiredColor(map, key: "surface", field: "colors.surface"),
            onSurface: try ThemeParser.requiredColor(map, key: "onSurface", field: "colors.onSurface"),
            surfaceVariant: try ThemeParser.requiredColor(map, key: "surfaceVariant", field: "colors.surfaceVariant"),
            scrim: try ThemeParser.requiredColor(map, key: "scrim", field: "colors.scrim"),
            accent: try ThemeParser.requiredColor(map, key: "accent", field: "colors.accent"),
            onAccent: try ThemeParser.requiredColor(map, key: "onAccent", field: "colors.onAccent"),
            buttonNormal: try ThemeParser.requiredColor(map, key: "buttonNormal", field: "colors.buttonNormal"),
            buttonFocused: try ThemeParser.requiredColor(map, key: "buttonFocused", field: "colors.buttonFocused"),
            buttonDisabled: try ThemeParser.requiredColor(map, key: "buttonDisabled", field: "colors.buttonDisabled"),
            buttonActive: try ThemeParser.requiredColor(map, key: "buttonActive", field: "colors.buttonActive"),
            onButtonNormal: try ThemeParser.requiredColor(map, key: "onButtonNormal", field: "colors.onButtonNormal"),
            onButtonFocused: try ThemeParser.requiredColor(map, key: "onButtonFocused", field: "colors.onButtonFocused"),
            onButtonDisabled: try ThemeParser.requiredColor(map, key: "onButtonDisabled", field: "colors.onButtonDisabled"),
            inputBackground: try ThemeParser.requiredColor(map, key: "inputBackground", field: "colors.inputBackground"),
            inputFocused: try ThemeParser.requiredColor(map, key: "inputFocused", field: "colors.inputFocused"),
            inputBorder: try ThemeParser.requiredColor(map, key: "inputBorder", field: "colors.inputBorder"),
            inputBorderFocused: try ThemeParser.requiredColor(map, key: "inputBorderFocused", field: "colors.inputBorderFocused"),
            rangeTrack: try ThemeParser.requiredColor(map, key: "rangeTrack", field: "colors.rangeTrack"),
            rangeProgress: try ThemeParser.requiredColor(map, key: "rangeProgress", field: "colors.rangeProgress"),
            rangeThumb: try ThemeParser.requiredColor(map, key: "rangeThumb", field: "colors.rangeThumb"),
            seekbarBuffered: try ThemeParser.requiredColor(map, key: "seekbarBuffered", field: "colors.seekbarBuffered"),
            badgeBackground: try ThemeParser.requiredColor(map, key: "badgeBackground", field: "colors.badgeBackground"),
            onBadge: try ThemeParser.requiredColor(map, key: "onBadge", field: "colors.onBadge"),
            badgeUnplayed: try ThemeParser.requiredColor(map, key: "badgeUnplayed", field: "colors.badgeUnplayed"),
            badgeWatched: try ThemeParser.requiredColor(map, key: "badgeWatched", field: "colors.badgeWatched"),
            recordingActive: try ThemeParser.requiredColor(map, key: "recordingActive", field: "colors.recordingActive"),
            recordingScheduled: try ThemeParser.requiredColor(map, key: "recordingScheduled", field: "colors.recordingScheduled")
        )
    }
}

struct ThemeBorderTokensSpec: Equatable {
    let cardBorder: ThemeBorderSideSpec
    let chipBorder: ThemeBorderSideSpec
    let focusBorder: ThemeBorderSideSpec
    let navBorder: ThemeBorderSideSpec?
    let cardRadius: ThemeCornerRadiusSpec
    let chipRadius: ThemeCornerRadiusSpec
    let chipBackground: ThemeHexColor
    let focusGlow: [ThemeShadowSpec]

    static func parse(_ raw: Any, field: String) throws -> ThemeBorderTokensSpec {
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        let glow = try ThemeParser.shadowList(
            map["focusGlow"],
            field: "borders.focusGlow",
            maxItems: 8,
            allowSpread: true
        )
        return ThemeBorderTokensSpec(
            cardBorder: try ThemeBorderSideSpec.parse(ThemeParser.requiredAny(map, key: "cardBorder", field: "borders.cardBorder"), field: "borders.cardBorder"),
            chipBorder: try ThemeBorderSideSpec.parse(ThemeParser.requiredAny(map, key: "chipBorder", field: "borders.chipBorder"), field: "borders.chipBorder"),
            focusBorder: try ThemeBorderSideSpec.parse(ThemeParser.requiredAny(map, key: "focusBorder", field: "borders.focusBorder"), field: "borders.focusBorder"),
            navBorder: try ThemeParser.optionalBorder(map, key: "navBorder", field: "borders.navBorder"),
            cardRadius: try ThemeCornerRadiusSpec.parse(ThemeParser.requiredAny(map, key: "cardRadius", field: "borders.cardRadius"), field: "borders.cardRadius"),
            chipRadius: try ThemeCornerRadiusSpec.parse(ThemeParser.requiredAny(map, key: "chipRadius", field: "borders.chipRadius"), field: "borders.chipRadius"),
            chipBackground: try ThemeParser.requiredColor(map, key: "chipBackground", field: "borders.chipBackground"),
            focusGlow: glow
        )
    }
}

struct ThemeSemanticTokensSpec: Equatable {
    let textHeadline: ThemeHexColor
    let textBody: ThemeHexColor
    let textCaption: ThemeHexColor
    let statusAvailable: ThemeHexColor
    let statusRequested: ThemeHexColor
    let statusPending: ThemeHexColor
    let statusDownloading: ThemeHexColor
    let mediaTypeBadgeMovie: ThemeHexColor
    let mediaTypeBadgeShow: ThemeHexColor

    static let defaults = ThemeSemanticTokensSpec(
        textHeadline: ThemeHexColor(argb: 0xFFFFFFFF),
        textBody: ThemeHexColor(argb: 0xFFEEEEEE),
        textCaption: ThemeHexColor(argb: 0xCCEEEEEE),
        statusAvailable: ThemeHexColor(argb: 0xFF22C55E),
        statusRequested: ThemeHexColor(argb: 0xFF9333EA),
        statusPending: ThemeHexColor(argb: 0xFFEAB308),
        statusDownloading: ThemeHexColor(argb: 0xFF6366F1),
        mediaTypeBadgeMovie: ThemeHexColor(argb: 0xFF3B82F6),
        mediaTypeBadgeShow: ThemeHexColor(argb: 0xFF8B5CF6)
    )

    static func parse(_ raw: Any?) throws -> ThemeSemanticTokensSpec {
        guard let raw else { return .defaults }
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField("semantic")
        }
        return ThemeSemanticTokensSpec(
            textHeadline: try ThemeParser.optionalColor(
                map,
                key: "textHeadline",
                field: "semantic.textHeadline",
                defaultValue: defaults.textHeadline
            ),
            textBody: try ThemeParser.optionalColor(
                map,
                key: "textBody",
                field: "semantic.textBody",
                defaultValue: defaults.textBody
            ),
            textCaption: try ThemeParser.optionalColor(
                map,
                key: "textCaption",
                field: "semantic.textCaption",
                defaultValue: defaults.textCaption
            ),
            statusAvailable: try ThemeParser.requiredColor(map, key: "statusAvailable", field: "semantic.statusAvailable"),
            statusRequested: try ThemeParser.requiredColor(map, key: "statusRequested", field: "semantic.statusRequested"),
            statusPending: try ThemeParser.requiredColor(map, key: "statusPending", field: "semantic.statusPending"),
            statusDownloading: try ThemeParser.requiredColor(map, key: "statusDownloading", field: "semantic.statusDownloading"),
            mediaTypeBadgeMovie: try ThemeParser.requiredColor(map, key: "mediaTypeBadgeMovie", field: "semantic.mediaTypeBadgeMovie"),
            mediaTypeBadgeShow: try ThemeParser.requiredColor(map, key: "mediaTypeBadgeShow", field: "semantic.mediaTypeBadgeShow")
        )
    }
}

struct ThemeBookTokensSpec: Equatable {
    let background: ThemeHexColor
    let accent: ThemeHexColor
    let mutedText: ThemeHexColor
    let primaryText: ThemeHexColor
    let sectionTitle: ThemeHexColor
    let divider: ThemeHexColor
    let placeholder: ThemeHexColor
    let shadow: ThemeHexColor
    let gradientTop: ThemeHexColor
    let gradientBottom: ThemeHexColor
    let inactiveChip: ThemeHexColor
    let placeholderPalette: [ThemeHexColor]

    static let defaults = ThemeBookTokensSpec(
        background: ThemeHexColor(argb: 0xFF0F182A),
        accent: ThemeHexColor(argb: 0xFF32B9E8),
        mutedText: ThemeHexColor(argb: 0xFF9EDBFF),
        primaryText: ThemeHexColor(argb: 0xFFDCEFFF),
        sectionTitle: ThemeHexColor(argb: 0xFFFFE6C3),
        divider: ThemeHexColor(argb: 0x223E5F82),
        placeholder: ThemeHexColor(argb: 0xFF2C77B7),
        shadow: ThemeHexColor(argb: 0x24000000),
        gradientTop: ThemeHexColor(argb: 0xFF18263D),
        gradientBottom: ThemeHexColor(argb: 0xFF0B1424),
        inactiveChip: ThemeHexColor(argb: 0x556388A8),
        placeholderPalette: [
            ThemeHexColor(argb: 0xFF1A5C9A),
            ThemeHexColor(argb: 0xFF2E7D32),
            ThemeHexColor(argb: 0xFF6A1B9A),
            ThemeHexColor(argb: 0xFF00695C),
            ThemeHexColor(argb: 0xFFC62828),
            ThemeHexColor(argb: 0xFF4527A0),
            ThemeHexColor(argb: 0xFF558B2F),
            ThemeHexColor(argb: 0xFF283593),
            ThemeHexColor(argb: 0xFF4E342E),
            ThemeHexColor(argb: 0xFF00838F)
        ]
    )

    static func parse(_ raw: Any?) throws -> ThemeBookTokensSpec {
        guard let raw else { return .defaults }
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidField("book")
        }
        let palette = try ThemeParser.colorList(
            map["placeholderPalette"],
            field: "book.placeholderPalette",
            maxItems: 16,
            allowEmpty: false,
            fallback: defaults.placeholderPalette
        )
        return ThemeBookTokensSpec(
            background: try ThemeParser.requiredColor(map, key: "background", field: "book.background"),
            accent: try ThemeParser.requiredColor(map, key: "accent", field: "book.accent"),
            mutedText: try ThemeParser.requiredColor(map, key: "mutedText", field: "book.mutedText"),
            primaryText: try ThemeParser.requiredColor(map, key: "primaryText", field: "book.primaryText"),
            sectionTitle: try ThemeParser.requiredColor(map, key: "sectionTitle", field: "book.sectionTitle"),
            divider: try ThemeParser.requiredColor(map, key: "divider", field: "book.divider"),
            placeholder: try ThemeParser.requiredColor(map, key: "placeholder", field: "book.placeholder"),
            shadow: try ThemeParser.requiredColor(map, key: "shadow", field: "book.shadow"),
            gradientTop: try ThemeParser.requiredColor(map, key: "gradientTop", field: "book.gradientTop"),
            gradientBottom: try ThemeParser.requiredColor(map, key: "gradientBottom", field: "book.gradientBottom"),
            inactiveChip: try ThemeParser.requiredColor(map, key: "inactiveChip", field: "book.inactiveChip"),
            placeholderPalette: palette
        )
    }
}

enum ThemeBrightness: String, Equatable {
    case dark
    case light
}

struct ThemeSpec: Equatable {
    static let currentSchemaVersion = 1

    let id: String
    let displayName: String
    let brightness: ThemeBrightness
    let fontFamily: String?
    let textGlow: [ThemeShadowSpec]
    let navColorCycle: [ThemeHexColor]
    let transparentNavbarSurface: Bool
    let semantic: ThemeSemanticTokensSpec
    let book: ThemeBookTokensSpec
    let colors: ThemeColorTokensSpec
    let borders: ThemeBorderTokensSpec

    static func parse(jsonData: Data) throws -> ThemeSpec {
        let raw = try JSONSerialization.jsonObject(with: jsonData)
        guard let map = raw as? [String: Any] else {
            throw ThemeSpecValidationError.invalidRoot
        }
        return try parse(jsonObject: map)
    }

    static func parse(jsonObject map: [String: Any]) throws -> ThemeSpec {
        let schemaVersion = (map["schemaVersion"] as? NSNumber)?.intValue ?? 1
        if schemaVersion > currentSchemaVersion {
            throw ThemeSpecValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        let id = try ThemeParser.requiredString(map, key: "id", field: "id")
        let idPattern = "^[a-z0-9_-]+$"
        if id.range(of: idPattern, options: .regularExpression) == nil {
            throw ThemeSpecValidationError.invalidField("id")
        }

        let displayName = try ThemeParser.requiredString(map, key: "displayName", field: "displayName")
        let brightnessRaw = try ThemeParser.requiredString(map, key: "brightness", field: "brightness")
        guard let brightness = ThemeBrightness(rawValue: brightnessRaw) else {
            throw ThemeSpecValidationError.invalidField("brightness")
        }

        let textGlow = try ThemeParser.shadowList(
            map["textGlow"],
            field: "textGlow",
            maxItems: 8,
            allowSpread: false
        )

        let fontFamily: String?
        if let rawFont = map["fontFamily"] as? String {
            let trimmed = rawFont.trimmingCharacters(in: .whitespacesAndNewlines)
            fontFamily = trimmed.isEmpty ? nil : trimmed
        } else {
            fontFamily = nil
        }

        return ThemeSpec(
            id: id,
            displayName: displayName,
            brightness: brightness,
            fontFamily: fontFamily,
            textGlow: textGlow,
            navColorCycle: try ThemeParser.colorList(map["navColorCycle"], field: "navColorCycle", maxItems: 16, allowEmpty: true, fallback: []),
            transparentNavbarSurface: (map["transparentNavbarSurface"] as? Bool) ?? false,
            semantic: try ThemeSemanticTokensSpec.parse(map["semantic"]),
            book: try ThemeBookTokensSpec.parse(map["book"]),
            colors: try ThemeColorTokensSpec.parse(ThemeParser.requiredAny(map, key: "colors", field: "colors"), field: "colors"),
            borders: try ThemeBorderTokensSpec.parse(ThemeParser.requiredAny(map, key: "borders", field: "borders"), field: "borders")
        )
    }
}

private enum ThemeParser {
    static func requiredAny(_ map: [String: Any], key: String, field: String) throws -> Any {
        guard let value = map[key] else {
            throw ThemeSpecValidationError.missingField(field)
        }
        return value
    }

    static func requiredString(_ map: [String: Any], key: String, field: String) throws -> String {
        guard let value = map[key] as? String else {
            throw ThemeSpecValidationError.missingField(field)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw ThemeSpecValidationError.invalidField(field)
        }
        return trimmed
    }

    static func requiredColor(_ map: [String: Any], key: String, field: String) throws -> ThemeHexColor {
        guard let raw = map[key] as? String else {
            throw ThemeSpecValidationError.missingField(field)
        }
        return try ThemeHexColor(hexString: raw, field: field)
    }

    static func optionalColor(
        _ map: [String: Any],
        key: String,
        field: String,
        defaultValue: ThemeHexColor
    ) throws -> ThemeHexColor {
        guard let raw = map[key] else { return defaultValue }
        guard let colorText = raw as? String else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        return try ThemeHexColor(hexString: colorText, field: field)
    }

    static func optionalDouble(
        _ map: [String: Any],
        key: String,
        defaultValue: Double
    ) throws -> Double {
        guard let value = map[key] else { return defaultValue }
        guard let number = value as? NSNumber else {
            throw ThemeSpecValidationError.invalidField(key)
        }
        return number.doubleValue
    }

    static func shadowList(
        _ raw: Any?,
        field: String,
        maxItems: Int,
        allowSpread: Bool
    ) throws -> [ThemeShadowSpec] {
        guard let raw else { return [] }
        guard let list = raw as? [Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        if list.count > maxItems {
            throw ThemeSpecValidationError.invalidField(field)
        }
        return try list.enumerated().map { index, entry in
            try ThemeShadowSpec.parse(entry, field: "\(field)[\(index)]", allowSpread: allowSpread)
        }
    }

    static func colorList(
        _ raw: Any?,
        field: String,
        maxItems: Int,
        allowEmpty: Bool,
        fallback: [ThemeHexColor]
    ) throws -> [ThemeHexColor] {
        guard let raw else { return fallback }
        guard let list = raw as? [Any] else {
            throw ThemeSpecValidationError.invalidField(field)
        }
        if list.count > maxItems || (!allowEmpty && list.isEmpty) {
            throw ThemeSpecValidationError.invalidField(field)
        }
        return try list.enumerated().map { index, value in
            guard let text = value as? String else {
                throw ThemeSpecValidationError.invalidField("\(field)[\(index)]")
            }
            return try ThemeHexColor(hexString: text, field: "\(field)[\(index)]")
        }
    }

    static func optionalBorder(
        _ map: [String: Any],
        key: String,
        field: String
    ) throws -> ThemeBorderSideSpec? {
        guard let raw = map[key] else { return nil }
        if raw is NSNull { return nil }
        return try ThemeBorderSideSpec.parse(raw, field: field)
    }
}
