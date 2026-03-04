import SwiftUI

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

    private let columns = [
        GridItem(.fixed(80), spacing: SpaceTokens.spaceSm),
        GridItem(.fixed(80), spacing: SpaceTokens.spaceSm),
        GridItem(.fixed(80), spacing: SpaceTokens.spaceSm),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onComplete(nil) }

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
                        Text("Forgot PIN?")
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
    }

    private var title: String {
        switch mode {
        case .set:
            return isConfirming ? "Confirm PIN" : "Enter New PIN"
        case .verify:
            return "Enter PIN"
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
            LazyVGrid(columns: columns, spacing: SpaceTokens.spaceSm) {
                ForEach(1...9, id: \.self) { digit in
                    keypadButton("\(digit)") { appendDigit("\(digit)") }
                }

                keypadButton("Clear", systemImage: "delete.left") { deleteDigit() }
                keypadButton("0") { appendDigit("0") }
                keypadButton("OK", systemImage: "checkmark") { submit() }
            }
        }
    }

    private func keypadButton(_ label: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.titleXl)
                } else {
                    Text(label)
                        .font(.title2xl)
                }
            }
            .foregroundColor(theme.colorScheme.onButton)
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(theme.colorScheme.button)
            )
        }
        .buttonStyle(.plain)
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
                    errorMessage = "PIN must be at least \(minLength) digits"
                    return
                }
                isConfirming = true
            } else {
                if confirmPin == pin {
                    onComplete(confirmPin)
                } else {
                    errorMessage = "PINs don't match"
                    confirmPin = ""
                }
            }
        }
    }
}
