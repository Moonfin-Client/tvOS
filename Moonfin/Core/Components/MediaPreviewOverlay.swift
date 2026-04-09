import SwiftUI

struct MediaPreviewOverlay: View {
    let item: ServerItem
    let shouldPlay: Bool
    let muted: Bool

    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var previewManager: PreviewPlayerManager

    private var isActiveItem: Bool {
        previewManager.currentItemId == item.id
    }

    var body: some View {
        Group {
            if isActiveItem {
                Color.clear.overlay(
                    PersistentSurfaceHost(surfaceView: previewManager.persistentSurface, player: previewManager.player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fill)
                )
                .clipped()
                .opacity(previewManager.isVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: previewManager.isVisible)
            }
        }
        .onChange(of: shouldPlay) { newValue in
            if newValue {
                previewManager.requestPreview(for: item, muted: muted, container: container)
            } else {
                previewManager.stopIfCurrent(itemId: item.id)
            }
        }
        .onDisappear {
            previewManager.stopIfCurrent(itemId: item.id)
        }
    }
}

private class SurfaceHostView: UIView {
    var onWindowAttach: (() -> Void)?
    private var hasNotifiedAttach = false

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil && bounds.width > 0 && !hasNotifiedAttach {
            hasNotifiedAttach = true
            onWindowAttach?()
        }
    }
}

private struct PersistentSurfaceHost: UIViewRepresentable {
    let surfaceView: UIView
    let player: MpvPlayerWrapper

    func makeUIView(context: Context) -> UIView {
        let host = SurfaceHostView()
        host.backgroundColor = .clear
        host.clipsToBounds = true
        surfaceView.frame = host.bounds
        surfaceView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(surfaceView)
        host.onWindowAttach = { [weak player] in
            player?.notifySurfaceReady()
        }
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if surfaceView.superview !== host {
            surfaceView.frame = host.bounds
            host.addSubview(surfaceView)
        } else {
            surfaceView.frame = host.bounds
        }
    }
}
