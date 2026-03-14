import Foundation

struct SubtitleConfigurator {
    let preferences: UserPreferences

    func mediaOptions() -> [String: Any] {
        var options: [String: Any] = [:]

        let textColor = preferences[UserPreferences.subtitlesTextColor]
        let bgColor = preferences[UserPreferences.subtitlesBackgroundColor]
        let strokeColor = preferences[UserPreferences.subtitlesStrokeColor]
        let fontSize = preferences[UserPreferences.subtitlesTextSize]

        // Use relative font size (video_height / value) for reliable cross-resolution scaling.
        // freetype-fontsize must be 0 so VLC uses freetype-rel-fontsize instead.
        options["freetype-fontsize"] = 0
        options["freetype-rel-fontsize"] = max(12, 1080 / max(1, fontSize))
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

        let offset = preferences[UserPreferences.subtitlesOffsetPosition]
        if offset > 0 {
            options["sub-margin"] = offset * 10
        }

        return options
    }

    var shouldDefaultToNone: Bool {
        preferences[UserPreferences.subtitlesDefaultToNone]
    }
}
