import SwiftUI

struct SettingsListButton: View {
    let icon: String
    let heading: String
    var caption: String? = nil
    var trailingText: String? = nil
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        Button(action: action) {
            SettingsItemContent(icon: icon, heading: heading, caption: caption) { isFocused in
                if let trailingText {
                    Text(trailingText)
                        .font(.captionXs)
                        .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused : theme.colorScheme.listCaption)
                }

                Image(systemName: "chevron.right")
                    .font(.captionXs)
                    .foregroundColor(isFocused ? theme.colorScheme.listCaptionFocused.opacity(0.5) : theme.colorScheme.listCaption)
            }
        }
        .buttonStyle(CleanButtonStyle())
    }
}

struct SettingsNavRow: View {
    @EnvironmentObject var settingsRouter: SettingsRouter

    private var focusedRoute: FocusState<SettingsRoute?>.Binding
    let route: SettingsRoute
    let icon: String
    let heading: String
    var caption: String? = nil
    var trailingText: String? = nil

    init(
        focusedRoute: FocusState<SettingsRoute?>.Binding,
        route: SettingsRoute,
        icon: String,
        heading: String,
        caption: String? = nil,
        trailingText: String? = nil
    ) {
        self.focusedRoute = focusedRoute
        self.route = route
        self.icon = icon
        self.heading = heading
        self.caption = caption
        self.trailingText = trailingText
    }

    var body: some View {
        SettingsListButton(
            icon: icon,
            heading: heading,
            caption: caption,
            trailingText: trailingText,
            action: { settingsRouter.navigate(to: route) }
        )
        .focused(focusedRoute, equals: route)
    }
}
