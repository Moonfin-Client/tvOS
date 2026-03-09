import Foundation

struct SubtitleConfigurator {
    let preferences: UserPreferences

    func mediaOptions() -> [String: Any] {
        var options: [String: Any] = [:]

        let textColor = preferences[UserPreferences.subtitlesTextColor]
        let bgColor = preferences[UserPreferences.subtitlesBackgroundColor]
        let strokeColor = preferences[UserPreferences.subtitlesStrokeColor]
        let fontSize = preferences[UserPreferences.subtitlesTextSize]

        options["freetype-fontsize"] = fontSize
        options["freetype-color"] = Int(textColor.argb & 0x00FFFFFF)

        if !bgColor.isTransparent {
            options["freetype-background-color"] = Int(bgColor.argb & 0x00FFFFFF)
            options["freetype-background-opacity"] = Int((bgColor.argb >> 24) & 0xFF)
        } else {
            options["freetype-background-opacity"] = 0
        }

        if !strokeColor.isTransparent {
            options["freetype-outline-color"] = Int(strokeColor.argb & 0x00FFFFFF)
            options["freetype-outline-thickness"] = 2
        } else {
            options["freetype-outline-thickness"] = 0
        }

        options["freetype-bold"] = false

        return options
    }

    var shouldDefaultToNone: Bool {
        preferences[UserPreferences.subtitlesDefaultToNone]
    }
}
