import SwiftUI
import Combine

enum BlurContext {
    case details
    case browsing
    case none
}

@MainActor
final class BackgroundService: ObservableObject {
    @Published private(set) var currentBackdropUrl: String?
    @Published private(set) var blurAmount: CGFloat = 0
    @Published private(set) var enabled: Bool = true

    private var blurContext: BlurContext = .none

    private var backgrounds: [String] = []
    private var currentIndex: Int = 0
    private var slideshowTimer: AnyCancellable?
    private var lastUpdateTime: Date = .distantPast
    private weak var preferences: UserPreferences?

    static let slideshowInterval: TimeInterval = 30
    static let transitionDuration: TimeInterval = 0.4

    func configure(preferences: UserPreferences) {
        self.preferences = preferences
    }

    func setBackground(urls: [String], context: BlurContext = .browsing) {
        if let prefs = preferences, !prefs[UserPreferences.backdropEnabled] {
            clearBackground()
            return
        }
        setBackgroundInternal(urls: urls, context: context)
    }

    func setBackground(url: String?, context: BlurContext = .browsing) {
        guard let url else {
            clearBackground()
            return
        }
        setBackground(urls: [url], context: context)
    }

    func clearBackground() {
        slideshowTimer?.cancel()
        slideshowTimer = nil
        enabled = true
        if backgrounds.isEmpty { return }
        backgrounds = []
        currentIndex = 0
        currentBackdropUrl = nil
    }

    func disable() {
        enabled = false
    }

    private func setBackgroundInternal(urls: [String], context: BlurContext) {
        guard !urls.isEmpty else {
            clearBackground()
            return
        }

        enabled = true
        blurContext = context
        blurAmount = blurAmount(for: context)
        backgrounds = urls
        currentIndex = 0
        currentBackdropUrl = urls.first
        lastUpdateTime = Date()

        if backgrounds.count > 1 {
            scheduleTimer(delay: Self.slideshowInterval, advanceIndex: true)
        } else {
            slideshowTimer?.cancel()
            slideshowTimer = nil
        }
    }

    private func blurAmount(for context: BlurContext) -> CGFloat {
        guard let prefs = preferences else {
            switch context {
            case .details: return 20
            case .browsing: return 20
            case .none: return 0
            }
        }
        switch context {
        case .details: return CGFloat(prefs[UserPreferences.detailsBackgroundBlur])
        case .browsing: return CGFloat(prefs[UserPreferences.browsingBackgroundBlur])
        case .none: return 0
        }
    }

    private func update() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdateTime)

        if elapsed < Self.transitionDuration {
            let remaining = Self.transitionDuration - elapsed
            scheduleTimer(delay: remaining, advanceIndex: false)
            return
        }

        lastUpdateTime = now

        if currentIndex >= backgrounds.count { currentIndex = 0 }
        currentBackdropUrl = backgrounds.isEmpty ? nil : backgrounds[currentIndex]

        if backgrounds.count > 1 {
            scheduleTimer(delay: Self.slideshowInterval, advanceIndex: true)
        } else {
            slideshowTimer?.cancel()
            slideshowTimer = nil
        }
    }

    private func scheduleTimer(delay: TimeInterval, advanceIndex: Bool) {
        slideshowTimer?.cancel()
        slideshowTimer = Timer.publish(every: delay, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                guard let self else { return }
                if advanceIndex { self.currentIndex += 1 }
                self.update()
            }
    }
}
