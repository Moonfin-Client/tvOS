import SwiftUI

struct ExpandableLibrariesButton: View {
    let libraries: [ServerItem]
    let activeLibraryId: String?
    let onLibrarySelected: (ServerItem) -> Void
    let pillNamespace: Namespace.ID
    let pillAnchorId: NavbarItem
    let pillHeight: CGFloat
    let onIconFocusChanged: (Bool) -> Void

    enum FocusedItem: Hashable {
        case icon
        case library(String)
    }

    @FocusState private var focusedItem: FocusedItem?
    @State private var isExpanded = false
    @EnvironmentObject var theme: MoonfinTheme

    private var initialLibraryFocus: FocusedItem? {
        if let activeLibraryId,
           libraries.contains(where: { $0.id == activeLibraryId }) {
            return .library(activeLibraryId)
        }
        if let first = libraries.first {
            return .library(first.id)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if isExpanded {
                    isExpanded = false
                    focusedItem = .icon
                } else {
                    isExpanded = true
                    if let target = initialLibraryFocus {
                        DispatchQueue.main.async {
                            focusedItem = target
                        }
                    }
                }
            }) {
                HStack(spacing: SpaceTokens.spaceSm) {
                    Image(systemName: "movieclapper.fill")
                        .font(.system(size: 26))

                    Text("Libraries")
                        .font(.bodyMd)
                        .fontWeight(.bold)
                        .padding(.trailing, 4)
                        .opacity(focusedItem == .icon && !isExpanded ? 1.0 : 0.0)
                        .frame(width: focusedItem == .icon && !isExpanded ? nil : 0, alignment: .center)
                        .clipped()
                }
                .padding(.horizontal, focusedItem == .icon ? 20 : 10)
                .padding(.vertical, 12)
                .foregroundColor(iconForeground)
            }
            .buttonStyle(CleanButtonStyle())
            .focused($focusedItem, equals: .icon)
            .background(Color.clear.frame(height: pillHeight).matchedGeometryEffect(id: pillAnchorId, in: pillNamespace, isSource: true))
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: focusedItem)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(libraries, id: \.id) { library in
                            Button(action: { onLibrarySelected(library) }) {
                                Text(library.name)
                                    .font(.bodyMd)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 18)
                                    .frame(height: pillHeight)
                                    .background(
                                        Capsule()
                                            .fill(pillBackground(for: library))
                                    )
                                    .foregroundColor(pillForeground(for: library))
                            }
                            .buttonStyle(CleanButtonStyle())
                            .focused($focusedItem, equals: .library(library.id))
                            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: focusedItem)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                }
                .frame(maxWidth: 700)
                .onMoveCommand { direction in
                    if direction == .up {
                        isExpanded = false
                        focusedItem = .icon
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .center)),
                        removal: .opacity
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .onChange(of: focusedItem) { newValue in
            onIconFocusChanged(newValue == .icon)
            if newValue == nil {
                isExpanded = false
            }
        }
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
