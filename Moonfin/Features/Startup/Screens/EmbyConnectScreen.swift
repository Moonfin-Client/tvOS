import SwiftUI

struct EmbyConnectScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @StateObject private var viewModel: EmbyConnectViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: EmbyConnectViewModel(
            serverRepository: container.serverRepository,
            authenticationStore: container.authenticationStore
        ))
    }

    var body: some View {
        ZStack {
            LoginBackground()

            ScrollView {
                VStack(spacing: SpaceTokens.spaceLg) {
                    Spacer(minLength: 40)

                    StartupBranding()

                    LoginCard {
                        VStack(spacing: SpaceTokens.spaceLg) {
                            headerView

                            switch viewModel.phase {
                            case .credentials:
                                credentialsView
                            case .authenticating, .loadingServers:
                                loadingView(Strings.embyConnectSigningIn)
                            case .serverList:
                                serverListView
                            case .connectingToServer:
                                loadingView(Strings.embyConnectConnectingToServer)
                            case .error(let message):
                                errorView(message)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: viewModel.connectedServerId) { serverId in
            if let serverId {
                router.navigate(to: .serverUsers(serverId: serverId))
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: SpaceTokens.spaceXs) {
            HStack(spacing: SpaceTokens.spaceSm) {
                EmbyLogo(size: 28, color: .white)
                Text(Strings.embyConnect)
                    .font(.title2xl)
                    .foregroundColor(.white)
            }

            Text(Strings.embyConnectSignInDescription)
                .font(.bodyMd)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var credentialsView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            LoginTextField(
                placeholder: Strings.embyConnectEmailOrUsername,
                text: $viewModel.username,
                keyboardType: .emailAddress
            )

            LoginTextField(
                placeholder: Strings.passwordField,
                text: $viewModel.password,
                isSecure: true,
                onSubmit: { viewModel.login() }
            )

            LoginButton(
                title: Strings.actionLogin,
                action: { viewModel.login() }
            )
        }
    }

    private func loadingView(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            ProgressView()
                .tint(.colorCyan500)
            Text(message)
                .font(.bodyMd)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, SpaceTokens.spaceLg)
    }

    private var serverListView: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceMd) {
            Text(Strings.selectServer)
                .font(.titleXl)
                .foregroundColor(.white)

            ForEach(viewModel.servers) { server in
                Button {
                    viewModel.selectServer(server)
                } label: {
                    ConnectServerRowContent(server: server)
                }
                .buttonStyle(CleanButtonStyle())
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            LoginErrorText(message: message)

            LoginButton(
                title: Strings.startupTryAgain,
                style: .secondary,
                action: { viewModel.clearError() }
            )
        }
    }
}

private struct ConnectServerRowContent: View {
    let server: EmbyConnectServer

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            EmbyLogo(size: 22, color: .white)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
                Text(server.name)
                    .font(.bodyLg)
                    .foregroundColor(.white)

                if let address = server.bestAddress {
                    Text(address)
                        .font(.bodySm)
                        .foregroundColor(.white.opacity(isFocused ? 0.8 : 0.5))
                }
            }

            Spacer()
        }
        .padding(.horizontal, SpaceTokens.spaceLg)
        .padding(.vertical, SpaceTokens.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(isFocused ? Color.colorCyan500 : Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .stroke(isFocused ? Color.colorCyan500 : Color.white.opacity(0.15), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
