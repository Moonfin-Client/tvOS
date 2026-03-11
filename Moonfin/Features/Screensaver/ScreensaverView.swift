import SwiftUI
import NukeUI

struct ScreensaverView: View {
    @EnvironmentObject var container: AppContainer
    @StateObject private var viewModel: ScreensaverViewModel
    let onDismiss: () -> Void

    init(container: AppContainer, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ScreensaverViewModel(container: container))
        self.onDismiss = onDismiss
    }

    private var dimmingLevel: Int {
        container.userPreferences[UserPreferences.screensaverDimmingLevel]
    }

    private var showClock: Bool {
        container.userPreferences[UserPreferences.screensaverShowClock]
    }

    private var contentId: String {
        switch viewModel.content {
        case .logo: return "logo"
        case .libraryShowcase(let item, _, _): return item.id
        case .nowPlaying(let item): return item.id
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            contentView
                .id(contentId)
                .transition(.opacity)
                .animation(.easeInOut(duration: 1.0), value: viewModel.content)

            if dimmingLevel > 0 {
                Color.black.opacity(Double(dimmingLevel) / 100.0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if showClock {
                BouncingClockView(dimmingLevel: dimmingLevel)
            }
        }
        .ignoresSafeArea()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onExitCommand { onDismiss() }
        .onMoveCommand { _ in onDismiss() }
        .onPlayPauseCommand { onDismiss() }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.content {
        case .logo:
            BouncingLogoView()
        case .libraryShowcase(let item, let backdropUrl, let logoUrl):
            LibraryShowcaseView(item: item, backdropUrl: backdropUrl, logoUrl: logoUrl)
        case .nowPlaying(let item):
            NowPlayingScreensaverView(item: item, container: container)
        }
    }
}

// MARK: - Bouncing View

private struct BouncingView<Content: View>: View {
    let contentSize: CGSize
    let content: Content

    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var velocityX: CGFloat = 0.5
    @State private var velocityY: CGFloat = 0.5
    @State private var bounceTimer: Timer?

    private let margin: CGFloat = 20

    init(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.contentSize = CGSize(width: width, height: height)
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            content
                .offset(x: offsetX, y: offsetY)
                .onAppear {
                    offsetX = (geo.size.width - contentSize.width) / 2
                    offsetY = (geo.size.height - contentSize.height) / 2
                    velocityX = Bool.random() ? 0.5 : -0.5
                    velocityY = Bool.random() ? 0.5 : -0.5
                    startBounce(in: geo.size)
                }
                .onDisappear { bounceTimer?.invalidate() }
        }
    }

    private func startBounce(in size: CGSize) {
        bounceTimer?.invalidate()
        bounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                let maxX = size.width - contentSize.width - margin
                let maxY = size.height - contentSize.height - margin

                var newX = offsetX + velocityX
                var newY = offsetY + velocityY

                if newX <= margin || newX >= maxX {
                    velocityX = -velocityX
                    newX = max(margin, min(newX, maxX))
                }
                if newY <= margin || newY >= maxY {
                    velocityY = -velocityY
                    newY = max(margin, min(newY, maxY))
                }

                offsetX = newX
                offsetY = newY
            }
        }
    }
}

// MARK: - Bouncing Logo

private struct BouncingLogoView: View {
    var body: some View {
        BouncingView(width: 400, height: 200) {
            Image("LogoText")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 400)
        }
        .background(Color.black)
    }
}

// MARK: - Library Showcase

private struct LibraryShowcaseView: View {
    let item: ServerItem
    let backdropUrl: String
    let logoUrl: String?

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage(urlString: backdropUrl)
                .scaleEffect(scale)
                .animation(.linear(duration: 30), value: scale)
                .onAppear { scale = 1.1 }

            vignetteOverlay

            itemOverlay
                .padding(48)
        }
    }

    private var vignetteOverlay: some View {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color.black.opacity(0.2), location: 0),
                .init(color: Color.black.opacity(0.7), location: 0.95)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 960
        )
    }

    @ViewBuilder
    private var itemOverlay: some View {
        if let logoUrl {
            CachedImage(urlString: logoUrl, contentMode: .fit)
                .frame(maxWidth: 500, maxHeight: 75)
        } else {
            Text(item.name)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .shadow(radius: 4)
        }
    }
}

// MARK: - Now Playing

private struct NowPlayingScreensaverView: View {
    let item: ServerItem
    let container: AppContainer

    private var primaryImageUrl: String? {
        guard let server = container.serverRepository.currentServer.value else { return nil }
        let api = container.serverClientFactory.client(for: server).imageApi
        if let tag = item.imageTags?[ImageType.primary.rawValue] {
            return api.getItemImageUrl(itemId: item.id, imageType: .primary, maxWidth: 300, maxHeight: nil, tag: tag)
        }
        if let parentId = item.albumId, let tag = item.albumPrimaryImageTag {
            return api.getItemImageUrl(itemId: parentId, imageType: .primary, maxWidth: 300, maxHeight: nil, tag: tag)
        }
        return nil
    }

    private var artistText: String {
        let names = item.artists ?? []
        if !names.isEmpty { return names.joined(separator: ", ") }
        let albumArtists = item.albumArtists?.compactMap(\.name) ?? []
        if !albumArtists.isEmpty { return albumArtists.joined(separator: ", ") }
        return item.albumArtist ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black

            HStack(alignment: .bottom, spacing: 20) {
                if let url = primaryImageUrl {
                    CachedImage(urlString: url)
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)

                    if !artistText.isEmpty {
                        Text(artistText)
                            .font(.system(size: 18))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                }
            }
            .padding(48)
        }
    }
}

// MARK: - Bouncing Clock

private struct BouncingClockView: View {
    let dimmingLevel: Int

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var clockAlpha: Double {
        1.0 - (Double(dimmingLevel) / 100.0 * 0.7)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: currentTime)
    }

    var body: some View {
        BouncingView(width: 150, height: 50) {
            Text(timeString)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white.opacity(clockAlpha))
                .monospacedDigit()
        }
        .allowsHitTesting(false)
        .onReceive(timer) { currentTime = $0 }
    }
}
