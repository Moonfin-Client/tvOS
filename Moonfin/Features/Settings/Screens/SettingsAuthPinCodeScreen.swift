import SwiftUI
import CryptoKit

struct SettingsAuthPinCodeScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var theme: MoonfinTheme

    private var prefs: UserPreferences { container.userPreferences }
    private var hasPinSet: Bool { !prefs[UserPreferences.userPinHash].isEmpty }

    @State private var showPinEntry = false
    @State private var pinFlow: PinFlow?

    enum PinFlow {
        case set
        case changeVerify
        case changeSet
        case removeVerify
    }

    var body: some View {
        SettingsScreenLayout(title: "PIN Code") {
            if hasPinSet {
                SettingsToggleButton(
                    icon: "lock.shield",
                    heading: "PIN Code Enabled",
                    caption: "Require PIN to access the app",
                    isOn: prefs.binding(for: UserPreferences.userPinEnabled)
                )

                Button(action: { startFlow(.changeVerify) }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Change PIN")
                    }
                    .font(.bodyMd)
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .buttonStyle(CleanButtonStyle())

                Button(action: { startFlow(.removeVerify) }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove PIN")
                    }
                    .font(.bodyMd)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .buttonStyle(CleanButtonStyle())
            } else {
                Text("No PIN is currently set. Set a PIN to protect access to the app.")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.listCaption)
                    .padding(.bottom, SpaceTokens.spaceSm)

                Button(action: { startFlow(.set) }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Set PIN")
                    }
                    .font(.bodyMd)
                    .foregroundColor(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
        .overlay {
            if showPinEntry {
                PinEntryView(
                    mode: pinEntryMode,
                    onComplete: handlePinResult
                )
            }
        }
    }

    private var pinEntryMode: PinEntryView.Mode {
        switch pinFlow {
        case .set, .changeSet:
            return .set
        case .changeVerify, .removeVerify:
            return .verify
        case .none:
            return .verify
        }
    }

    private func startFlow(_ flow: PinFlow) {
        pinFlow = flow
        showPinEntry = true
    }

    private func handlePinResult(_ pin: String?) {
        showPinEntry = false
        guard let pin else { return }

        switch pinFlow {
        case .set:
            prefs[UserPreferences.userPinHash] = hashPin(pin)
            prefs[UserPreferences.userPinEnabled] = true

        case .changeVerify:
            if hashPin(pin) == prefs[UserPreferences.userPinHash] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startFlow(.changeSet)
                }
            }

        case .changeSet:
            prefs[UserPreferences.userPinHash] = hashPin(pin)

        case .removeVerify:
            if hashPin(pin) == prefs[UserPreferences.userPinHash] {
                prefs[UserPreferences.userPinHash] = ""
                prefs[UserPreferences.userPinEnabled] = false
            }

        case .none:
            break
        }
    }

    private func hashPin(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
