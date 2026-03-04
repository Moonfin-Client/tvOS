import SwiftUI

struct UserLoginScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme
    @StateObject private var viewModel: UserLoginViewModel

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
            theme.colorScheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: SpaceTokens.spaceLg) {
                    if let server = viewModel.server {
                        Text("Sign in to \(server.name)")
                            .font(.title2xl)
                            .foregroundColor(theme.colorScheme.onBackground)
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
                .padding(.horizontal, SpaceTokens.space3xl)
                .frame(maxWidth: 500)

                Spacer()
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
        .onDisappear {
            viewModel.stopQuickConnect()
        }
        .onChange(of: viewModel.loginState) { state in
            if state == .authenticated {
                router.switchFlow(to: .main)
            }
        }
        .onChange(of: viewModel.quickConnectState) { state in
            if state == .unavailable {
                selectedTab = .credentials
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton("Quick Connect", tab: .quickConnect)
            tabButton("Password", tab: .credentials)
        }
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(theme.colorScheme.surface)
        )
    }

    private func tabButton(_ title: String, tab: LoginTab) -> some View {
        Button {
            selectedTab = tab
            if tab == .quickConnect {
                viewModel.clearLoginState()
                viewModel.initiateQuickConnect()
            }
        } label: {
            Text(title)
                .font(.bodyMd)
                .foregroundColor(
                    selectedTab == tab
                        ? theme.colorScheme.onButtonFocused
                        : theme.colorScheme.onButton
                )
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(selectedTab == tab ? theme.colorScheme.buttonFocused : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var quickConnectTab: some View {
        VStack(spacing: SpaceTokens.spaceLg) {
            switch viewModel.quickConnectState {
            case .unknown:
                ProgressView()
                    .tint(theme.accent)
                Text("Connecting to Quick Connect...")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))

            case .unavailable:
                Text("Quick Connect is not available on this server")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))

            case .pending:
                Text("Enter this code on your server's web dashboard:")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))

                Text(viewModel.quickConnectCode)
                    .font(.token(48, weight: .bold))
                    .foregroundColor(theme.accent)
                    .tracking(4)

                ProgressView()
                    .tint(theme.accent)
                Text("Waiting for authorization...")
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))

            case .connected:
                ProgressView()
                    .tint(theme.accent)
                Text("Authorized! Signing in...")
                    .font(.bodyMd)
                    .foregroundColor(theme.accent)
            }

            loginError
        }
    }

    private var credentialsTab: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            TextField("Username", text: $viewModel.username)
                .textFieldStyle(.plain)
                .font(.bodyLg)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(SpaceTokens.spaceMd)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(theme.colorScheme.input)
                )
                .foregroundColor(theme.colorScheme.onInput)
                .disabled(viewModel.forcedUsername != nil)

            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.plain)
                .font(.bodyLg)
                .padding(SpaceTokens.spaceMd)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(theme.colorScheme.input)
                )
                .foregroundColor(theme.colorScheme.onInput)
                .onSubmit { viewModel.login() }

            if viewModel.loginState == .authenticating {
                ProgressView()
                    .tint(theme.accent)
            }

            loginError

            Button {
                viewModel.login()
            } label: {
                Text("Sign In")
                    .font(.bodyMd)
                    .foregroundColor(theme.colorScheme.onButtonFocused)
                    .padding(.horizontal, SpaceTokens.space2xl)
                    .padding(.vertical, SpaceTokens.spaceSm)
                    .background(
                        RoundedRectangle(cornerRadius: RadiusTokens.small)
                            .fill(theme.colorScheme.buttonFocused)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.loginState == .authenticating)
        }
    }

    @ViewBuilder
    private var loginError: some View {
        switch viewModel.loginState {
        case .requireSignIn:
            Text("Invalid credentials")
                .font(.bodySm)
                .foregroundColor(.colorRed300)
        case .serverUnavailable:
            Text("Server unavailable")
                .font(.bodySm)
                .foregroundColor(.colorRed300)
        case .apiClientError(let message):
            Text(message)
                .font(.bodySm)
                .foregroundColor(.colorRed300)
        case .versionNotSupported(let server):
            Text("Server version \(server.version ?? "unknown") is not supported")
                .font(.bodySm)
                .foregroundColor(.colorRed300)
        default:
            EmptyView()
        }
    }
}
