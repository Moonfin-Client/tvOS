import SwiftUI

struct ServerAddScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @EnvironmentObject var theme: MoonfinTheme
    @StateObject private var viewModel: ServerAddViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ServerAddViewModel(
            serverRepository: container.serverRepository
        ))
    }

    var body: some View {
        ZStack {
            theme.colorScheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: SpaceTokens.spaceLg) {
                    Text("Add Server")
                        .font(.title2xl)
                        .foregroundColor(theme.colorScheme.onBackground)

                    Text("Enter your Jellyfin or Emby server address")
                        .font(.bodyMd)
                        .foregroundColor(theme.colorScheme.onBackground.opacity(0.6))

                    TextField("https://your-server.com", text: $viewModel.address)
                        .textFieldStyle(.plain)
                        .font(.bodyLg)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(SpaceTokens.spaceMd)
                        .background(
                            RoundedRectangle(cornerRadius: RadiusTokens.small)
                                .fill(theme.colorScheme.input)
                        )
                        .foregroundColor(theme.colorScheme.onInput)
                        .disabled(viewModel.isConnecting)
                        .frame(maxWidth: 500)
                        .onSubmit { viewModel.connect() }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.bodySm)
                            .foregroundColor(.colorRed300)
                            .multilineTextAlignment(.center)
                    }

                    if viewModel.isConnecting {
                        ProgressView()
                            .tint(theme.accent)
                    }

                    Button {
                        viewModel.connect()
                    } label: {
                        Text("Connect")
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
                    .disabled(viewModel.isConnecting || viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, SpaceTokens.space3xl)

                Spacer()
            }
        }
        .onChange(of: viewModel.state) { state in
            if case .connected(let id, _) = state {
                router.navigate(to: .serverUsers(serverId: id))
            }
        }
    }
}
