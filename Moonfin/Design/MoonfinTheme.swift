import SwiftUI

final class MoonfinTheme: ObservableObject {
    private static let focusBorderStorageKey = "focus_border_color"

    @Published private(set) var activeSpec: ThemeSpec
    @Published private(set) var activeThemeId: VisualThemeId
    @Published private(set) var activeCustomId: String

    @Published var colorScheme: MoonfinColorScheme
    @Published var focusBorder: FocusBorderColor {
        didSet {
            guard oldValue != focusBorder else { return }
            UserDefaults.standard.set(focusBorder.rawValue, forKey: Self.focusBorderStorageKey)
        }
    }

    private var defaultsObserver: NSObjectProtocol?
    private var registryObserver: NSObjectProtocol?
    private weak var preferences: UserPreferences?
    private var isInitializing = true
    private let hasStoredFocusBorderAtLaunch: Bool

    var accent: Color { activeSpec.colors.accent.color }
    var effectiveFocusColor: Color { focusBorder.color }
    var isNeonPulseTheme: Bool { activeSpec.id == ThemeRegistry.neonPulseId }

    func navCycleColor(for index: Int) -> Color {
        let cycle = activeSpec.navColorCycle
        guard !cycle.isEmpty else { return colorScheme.onButton }
        return cycle[index % cycle.count].color
    }

    var neonPrimaryColor: Color {
        isNeonPulseTheme ? navCycleColor(for: 0) : colorScheme.onButton
    }

    var neonSecondaryColor: Color {
        isNeonPulseTheme ? navCycleColor(for: 1) : colorScheme.onBackground
    }

    init(colorScheme: MoonfinColorScheme = .default) {
        let stored = UserDefaults.standard.string(forKey: Self.focusBorderStorageKey)
        self.activeSpec = .moonfin
        self.activeThemeId = .moonfin
        self.activeCustomId = ""
        self.colorScheme = colorScheme
        self.focusBorder = stored.flatMap(FocusBorderColor.init(rawValue:)) ?? .white
        self.hasStoredFocusBorderAtLaunch = stored != nil

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isInitializing else { return }
            // Dispatch asynchronously to avoid publishing changes during view updates
            DispatchQueue.main.async { [weak self] in
                self?.refreshFromDefaults()
            }
        }

        registryObserver = NotificationCenter.default.addObserver(
            forName: .themeRegistryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isInitializing else { return }
            // Dispatch asynchronously to avoid publishing changes during view updates
            DispatchQueue.main.async { [weak self] in
                self?.refreshFromDefaults()
            }
        }

