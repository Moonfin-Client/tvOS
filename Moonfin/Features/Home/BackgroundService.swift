import SwiftUI
import Combine

@MainActor
final class BackgroundService: ObservableObject {
    @Published private(set) var currentBackdropUrl: String?
    @Published var blurAmount: CGFloat = 20

    private var backgrounds: [String] = []
    private var currentIndex: Int = 0
    private var slideshowTimer: AnyCancellable?
    private var lastUpdateTime: Date = .distantPast

    private static let slideshowInterval: TimeInterval = 30
    private static let transitionGuard: TimeInterval = 0.8

    func setBackground(urls: [String]) {
        guard !urls.isEmpty else {
            clearBackground()
            return
        }

        backgrounds = urls
        currentIndex = 0
        updateCurrentBackdrop()
        startSlideshow()
    }

    func setBackground(url: String?) {
        guard let url else {
            clearBackground()
            return
        }
        setBackground(urls: [url])
    }

    func clearBackground() {
        slideshowTimer?.cancel()
        slideshowTimer = nil
        backgrounds = []
        currentIndex = 0
        currentBackdropUrl = nil
    }

    private func updateCurrentBackdrop() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= Self.transitionGuard else { return }
        lastUpdateTime = now

        guard !backgrounds.isEmpty else { return }
        currentBackdropUrl = backgrounds[currentIndex % backgrounds.count]
    }

    private func startSlideshow() {
        slideshowTimer?.cancel()
        guard backgrounds.count > 1 else {
            slideshowTimer = nil
            return
        }

        slideshowTimer = Timer.publish(every: Self.slideshowInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentIndex += 1
                self.updateCurrentBackdrop()
            }
    }
}
