import SwiftUI

struct ServerAddScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var router: NavigationRouter
    @StateObject private var viewModel: ServerAddViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ServerAddViewModel(
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

                    LoginCard {
                        VStack(spacing: SpaceTokens.spaceLg) {
                            Text(Strings.enterServerAddress)
                                .font(.title2xl)
                                .foregroundColor(.white)

                            Text(Strings.startupEnterValidServerAddress)
                                .font(.bodyMd)
                                .foregroundColor(.white.opacity(0.7))

                            LoginTextField(
                                placeholder: Strings.startupServerAddressPlaceholder,
                                text: $viewModel.address,
                                isDisabled: viewModel.isConnecting,
                                keyboardType: .URL,
                                onSubmit: { viewModel.connect() }
                            )

                            if let error = viewModel.errorMessage {
                                LoginErrorText(message: error)
                            }

                            if viewModel.isConnecting {
                                ProgressView()
                                    .tint(.colorCyan500)
                            }

                            LoginButton(
                                title: Strings.connect,
                                isDisabled: viewModel.isConnecting || viewModel.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                action: { viewModel.connect() }
                            )

                            LoginButton(
                                title: Strings.startupChangeServer,
                                icon: "arrow.left",
                                style: .secondary,
                                action: { router.goBack() }
                            )
                        }
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: viewModel.state) { state in
            if case .connected(let id, _) = state {
                router.navigate(to: .serverUsers(serverId: id))
            }
        }
    }
}