        refreshFromDefaults()
        isInitializing = false
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let registryObserver {
            NotificationCenter.default.removeObserver(registryObserver)
        }
    }

    static func builtInThemeIdFor(_ id: VisualThemeId) -> String {
        switch id {
        case .moonfin: return ThemeRegistry.moonfinId
        case .neonPulse: return ThemeRegistry.neonPulseId
        }
    }

    static func builtInThemeForId(_ id: String) -> VisualThemeId? {
        switch id {
        case ThemeRegistry.moonfinId:
            return .moonfin
        case ThemeRegistry.neonPulseId:
            return .neonPulse
        default:
            return nil
        }
    }

    func refreshFromPreferences(_ prefs: UserPreferences) {
        preferences = prefs
        applyResolved(builtIn: prefs[UserPreferences.visualTheme], customId: prefs[UserPreferences.customThemeId])
    }

    func refreshFromDefaults() {
        if let preferences {
            refreshFromPreferences(preferences)
            return
        }
        let fallback = UserPreferences(store: UserDefaultsPreferenceStore(defaults: .standard))
        refreshFromPreferences(fallback)
    }

    func applyThemeSelection(_ prefs: UserPreferences, themeId: VisualThemeId) {
        // Dispatch asynchronously to avoid simultaneous access violations during view updates
        DispatchQueue.main.async { [weak self] in
            prefs[UserPreferences.visualTheme] = themeId
            prefs[UserPreferences.customThemeId] = ""
            self?.applyResolved(builtIn: themeId, customId: "")
        }
    }

    func applyThemeById(_ prefs: UserPreferences, themeId: String) {
        // Dispatch asynchronously to avoid simultaneous access violations during view updates
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            if let builtIn = Self.builtInThemeForId(themeId) {
                prefs[UserPreferences.visualTheme] = builtIn
                prefs[UserPreferences.customThemeId] = ""
                self.applyResolved(builtIn: builtIn, customId: "")
                return
            }

            if ThemeRegistry.shared.availableThemes[themeId] != nil {
                prefs[UserPreferences.customThemeId] = themeId
                self.applyResolved(builtIn: prefs[UserPreferences.visualTheme], customId: themeId)
                return
            }

            prefs[UserPreferences.visualTheme] = .moonfin
            prefs[UserPreferences.customThemeId] = ""
            self.applyResolved(builtIn: .moonfin, customId: "")
        }
    }

    private func applyResolved(builtIn: VisualThemeId, customId: String) {
        let hasCustom = !customId.isEmpty
            && !ThemeRegistry.builtInIds.contains(customId)
            && ThemeRegistry.shared.availableThemes[customId] != nil
        let resolved = hasCustom
            ? ThemeRegistry.shared.resolveById(customId)
            : ThemeRegistry.shared.resolveById(Self.builtInThemeIdFor(builtIn))

        activeThemeId = builtIn
        activeCustomId = hasCustom ? customId : ""
        activeSpec = resolved
        TypographyTokens.fontFamily = resolved.fontFamily

        if !hasStoredFocusBorderAtLaunch && resolved.id == ThemeRegistry.neonPulseId && focusBorder == .white {
            focusBorder = .neonPink
        }

        colorScheme = resolved.toMoonfinColorScheme()
    }
}

extension Notification.Name {
    static let themeRegistryDidChange = Notification.Name("themeRegistryDidChange")
}

private extension ThemeSpec {
    func toMoonfinColorScheme() -> MoonfinColorScheme {
        let isNeonPulse = id == ThemeRegistry.neonPulseId

        return MoonfinColorScheme(
            background: colors.background.color,
            onBackground: colors.onBackground.color,
            surface: colors.surface.color,
            scrim: colors.scrim.color,

            button: colors.buttonNormal.color,
            onButton: colors.onButtonNormal.color,
            buttonFocused: colors.buttonFocused.color,
            onButtonFocused: colors.onButtonFocused.color,
            buttonDisabled: colors.buttonDisabled.color,
            onButtonDisabled: colors.onButtonDisabled.color,
            buttonActive: colors.buttonActive.color,
            onButtonActive: colors.onButtonFocused.color,

            input: colors.inputBackground.color,
            onInput: colors.onSurface.color,
            inputFocused: colors.inputFocused.color,
            onInputFocused: colors.onSurface.color,

            rangeControlBackground: colors.rangeTrack.color,
            rangeControlFill: colors.rangeProgress.color,
            rangeControlKnob: colors.rangeThumb.color,
            seekbarBuffer: colors.seekbarBuffered.color,

            recording: colors.recordingActive.color,
            onRecording: colors.onBadge.color,

            badge: colors.badgeBackground.color,
            onBadge: colors.onBadge.color,

            listHeader: semantic.textHeadline.color,
            listOverline: semantic.textBody.color.opacity(0.85),
            listHeadline: isNeonPulse ? colors.accent.color : semantic.textHeadline.color,
            listCaption: isNeonPulse ? colors.onBackground.color : semantic.textCaption.color,
            listButton: .clear,
            listButtonFocused: isNeonPulse ? colors.accent.color.opacity(0.38) : colors.surfaceVariant.color,
            listHeadlineFocused: semantic.textHeadline.color,
            listCaptionFocused: semantic.textCaption.color,

            statusAvailable: semantic.statusAvailable.color,
            statusRequested: semantic.statusRequested.color,
            statusPending: semantic.statusPending.color,
            statusDownloading: semantic.statusDownloading.color,
            mediaTypeBadgeMovie: semantic.mediaTypeBadgeMovie.color,
            mediaTypeBadgeShow: semantic.mediaTypeBadgeShow.color
        )
    }
}
