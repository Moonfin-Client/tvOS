import SwiftUI

/// A lightweight overlay that shows the shared preview player when this card is focused.
///
/// All playback logic lives in PreviewPlayerManager. This view just requests/releases
/// the shared player and renders PlaybackSurfaceView when it owns the active preview.
struct EpisodePreviewOverlay: View {
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
            if isActiveItem && previewManager.isVisible {
                PlaybackSurfaceView(player: previewManager.player)
                    .transition(.opacity)
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
