import SwiftUI

struct SelectServerScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme
    @StateObject private var viewModel: SelectServerViewModel

    @State private var showDeleteAlert = false

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: SelectServerViewModel(
            serverRepository: container.serverRepository
        ))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: SpaceTokens.spaceLg) {
                        if viewModel.storedServers.isEmpty {
                            welcomeSection
                        }

                        if !viewModel.storedServers.isEmpty {
                            storedServersSection
                        }

                        addServerButton

                        Spacer(minLength: SpaceTokens.spaceLg)

                        Text(viewModel.appVersion)
                            .font(.captionXs)
                            .foregroundColor(theme.colorScheme.onBackground.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, SpaceTokens.space3xl)
                    .padding(.vertical, SpaceTokens.spaceLg)
                }
            }
        }
        .onAppear { viewModel.loadServers() }
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

    private var welcomeSection: some View {
        VStack(spacing: SpaceTokens.spaceMd) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(theme.accent)

            Text("Welcome to Moonfin")
                .font(.title2xl)
                .foregroundColor(theme.colorScheme.onBackground)

            Text("Connect to a Jellyfin or Emby server to get started")
                .font(.bodyMd)
                .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpaceTokens.space2xl)
    }

    private var storedServersSection: some View {
        VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
            Text("Your Servers")
                .font(.titleXl)
                .foregroundColor(theme.colorScheme.onBackground)

            ForEach(viewModel.storedServers) { server in
                ServerRow(server: server, theme: theme) {
                    router.navigate(to: .serverUsers(serverId: server.id))
                } onDelete: {
                    viewModel.serverToDelete = server
                    showDeleteAlert = true
                }
            }
        }
    }

    private var addServerButton: some View {
        Button {
            router.navigate(to: .serverAdd)
        } label: {
            HStack(spacing: SpaceTokens.spaceSm) {
                Image(systemName: "plus")
                Text("Enter server address")
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
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ServerRow: View {
    let server: Server
    let theme: MoonfinTheme
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SpaceTokens.spaceMd) {
                Image(systemName: server.serverType == .jellyfin ? "server.rack" : "desktopcomputer")
                    .font(.bodyLg)
                    .foregroundColor(theme.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: SpaceTokens.space2xs) {
                    Text(server.name)
                        .font(.bodyLg)
                        .foregroundColor(theme.colorScheme.onBackground)

                    HStack(spacing: SpaceTokens.spaceXs) {
                        Text(server.address)
                        if let version = server.version {
                            Text("•")
                            Text(version)
                        }
                    }
                    .font(.bodySm)
                    .foregroundColor(theme.colorScheme.onBackground.opacity(0.5))
                }

                Spacer()
            }
            .padding(.horizontal, SpaceTokens.spaceLg)
            .padding(.vertical, SpaceTokens.spaceMd)
            .background(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .fill(theme.colorScheme.surface)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
