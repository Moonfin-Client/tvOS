import SwiftUI

struct ServerScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme
    @StateObject private var viewModel: ServerViewModel

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
            theme.colorScheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if let server = viewModel.server {
                    serverContent(server)
                } else {
                    Spacer()
                    ProgressView()
                        .tint(theme.accent)
                    Spacer()
                }
            }

            if viewModel.showPinEntry {
                PinEntryView(
                    mode: .verify,
                    onComplete: { pin in
                        viewModel.showPinEntry = false
                        if let pin, let user = viewModel.pinUser {
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
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.loginState) { state in
            switch state {
            case .authenticated:
                router.switchFlow(to: .main)
            case .requireSignIn:
                if let server = viewModel.server {
                    router.navigate(to: .userLogin(
                        serverId: server.id,
                        username: viewModel.pinUser?.name
                    ))
                }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func serverContent(_ server: Server) -> some View {
        ScrollView {
            VStack(spacing: SpaceTokens.spaceLg) {
                serverHeader(server)

                if let notification = viewModel.notification {
                    notificationBanner(notification)
                }

                if viewModel.users.isEmpty {
                    noUsersView
                } else {
                    userGrid
                }

                actionButtons(server)
            }
            .padding(.horizontal, SpaceTokens.space3xl)
            .padding(.vertical, SpaceTokens.spaceLg)
        }
    }

    private func serverHeader(_ server: Server) -> some View {
        VStack(spacing: SpaceTokens.spaceSm) {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: server.serverType == .jellyfin ? "server.rack" : "desktopcomputer")
                    .foregroundColor(theme.accent)
                Text(server.name)
                    .font(.title2xl)
                    .foregroundColor(theme.colorScheme.onBackground)
            }

            if let disclaimer = server.loginDisclaimer, !disclaimer.isEmpty {
                Text(disclaimer)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
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
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.3))
            Text("No users found")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
        }
        .padding(.vertical, SpaceTokens.space2xl)
    }

    private var userGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(150), spacing: SpaceTokens.spaceMd), count: min(viewModel.users.count, 6)),
            spacing: SpaceTokens.spaceLg
        ) {
            ForEach(viewModel.users.indices, id: \.self) { index in
                let user = viewModel.users[index]
                userCard(user)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func userCard(_ user: any User) -> some View {
        let imageUrl = viewModel.getUserImageUrl(user)

        Button {
            handleUserTap(user)
        } label: {
            VStack(spacing: SpaceTokens.spaceSm) {
                ZStack {
                    Circle()
                        .fill(theme.colorScheme.surface)

                    if let imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                personIcon
                            }
                        }
                        .clipShape(Circle())
                    } else {
                        personIcon
                    }
                }
                .frame(width: 130, height: 130)

                Text(user.name)
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground)
                    .lineLimit(1)
                    .frame(width: 130)
            }
        }
        .buttonStyle(.plain)
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

    private var personIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 40))
            .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
    }

    private func handleUserTap(_ user: any User) {
        if let privateUser = user as? PrivateUser, privateUser.accessToken != nil {
            viewModel.authenticate(user: user)
        } else if let publicUser = user as? PublicUser, !publicUser.hasPassword {
            viewModel.authenticate(user: user)
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
            Button {
                router.navigate(to: .userLogin(serverId: server.id, username: nil))
            } label: {
                HStack(spacing: SpaceTokens.spaceXs) {
                    Image(systemName: "person.badge.plus")
                    Text("Add User")
                }
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onButton)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(theme.colorScheme.button)
                )
            }
            .buttonStyle(.plain)

            Button {
                router.goBack()
            } label: {
                HStack(spacing: SpaceTokens.spaceXs) {
                    Image(systemName: "arrow.left")
                    Text("Change Server")
                }
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onButton)
                .padding(.horizontal, SpaceTokens.spaceLg)
                .padding(.vertical, SpaceTokens.spaceSm)
                .background(
                    RoundedRectangle(cornerRadius: RadiusTokens.small)
                        .fill(theme.colorScheme.button)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
