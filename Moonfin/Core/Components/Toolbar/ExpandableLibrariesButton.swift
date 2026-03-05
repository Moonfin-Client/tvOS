import SwiftUI

struct ExpandableLibrariesButton: View {
    let libraries: [ServerItem]
    let activeLibraryId: String?
    let onLibrarySelected: (ServerItem) -> Void

    enum FocusedItem: Hashable {
        case icon
        case library(String)
    }

    @FocusState private var focusedItem: FocusedItem?
    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                Image(systemName: "movieclapper.fill")
                    .font(.system(size: 22))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(iconBackground)
                    )
                    .foregroundColor(iconForeground)
            }
            .buttonStyle(CleanButtonStyle())
            .focused($focusedItem, equals: .icon)

            if isExpanded {
                HStack(spacing: 0) {
                    ForEach(libraries, id: \.id) { library in
                        Button(action: { onLibrarySelected(library) }) {
                            Text(library.name)
                                .font(.bodySm)
                                .fontWeight(.bold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(pillBackground(for: library))
                                )
                                .foregroundColor(pillForeground(for: library))
                        }
                        .buttonStyle(CleanButtonStyle())
                        .focused($focusedItem, equals: .library(library.id))
                        .scaleEffect(focusedItem == .library(library.id) ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: focusedItem)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .fixedSize()
                .onMoveCommand { direction in
                    if direction == .up {
                        isExpanded = false
                        focusedItem = nil
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .leading)),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .onChange(of: focusedItem) { newValue in
            collapseTask?.cancel()
            if newValue != nil {
                isExpanded = true
            } else {
                collapseTask = Task {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    isExpanded = false
                }
            }
        }
    }

    private var iconBackground: Color {
        if focusedItem == .icon { return theme.focusBorder.color }
        if activeLibraryId != nil { return theme.colorScheme.buttonActive }
        return .clear
    }

    private var iconForeground: Color {
        if focusedItem == .icon { return theme.focusBorder.color.contrastingContentColor }
        if activeLibraryId != nil { return theme.colorScheme.onButtonActive }
        return theme.colorScheme.onButton
    }

    private func pillBackground(for library: ServerItem) -> Color {
        if focusedItem == .library(library.id) { return theme.focusBorder.color }
        if library.id == activeLibraryId { return theme.colorScheme.buttonActive }
        return .clear
    }

    private func pillForeground(for library: ServerItem) -> Color {
        if focusedItem == .library(library.id) { return theme.focusBorder.color.contrastingContentColor }
        if library.id == activeLibraryId { return theme.colorScheme.onButtonActive }
        return theme.colorScheme.onButton
    }
}
