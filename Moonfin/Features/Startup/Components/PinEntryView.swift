import SwiftUI

private struct PinPadButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: isFocused ? .white.opacity(0.35) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.14), value: isFocused)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct PinEntryView: View {
    enum Mode {
        case set
        case verify
    }

    let mode: Mode
    let onComplete: (String?) -> Void
    var onForgotPin: (() -> Void)? = nil

    @EnvironmentObject var theme: MoonfinTheme

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isConfirming = false
    @State private var errorMessage: String?

    private let maxLength = 10
    private let minLength = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: SpaceTokens.spaceLg) {
                Text(title)
                    .font(.titleXl)
                    .foregroundColor(theme.colorScheme.onBackground)

                pinDisplay

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodySm)
                        .foregroundColor(.colorRed300)
                }

                numericKeypad

                if let onForgotPin, mode == .verify {
                    Button {
                        onForgotPin()
                    } label: {
                        Text(Strings.forgotPin)
                            .font(.bodySm)
                            .foregroundColor(theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SpaceTokens.space2xl)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.large)
                    .fill(theme.colorScheme.surface)
            )
        }
        .onExitCommand {
            onComplete(nil)
        }
    }

    private var title: String {
        switch mode {
        case .set:
            return isConfirming ? Strings.confirmPin : Strings.enterNewPin
        case .verify:
            return Strings.enterPin
        }
    }

    private var currentPin: String {
        isConfirming ? confirmPin : pin
    }

    private var pinDisplay: some View {
        HStack(spacing: SpaceTokens.spaceSm) {
            ForEach(0..<maxLength, id: \.self) { index in
                Circle()
                    .fill(index < currentPin.count
                        ? theme.accent
                        : theme.colorScheme.onBackground.opacity(0.2))
                    .frame(width: 12, height: 12)
            }
        }
    }

    private var numericKeypad: some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            HStack(spacing: SpaceTokens.spaceSm) {
                keypadButton(label: "1", systemImage: nil) { appendDigit("1") }
                keypadButton(label: "2", systemImage: nil) { appendDigit("2") }
                keypadButton(label: "3", systemImage: nil) { appendDigit("3") }
            }
            HStack(spacing: SpaceTokens.spaceSm) {
                keypadButton(label: "4", systemImage: nil) { appendDigit("4") }
                keypadButton(label: "5", systemImage: nil) { appendDigit("5") }
                keypadButton(label: "6", systemImage: nil) { appendDigit("6") }
            }
            HStack(spacing: SpaceTokens.spaceSm) {
                keypadButton(label: "7", systemImage: nil) { appendDigit("7") }
                keypadButton(label: "8", systemImage: nil) { appendDigit("8") }
                keypadButton(label: "9", systemImage: nil) { appendDigit("9") }
            }
            HStack(spacing: SpaceTokens.spaceSm) {
                keypadButton(label: "", systemImage: "delete.left") { deleteDigit() }
                keypadButton(label: "0", systemImage: nil) { appendDigit("0") }
                keypadButton(label: "", systemImage: "checkmark") { submit() }
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func keypadButton(
        label: String,
        systemImage: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.titleXl)
                } else {
                    Text(label)
                        .font(.title2xl)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(theme.colorScheme.onButton)
            .frame(width: 84, height: 64)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(theme.colorScheme.button)
            )
        }
        .buttonStyle(PinPadButtonStyle())
    }

    private func appendDigit(_ digit: String) {
        errorMessage = nil
        if isConfirming {
            guard confirmPin.count < maxLength else { return }
            confirmPin += digit
        } else {
            guard pin.count < maxLength else { return }
            pin += digit
        }
    }

    private func deleteDigit() {
        errorMessage = nil
        if isConfirming {
            if !confirmPin.isEmpty { confirmPin.removeLast() }
        } else {
            if !pin.isEmpty { pin.removeLast() }
        }
    }

    private func submit() {
        switch mode {
        case .verify:
            guard !pin.isEmpty else { return }
            onComplete(pin)

        case .set:
            if !isConfirming {
                guard pin.count >= minLength else {
                    errorMessage = Strings.pinTooShort(minLength)
                    return
                }
                isConfirming = true
            } else {
                if confirmPin == pin {
                    onComplete(confirmPin)
                } else {
                    errorMessage = Strings.pinMismatch
                    confirmPin = ""
                }
            }
        }
    }
}
