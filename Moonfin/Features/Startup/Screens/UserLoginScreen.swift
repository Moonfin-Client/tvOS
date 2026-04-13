import SwiftUI

struct UserLoginScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @StateObject private var viewModel: UserLoginViewModel
    @State private var mainFlowTransitionTask: Task<Void, Never>?

    @State private var selectedTab: LoginTab = .credentials

    enum LoginTab {
        case quickConnect
        case credentials
    }

    let serverId: UUID
    let username: String?

    init(serverId: UUID, username: String?, container: AppContainer) {
        self.serverId = serverId
        self.username = username
        _viewModel = StateObject(wrappedValue: UserLoginViewModel(
            serverId: serverId,
            username: username,
            serverRepository: container.serverRepository,
            authenticationRepository: container.authenticationRepository,
            serverClientFactory: container.serverClientFactory
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
                            if let server = viewModel.server {
                                VStack(spacing: SpaceTokens.spaceXs) {
                                    Text(Strings.actionLogin)
                                        .font(.title2xl)
                                        .foregroundColor(.white)

                                    Text(Strings.connectingTo(server.name))
                                        .font(.bodyMd)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }

                            if viewModel.isQuickConnectSupported {
                                tabSelector
                            }

                            switch selectedTab {
                            case .quickConnect:
                                quickConnectTab
                            case .credentials:
                                credentialsTab
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !viewModel.isQuickConnectSupported {
                selectedTab = .credentials
            } else {
                selectedTab = .quickConnect
                viewModel.initiateQuickConnect()
            }
        }
        .onChange(of: viewModel.server != nil) { serverLoaded in
            if serverLoaded, selectedTab == .quickConnect, viewModel.quickConnectState == .unknown {
                viewModel.initiateQuickConnect()
            }
        }
        .onDisappear {
            viewModel.stopQuickConnect()
            mainFlowTransitionTask?.cancel()
            mainFlowTransitionTask = nil
        }
        .onChange(of: viewModel.loginState) { state in
            if state == .authenticated {
                guard mainFlowTransitionTask == nil else { return }
                mainFlowTransitionTask = Task {
                    router.switchFlow(to: .main)
                    container.serverConnectionMonitor.startMonitoring()
                    Task { await container.pluginSyncService.syncOnStartup() }
                }
            }
        }
        .onChange(of: viewModel.quickConnectState) { state in
            if state == .unavailable {
                selectedTab = .credentials
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            tabButton(Strings.useQuickConnect, tab: .quickConnect)
            tabButton(Strings.usePassword, tab: .credentials)
        }
    }

    private func tabButton(_ title: String, tab: LoginTab) -> some View {
        Button {
            selectedTab = tab
            if tab == .quickConnect {
                viewModel.clearLoginState()
                viewModel.initiateQuickConnect()
            }
        } label: {
            TabButtonLabel(title: title, isSelected: selectedTab == tab)
        }
        .buttonStyle(CleanButtonStyle())
    }

    private var quickConnectTab: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            switch viewModel.quickConnectState {
            case .unknown:
                ProgressView()
                    .tint(.colorCyan500)
                Text(Strings.loginQuickConnectConnecting)
                    .font(.bodyMd)
                    .foregroundColor(.white.opacity(0.6))

            case .unavailable:
                Text(Strings.loginQuickConnectUnavailable)
                    .font(.bodyMd)
                    .foregroundColor(.white.opacity(0.6))

            case .pending:
                Text(Strings.loginQuickConnectEnterCode)
                    .font(.bodyMd)
                    .foregroundColor(.white.opacity(0.6))

                Text(viewModel.quickConnectCode)
                    .font(.token(48, weight: .bold))
                    .foregroundColor(.colorCyan500)
                    .tracking(4)

                ProgressView()
                    .tint(.colorCyan500)
                Text(Strings.loginQuickConnectWaiting)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.4))

            case .connected:
                ProgressView()
                    .tint(.colorCyan500)
                Text(Strings.loginQuickConnectAuthorized)
                    .font(.bodyMd)
                    .foregroundColor(.colorCyan500)
            }

            loginError
        }
    }

    private var credentialsTab: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            if viewModel.forcedUsername == nil {
                LoginTextField(
                    placeholder: Strings.usernameField,
                    text: $viewModel.username
                )
            }

            LoginTextField(
                placeholder: Strings.passwordField,
                text: $viewModel.password,
                isSecure: true,
                onSubmit: { viewModel.login() }
            )

            if viewModel.loginState == .authenticating {
                ProgressView()
                    .tint(.colorCyan500)
            }

            loginError

            LoginButton(
                title: Strings.actionLogin,
                isDisabled: viewModel.loginState == .authenticating,
                action: { viewModel.login() }
            )
        }
    }

    @ViewBuilder
    private var loginError: some View {
        switch viewModel.loginState {
        case .requireSignIn:
            LoginErrorText(message: Strings.invalidCredentials)
        case .serverUnavailable:
            LoginErrorText(message: Strings.serverUnavailable)
        case .apiClientError(let message):
            LoginErrorText(message: message)
        case .versionNotSupported(let server):
            LoginErrorText(message: Strings.serverUnsupportedVersion(server.version ?? Strings.unknown))
        default:
            EmptyView()
        }
    }
}

private struct TabButtonLabel: View {
    let title: String
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(.bodyMd)
            .foregroundColor(.white)
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceSm)
            .frame(minWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(isFocused ? Color.colorCyan500 : isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(isSelected ? Color.colorCyan500 : Color.clear, lineWidth: 2)
            )
    }
}
