import SwiftUI

struct ExpandableLibrariesButton: View {
    let libraries: [ServerItem]
    let activeLibraryId: String?
    let onLibrarySelected: (ServerItem) -> Void

    @FocusState private var groupFocused: Bool
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        HStack(spacing: 0) {
            libraryIcon

            if groupFocused {
                libraryButtons
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity
                        )
                    )
            }
        }
        .focusSection()
        .animation(.easeInOut(duration: 0.25), value: groupFocused)
    }

    private var libraryIcon: some View {
        Button(action: {}) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 22))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(hasActiveLibrary ? theme.colorScheme.buttonActive : theme.colorScheme.button)
                )
                .foregroundColor(hasActiveLibrary ? theme.colorScheme.onButtonActive : theme.colorScheme.onButton)
        }
        .buttonStyle(CleanButtonStyle())
        .focusable()
        .focused($groupFocused)
    }

    private var libraryButtons: some View {
        HStack(spacing: SpaceTokens.spaceXs) {
            ForEach(libraries, id: \.id) { library in
                LibraryPillButton(
                    library: library,
                    isActive: library.id == activeLibraryId,
                    onTap: { onLibrarySelected(library) }
                )
            }
        }
        .padding(.leading, SpaceTokens.spaceSm)
    }

    private var hasActiveLibrary: Bool {
        activeLibraryId != nil
    }
}

private struct LibraryPillButton: View {
    let library: ServerItem
    let isActive: Bool
    let onTap: () -> Void

    @FocusState private var isFocused: Bool
    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: onTap) {
            Text(library.name)
                .font(.bodySm)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(pillBackground)
                )
                .foregroundColor(pillForeground)
        }
        .buttonStyle(CleanButtonStyle())
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var pillBackground: Color {
        if isFocused { return theme.focusBorder.color }
        if isActive { return theme.colorScheme.buttonActive }
        return theme.colorScheme.button
    }

    private var pillForeground: Color {
        if isFocused { return focusContentColor }
        if isActive { return theme.colorScheme.onButtonActive }
        return theme.colorScheme.onButton
    }

    private var focusContentColor: Color {
        theme.focusBorder.color.contrastingContentColor
    }
}
