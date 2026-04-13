import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var style: BannerStyle = .error
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme

    enum BannerStyle {
        case error, warning, info

        var icon: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .error: return Color.red.opacity(0.85)
            case .warning: return Color.orange.opacity(0.85)
            case .info: return Color.blue.opacity(0.85)
            }
        }
    }

    var body: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            Image(systemName: style.icon)
                .font(.bodyLg)

            Text(message)
                .font(.bodySm)
                .lineLimit(2)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.captionSm)
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, SpaceTokens.spaceMd)
        .padding(.vertical, SpaceTokens.spaceSm)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(style.backgroundColor)
        )
    }
}

struct RetryableErrorView: View {
    let title: String
    var message: String? = nil
    var retryAction: (() -> Void)? = nil
    var backAction: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))

            Text(title)
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)

            if let message {
                Text(message)
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: SpaceTokens.spaceMd) {
                if let retryAction {
                    FocusableDialogButton(title: Strings.retry, action: retryAction)
                }
                if let backAction {
                    FocusableDialogButton(title: Strings.goBack, action: backAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServerUnavailableView: View {
    let serverName: String
    var onRetry: (() -> Void)? = nil
    var onSwitchServer: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))

            Text(Strings.serverUnavailableTitle)
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)

            Text(Strings.unableToConnectTo(serverName))
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))

            HStack(spacing: SpaceTokens.spaceMd) {
                if let onRetry {
                    FocusableDialogButton(title: Strings.retry, action: onRetry)
                }
                if let onSwitchServer {
                    FocusableDialogButton(title: Strings.switchServerAction, action: onSwitchServer)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NetworkRetryDialog: View {
    let error: NetworkError
    let onRetry: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject var theme: MoonfinTheme

    var body: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            Image(systemName: dialogIcon)
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(dialogTitle)
                .font(.titleMd)
                .foregroundColor(theme.colorScheme.onBackground)

            Text(error.userFacingMessage)
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.7))
                .multilineTextAlignment(.center)

            HStack(spacing: SpaceTokens.spaceMd) {
                if error.isRetryable {
                    FocusableDialogButton(title: Strings.retry, action: onRetry)
                }
                FocusableDialogButton(title: Strings.dismiss, action: onCancel)
            }
        }
        .padding(SpaceTokens.spaceXl)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.large)
                .fill(theme.colorScheme.surface)
        )
        .frame(maxWidth: 500)
    }

    private var dialogIcon: String {
        switch error {
        case .unauthorized: return "lock.fill"
        case .serverUnavailable: return "server.rack"
        case .networkError: return "wifi.slash"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var dialogTitle: String {
        switch error {
        case .unauthorized: return Strings.authenticationRequired
        case .serverUnavailable: return Strings.serverUnavailableTitle
        case .networkError: return Strings.connectionError
        default: return Strings.errorTitle
        }
    }
}

struct InlineErrorView: View {
    let message: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: SpaceTokens.spaceXs) {
            Image(systemName: "exclamationmark.circle")
                .font(compact ? .captionSm : .bodySm)
            Text(message)
                .font(compact ? .captionSm : .bodySm)
                .lineLimit(compact ? 1 : 3)
        }
        .foregroundColor(.red.opacity(0.9))
    }
}

struct ErrorOverlayModifier: ViewModifier {
    let error: NetworkError?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if let error {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    NetworkRetryDialog(
                        error: error,
                        onRetry: onRetry,
                        onCancel: onDismiss
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: error != nil)
    }
}

extension View {
    func networkErrorOverlay(
        error: NetworkError?,
        onRetry: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(ErrorOverlayModifier(error: error, onRetry: onRetry, onDismiss: onDismiss))
    }

    func errorBanner(
        message: String?,
        style: ErrorBannerView.BannerStyle = .error,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        overlay(alignment: .top) {
            if let message {
                ErrorBannerView(message: message, style: style, onDismiss: onDismiss)
                    .padding(.horizontal, SpaceTokens.spaceLg)
                    .padding(.top, SpaceTokens.spaceSm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: message != nil)
    }
}
