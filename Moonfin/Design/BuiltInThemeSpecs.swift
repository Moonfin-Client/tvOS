import Foundation

extension ThemeSpec {
    static let moonfin = ThemeSpec(
        id: "moonfin",
        displayName: "Moonfin",
        brightness: .dark,
        fontFamily: nil,
        textGlow: [],
        navColorCycle: [],
        transparentNavbarSurface: false,
        semantic: ThemeSemanticTokensSpec(
            textHeadline: ThemeHexColor(argb: 0xFFFFFFFF),
            textBody: ThemeHexColor(argb: 0xFFE6E6E6),
            textCaption: ThemeHexColor(argb: 0xCCFFFFFF),
            statusAvailable: ThemeHexColor(argb: 0xFF22C55E),
            statusRequested: ThemeHexColor(argb: 0xFF9333EA),
            statusPending: ThemeHexColor(argb: 0xFFEAB308),
            statusDownloading: ThemeHexColor(argb: 0xFF6366F1),
            mediaTypeBadgeMovie: ThemeHexColor(argb: 0xFF3B82F6),
            mediaTypeBadgeShow: ThemeHexColor(argb: 0xFF8B5CF6)
        ),
        book: .defaults,
        colors: ThemeColorTokensSpec(
            background: ThemeHexColor(argb: 0xFF101010),
            onBackground: ThemeHexColor(argb: 0xFFFFFFFF),
            surface: ThemeHexColor(argb: 0xFF1C2026),
            onSurface: ThemeHexColor(argb: 0xFFFFFFFF),
            surfaceVariant: ThemeHexColor(argb: 0xFF252525),
            scrim: ThemeHexColor(argb: 0xAA000000),
            accent: ThemeHexColor(argb: 0xFF00A4DC),
            onAccent: ThemeHexColor(argb: 0xFFFFFFFF),
            buttonNormal: ThemeHexColor(argb: 0xFF2A2A2A),
            buttonFocused: ThemeHexColor(argb: 0xFF00A4DC),
            buttonDisabled: ThemeHexColor(argb: 0xFF1E1E1E),
            buttonActive: ThemeHexColor(argb: 0xFF3A3A3A),
            onButtonNormal: ThemeHexColor(argb: 0xFFFFFFFF),
            onButtonFocused: ThemeHexColor(argb: 0xFFFFFFFF),
            onButtonDisabled: ThemeHexColor(argb: 0xFF666666),
            inputBackground: ThemeHexColor(argb: 0xFF2A2A2A),
            inputFocused: ThemeHexColor(argb: 0xFF3A3A3A),
            inputBorder: ThemeHexColor(argb: 0xFF404040),
            inputBorderFocused: ThemeHexColor(argb: 0xFF00A4DC),
            rangeTrack: ThemeHexColor(argb: 0xFF404040),
            rangeProgress: ThemeHexColor(argb: 0xFF00A4DC),
            rangeThumb: ThemeHexColor(argb: 0xFF00A4DC),
            seekbarBuffered: ThemeHexColor(argb: 0x80FFFFFF),
            badgeBackground: ThemeHexColor(argb: 0xFF00A4DC),
            onBadge: ThemeHexColor(argb: 0xFFFFFFFF),
            badgeUnplayed: ThemeHexColor(argb: 0xFF00A4DC),
            badgeWatched: ThemeHexColor(argb: 0xFF4CAF50),
            recordingActive: ThemeHexColor(argb: 0xFFF44336),
            recordingScheduled: ThemeHexColor(argb: 0xFFFF9800)
        ),
        borders: ThemeBorderTokensSpec(
            cardBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0x00000000), width: 1),
            chipBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0x558EC8F0), width: 1),
            focusBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0xFF00A4DC), width: 2),
            navBorder: nil,
            cardRadius: .uniform(8),
            chipRadius: .uniform(999),
            chipBackground: ThemeHexColor(argb: 0x1F8EC8F0),
            focusGlow: []
        )
    )

    static let neonPulse = ThemeSpec(
        id: "neon_pulse",
        displayName: "Neon Pulse",
        brightness: .dark,
        fontFamily: "NeonPulseDisplay",
        textGlow: [
            ThemeShadowSpec(
                color: ThemeHexColor(argb: 0x6600E5FF),
                blurRadius: 8,
                spreadRadius: 0,
                offsetX: 0,
                offsetY: 0
            )
        ],
        navColorCycle: [
            ThemeHexColor(argb: 0xFFFF2E92),
            ThemeHexColor(argb: 0xFF00E5FF)
        ],
        transparentNavbarSurface: true,
        semantic: ThemeSemanticTokensSpec(
            textHeadline: ThemeHexColor(argb: 0xFF00E5FF),
            textBody: ThemeHexColor(argb: 0xFFB8F6FF),
            textCaption: ThemeHexColor(argb: 0xCCB8F6FF),
            statusAvailable: ThemeHexColor(argb: 0xFF22C55E),
            statusRequested: ThemeHexColor(argb: 0xFF9333EA),
            statusPending: ThemeHexColor(argb: 0xFFEAB308),
            statusDownloading: ThemeHexColor(argb: 0xFF6366F1),
            mediaTypeBadgeMovie: ThemeHexColor(argb: 0xFF3B82F6),
            mediaTypeBadgeShow: ThemeHexColor(argb: 0xFF8B5CF6)
        ),
        book: .defaults,
        colors: ThemeColorTokensSpec(
            background: ThemeHexColor(argb: 0xFF0B0420),
            onBackground: ThemeHexColor(argb: 0xFF00E5FF),
            surface: ThemeHexColor(argb: 0xCC1E0A3F),
            onSurface: ThemeHexColor(argb: 0xFF00E5FF),
            surfaceVariant: ThemeHexColor(argb: 0xCC1E0A3F),
            scrim: ThemeHexColor(argb: 0xCC0B0420),
            accent: ThemeHexColor(argb: 0xFFFF2E92),
            onAccent: ThemeHexColor(argb: 0xFFFFFFFF),
            buttonNormal: ThemeHexColor(argb: 0x00000000),
            buttonFocused: ThemeHexColor(argb: 0x33FF2E92),
            buttonDisabled: ThemeHexColor(argb: 0x22FFFFFF),
            buttonActive: ThemeHexColor(argb: 0x33FF2E92),
            onButtonNormal: ThemeHexColor(argb: 0xFFFF2E92),
            onButtonFocused: ThemeHexColor(argb: 0xFFFFFFFF),
            onButtonDisabled: ThemeHexColor(argb: 0xAAFFFFFF),
            inputBackground: ThemeHexColor(argb: 0x331E0A3F),
            inputFocused: ThemeHexColor(argb: 0x441E0A3F),
            inputBorder: ThemeHexColor(argb: 0x66FF2E92),
            inputBorderFocused: ThemeHexColor(argb: 0xFFFF2E92),
            rangeTrack: ThemeHexColor(argb: 0x66201840),
            rangeProgress: ThemeHexColor(argb: 0xFFFF2E92),
            rangeThumb: ThemeHexColor(argb: 0xFFFF2E92),
            seekbarBuffered: ThemeHexColor(argb: 0x66FFFFFF),
            badgeBackground: ThemeHexColor(argb: 0xFFFF2E92),
            onBadge: ThemeHexColor(argb: 0xFFFFFFFF),
            badgeUnplayed: ThemeHexColor(argb: 0xFFFF2E92),
            badgeWatched: ThemeHexColor(argb: 0xFFFF2E92),
            recordingActive: ThemeHexColor(argb: 0xFFFF2E92),
            recordingScheduled: ThemeHexColor(argb: 0xFF00E5FF)
        ),
        borders: ThemeBorderTokensSpec(
            cardBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0x66FF2E92), width: 1),
            chipBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0xCCFF2E92), width: 1.2),
            focusBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0xFFFF2E92), width: 1.4),
            navBorder: ThemeBorderSideSpec(color: ThemeHexColor(argb: 0xCCFF2E92), width: 1),
            cardRadius: .uniform(10),
            chipRadius: .uniform(8),
            chipBackground: ThemeHexColor(argb: 0x00000000),
            focusGlow: [
                ThemeShadowSpec(
                    color: ThemeHexColor(argb: 0x99FF2E92),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                    offsetX: 0,
                    offsetY: 0
                ),
                ThemeShadowSpec(
                    color: ThemeHexColor(argb: 0x6600E5FF),
                    blurRadius: 5,
                    spreadRadius: 0,
                    offsetX: 0,
                    offsetY: 0
                )
            ]
        )
    )
}
