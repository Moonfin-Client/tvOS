import SwiftUI

struct PhotoPlayerScreen: View {
    @StateObject private var viewModel: PhotoPlayerViewModel
    @EnvironmentObject private var theme: MoonfinTheme
    @FocusState private var focusedControl: ControlFocus?

    enum ControlFocus: Hashable {
        case previous
        case playPause
        case next
    }

    init(container: AppContainer, itemId: String, autoPlay: Bool, sortBy: String?, sortOrder: String?) {
        _viewModel = StateObject(wrappedValue: PhotoPlayerViewModel(
            container: container,
            itemId: itemId,
            autoPlay: autoPlay,
            sortBy: sortBy,
            sortOrder: sortOrder
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
            } else if let url = viewModel.currentImageUrl, let imageURL = URL(string: url) {
                photoView(imageURL)
            }

            if viewModel.overlayVisible && !viewModel.isLoading {
                overlayView
            }
        }
        .focusable()
        .onPlayPauseCommand { viewModel.togglePlayPause() }
        .onMoveCommand { direction in
            switch direction {
            case .left: viewModel.goToPrevious()
            case .right: viewModel.goToNext()
            default: break
            }
            viewModel.showOverlay()
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.cleanup() }
    }

    private func photoView(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.3))
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
            }
        }
        .id(viewModel.currentIndex)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: viewModel.currentIndex)
    }

    private var overlayView: some View {
        VStack {
            headerSection
            Spacer()
            controlsSection
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 27)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayVisible)
        .onChange(of: viewModel.overlayVisible) { visible in
            if visible { focusedControl = .playPause }
        }
    }

    private var headerSection: some View {
        Text(viewModel.photoTitle)
            .font(.title2xl)
            .foregroundColor(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SpaceTokens.spaceMd)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -48)
            .padding(.top, -27)
        )
    }

    private var controlsSection: some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            HStack(spacing: SpaceTokens.spaceMd) {
                overlayButton(icon: "backward.end.fill", focus: .previous) {
                    viewModel.goToPrevious()
                }

                overlayButton(
                    icon: viewModel.isPlaying ? "pause.fill" : "play.fill",
                    focus: .playPause,
                    size: 44
                ) {
                    viewModel.togglePlayPause()
                }

                overlayButton(icon: "forward.end.fill", focus: .next) {
                    viewModel.goToNext()
                }
            }

            Text(viewModel.positionText)
                .font(.bodySm)
                .foregroundColor(.white.opacity(0.8))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, SpaceTokens.spaceMd)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.horizontal, -48)
            .padding(.bottom, -27)
        )
    }

    private func overlayButton(
        icon: String,
        focus: ControlFocus,
        size: CGFloat = 32,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(.white)
                .frame(width: size + 24, height: size + 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(OverlayButtonStyle(isFocused: focusedControl == focus))
        .focused($focusedControl, equals: focus)
    }
}
