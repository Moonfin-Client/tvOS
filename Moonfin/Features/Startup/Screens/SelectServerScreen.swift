import SwiftUI

struct SelectServerScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @StateObject private var viewModel: SelectServerViewModel
    @StateObject private var discovery = LocalServerDiscovery()

    @State private var showDeleteAlert = false
    @State private var connectingDiscoveredId: String?

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: SelectServerViewModel(
            serverRepository: container.serverRepository
        ))
    }

    var body: some View {
        ZStack {
            LoginBackground()

            ScrollView {
                VStack(spacing: SpaceTokens.spaceLg) {
                    Spacer(minLength: 40)

                    StartupBranding()

                    LoginCard(maxWidth: 900) {
                        VStack(spacing: SpaceTokens.spaceLg) {
                            if viewModel.storedServers.isEmpty && discovery.discoveredServers.isEmpty {
                                welcomeContent
                            }

                            if !viewModel.storedServers.isEmpty {
                                savedServersContent
                            }

                            if !discovery.discoveredServers.isEmpty || discovery.isScanning {
                                discoveredServersContent
                            }

                            LoginDivider()

                            HStack(spacing: SpaceTokens.spaceMd) {
                                LoginButton(
                                    title: "Connect manually",
                                    icon: "plus",
                                    style: .secondary,
                                    action: { router.navigate(to: .serverAdd) }
                                )

                                LoginButton(
                                    title: "Emby Connect",
                                    iconView: AnyView(EmbyLogo(size: 14, color: .white)),
                                    style: .secondary,
                                    action: { router.navigate(to: .embyConnect) }
                                )
                            }
                        }
                    }

                    Text(viewModel.appVersion)
                        .font(.captionXs)
                        .foregroundColor(.white.opacity(0.4))

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            viewModel.loadServers()
            discovery.startDiscovery()
        }
        .onDisappear {
            discovery.stopDiscovery()
        }
        .alert("Delete Server", isPresented: $showDeleteAlert, presenting: viewModel.serverToDelete) { server in
            Button("Delete", role: .destructive) {
                viewModel.deleteServer(server)
                viewModel.serverToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                viewModel.serverToDelete = nil
            }
        } message: { server in
            Text("Remove \(server.name) from your saved servers?")
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Text("Welcome to Moonfin")
                .font(.title2xl)
                .foregroundColor(.white)

            Text("Connect to a Jellyfin or Emby server to get started")
                .font(.bodyMd)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private var savedServersContent: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text("Saved Servers")
                .font(.titleXl)
                .foregroundColor(.white)

            ForEach(viewModel.storedServers) { server in
                ServerRow(server: server) {
                    router.navigate(to: .serverUsers(serverId: server.id))
                } onDelete: {
                    viewModel.serverToDelete = server
                    showDeleteAlert = true
                }
            }
        }
    }

    private var discoveredServersContent: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            if !viewModel.storedServers.isEmpty {
                LoginDivider()
            }

            HStack(spacing: SpaceTokens.spaceSm) {
                Text("Discovered Servers")
                    .font(.titleXl)
                    .foregroundColor(.white)

                if discovery.isScanning {
                    ProgressView()
                        .tint(.colorCyan500)
                        .scaleEffect(0.7)
                }
            }

            let savedAddresses = Set(viewModel.storedServers.map { $0.address })
            let filtered = discovery.discoveredServers.filter { !savedAddresses.contains($0.address) }

            ForEach(filtered) { server in
                DiscoveredServerRow(
                    server: server,
                    isConnecting: connectingDiscoveredId == server.id
                ) {
                    connectDiscoveredServer(server)
                }
            }
        }
    }

    private func connectDiscoveredServer(_ server: DiscoveredServer) {
        guard connectingDiscoveredId == nil else { return }
        connectingDiscoveredId = server.id

        Task {
            for await update in container.serverRepository.addServer(address: server.address) {
                switch update {
                case .connected(let id, _):
                    connectingDiscoveredId = nil
                    router.navigate(to: .serverUsers(serverId: id))
                case .unableToConnect:
                    connectingDiscoveredId = nil
                default:
                    break
                }
            }
        }
    }
}

private struct ServerRow: View {
    let server: Server
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            ServerRowContent(server: server)
        }
        .buttonStyle(CleanButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

private struct ServerRowContent: View {
    let server: Server

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if server.serverType == .jellyfin {
                JellyfinLogo(size: 22, color: .white)
                    .frame(width: 30)
            } else {
                EmbyLogo(size: 22, color: .white)
                    .frame(width: 30)
            }

            VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
                Text(server.name)
                    .font(.bodyLg)
                    .foregroundColor(.white)

                HStack(spacing: SpaceTokens.spaceXs) {
                    Text(server.address)
                    if let version = server.version {
                        Text("•")
                        Text(version)
                    }
                }
                .font(.bodySm)
                .foregroundColor(.white.opacity(isFocused ? 0.8 : 0.5))
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

private struct DiscoveredServerRow: View {
    let server: DiscoveredServer
    let isConnecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DiscoveredServerRowContent(server: server, isConnecting: isConnecting)
        }
        .buttonStyle(CleanButtonStyle())
        .disabled(isConnecting)
    }
}

private struct DiscoveredServerRowContent: View {
    let server: DiscoveredServer
    let isConnecting: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: SpaceTokens.spaceMd) {
            if server.serverType == .jellyfin {
                JellyfinLogo(size: 22, color: .white)
                    .frame(width: 30)
            } else {
                EmbyLogo(size: 22, color: .white)
                    .frame(width: 30)
            }

            VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
                Text(server.name)
                    .font(.bodyLg)
                    .foregroundColor(.white)

                Text(server.address)
                    .font(.bodySm)
                    .foregroundColor(.white.opacity(isFocused ? 0.8 : 0.5))
            }

            Spacer()

            if isConnecting {
                ProgressView()
                    .tint(.colorCyan500)
            }
        }
        .padding(.horizontal, SpaceTokens.spaceLg)
        .padding(.vertical, SpaceTokens.spaceMd)
        .background(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .fill(isFocused ? Color.colorCyan500 : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusTokens.small)
                .stroke(isFocused ? Color.colorCyan500 : Color.white.opacity(0.1), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
