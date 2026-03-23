import SwiftUI

struct ServerScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @StateObject private var viewModel: ServerViewModel
    @State private var mainFlowTransitionTask: Task<Void, Never>?

    let serverId: UUID

    init(serverId: UUID, container: AppContainer) {
        self.serverId = serverId
        _viewModel = StateObject(wrappedValue: ServerViewModel(
            serverId: serverId,
            serverRepository: container.serverRepository,
            serverUserRepository: container.serverUserRepository,
            authenticationRepository: container.authenticationRepository,
            authPreferences: container.authPreferences,
            serverClientFactory: container.serverClientFactory
        ))
    }

    var body: some View {
        ZStack {
            LoginBackground()

            if let server = viewModel.server {
                serverContent(server)
            } else {
                ProgressView()
                    .tint(.colorCyan500)
            }

            if viewModel.showPinEntry {
                pinEntryOverlay
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.loginState) { state in
            switch state {
            case .authenticated:
                guard mainFlowTransitionTask == nil else { return }
                mainFlowTransitionTask = Task {
                    await container.pluginSyncService.syncOnStartup()
                    guard !Task.isCancelled else { return }
                    router.switchFlow(to: .main)
                    container.serverConnectionMonitor.startMonitoring()
                }
            case .requireSignIn:
                if let server = viewModel.server {
                    let username = viewModel.authenticatingUser?.name ?? viewModel.pinUser?.name
                    router.navigate(to: .userLogin(
                        serverId: server.id,
                        username: username
                    ))
                }
            default:
                break
            }
        }
        .onDisappear {
            mainFlowTransitionTask?.cancel()
            mainFlowTransitionTask = nil
        }
    }

    private var pinEntryOverlay: some View {
        PinEntryView(
            mode: .verify,
            onComplete: {
                viewModel.showPinEntry = false
                if $0 != nil, let user = viewModel.pinUser {
                    viewModel.authenticate(user: user)
                }
                viewModel.pinUser = nil
            },
            onForgotPin: {
                viewModel.showPinEntry = false
                if let user = viewModel.pinUser, let server = viewModel.server {
                    router.navigate(to: .userLogin(
                        serverId: server.id,
                        username: user.name
                    ))
                }
                viewModel.pinUser = nil
            }
        )
    }

    @ViewBuilder
    private func serverContent(_ server: Server) -> some View {
        ScrollView {
            VStack(spacing: SpaceTokens.spaceLg) {
                Spacer(minLength: 40)

                StartupBranding()

                LoginCard(maxWidth: 900) {
                    VStack(spacing: SpaceTokens.spaceLg) {
                        serverHeader(server)

                        if let notification = viewModel.notification {
                            notificationBanner(notification)
                        }

                        LoginDivider()

                        Text("Who's watching?")
                            .font(.titleXl)
                            .foregroundColor(.white.opacity(0.7))

                        if viewModel.users.isEmpty {
                            noUsersView
                        } else {
                            userGrid
                        }

                        LoginDivider()

                        actionButtons(server)
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func serverHeader(_ server: Server) -> some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            HStack(spacing: SpaceTokens.spaceSm) {
                if server.serverType == .jellyfin {
                    JellyfinLogo(size: 28, color: .white)
                } else {
                    EmbyLogo(size: 28, color: .white)
                }
                Text(server.name)
                    .font(.title2xl)
                    .foregroundColor(.white)
            }

            if let disclaimer = server.loginDisclaimer, !disclaimer.isEmpty {
                Text(disclaimer)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func notificationBanner(_ message: String) -> some View {
        Text(message)
            .font(.bodySm)
            .foregroundColor(.colorRed25)
            .padding(SpaceTokens.spaceMd)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(Color.colorRed300.opacity(0.2))
            )
    }

    private var noUsersView: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "person.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("No users found")
                .font(.bodyMd)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, SpaceTokens.space2xl)
    }

    private var userGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SpaceTokens.spaceLg) {
                ForEach(viewModel.users.indices, id: \.self) { index in
                    let user = viewModel.users[index]
                    userCard(user)
                }
            }
            .padding(.horizontal, SpaceTokens.spaceMd)
            .padding(.vertical, SpaceTokens.spaceSm)
        }
        .focusSection()
    }

    @ViewBuilder
    private func userCard(_ user: any User) -> some View {
        let imageUrl = viewModel.getUserImageUrl(user)
        let url = imageUrl.flatMap { URL(string: $0) }

        Button {
            handleUserTap(user)
        } label: {
            UserCardContent(imageUrl: url, name: user.name)
        }
        .buttonStyle(CleanButtonStyle())
        .contextMenu {
            if let privateUser = user as? PrivateUser {
                if privateUser.accessToken != nil {
                    Button {
                        viewModel.logoutUser(user)
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Button(role: .destructive) {
                    viewModel.deleteUser(privateUser)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func handleUserTap(_ user: any User) {
        if let privateUser = user as? PrivateUser, privateUser.accessToken != nil {
            viewModel.authenticate(user: user)
        } else if let publicUser = user as? PublicUser, !publicUser.hasPassword {
            viewModel.loginWithoutPassword(user: user)
        } else {
            if let server = viewModel.server {
                router.navigate(to: .userLogin(
                    serverId: server.id,
                    username: user.name
                ))
            }
        }
    }

    private func actionButtons(_ server: Server) -> some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            LoginButton(
                title: "Add User",
                icon: "person.badge.plus",
                style: .secondary,
                action: { router.navigate(to: .userLogin(serverId: server.id, username: nil)) }
            )

            LoginButton(
                title: "Change Server",
                icon: "arrow.left",
                style: .secondary,
                action: { router.goBack() }
            )
        }
    }
}

private struct UserCardContent: View {
    let imageUrl: URL?
    let name: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Circle().stroke(
                            isFocused ? Color.colorCyan500 : Color.white.opacity(0.15),
                            lineWidth: isFocused ? 3 : 1
                        )
                    )

                if let imageUrl {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .clipShape(Circle())
                        default:
                            personIcon
                        }
                    }
                } else {
                    personIcon
                }
            }
            .frame(width: 130, height: 130)

            Text(name)
                .font(.bodySm)
                .foregroundColor(isFocused ? .colorCyan500 : .white)
                .lineLimit(1)
                .frame(width: 130)
        }
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var personIcon: some View {
        PersonAvatarShape()
            .fill(Color.white)
            .frame(width: 56, height: 56)
    }
}
