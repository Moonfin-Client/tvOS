import SwiftUI

struct LoginTextField: View {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(text: $text, prompt: Text(placeholder).foregroundColor(.gray)) {}
                    .onSubmit { onSubmit?() }
            } else {
                TextField(text: $text, prompt: Text(placeholder).foregroundColor(.gray)) {}
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { onSubmit?() }
            }
        }
        .focused($isFocused)
        .textFieldStyle(.plain)
        .font(.bodyLg)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.medium)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.medium)
                .stroke(
                    isFocused ? Color.colorCyan500 : Color.white.opacity(0.15),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .foregroundColor(isFocused ? .black : .gray)
        .disabled(isDisabled)
    }
}

struct LoginButton: View {
    let title: String
    var icon: String? = nil
    var iconView: AnyView? = nil
    var style: LoginButtonStyle = .primary
    var isDisabled: Bool = false
    let action: () -> Void

    enum LoginButtonStyle {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            LoginButtonLabel(
                title: title,
                icon: icon,
                iconView: iconView,
                style: style,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(CleanButtonStyle())
        .disabled(isDisabled)
    }
}

private struct LoginButtonLabel: View {
    let title: String
    var icon: String?
    var iconView: AnyView?
    var style: LoginButton.LoginButtonStyle
    var isDisabled: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceXs) {
            if let iconView {
                iconView
            } else if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.bodyMd)
        .foregroundColor(textColor)
        .padding(.horizontal, SpaceTokens.spaceLg)
        .padding(.vertical, 10)
        .frame(minWidth: 140)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(bgColor)
        )
    }

    private var bgColor: Color {
        if isFocused { return .colorCyan500 }
        switch style {
        case .primary: return Color.white.opacity(0.15)
        case .secondary: return Color.white.opacity(0.1)
        }
    }

    private var textColor: Color {
        if isDisabled { return Color.white.opacity(0.4) }
        return .white
    }
}

struct LoginErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.bodySm)
            .foregroundColor(.colorRed300)
            .multilineTextAlignment(.center)
    }
}

struct LoginDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(height: 1)
    }
}
