import SwiftUI

struct CastListView: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    var onSelectPerson: (ServerPerson) -> Void
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: SpaceTokens.spaceSm) {
                Text(Strings.cast)
                    .font(.title2xl)
                    .foregroundColor(.white)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpaceTokens.spaceMd) {
                        ForEach(Array(viewModel.castMembers.enumerated()), id: \.offset) { index, person in
                            castCard(person: person, index: index)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, SpaceTokens.spaceSm)
                }
                .onAppear {
                    focusedIndex = 0
                }
            }
            .padding(.vertical, 40)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.bottom, -60)
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onExitCommand {
            viewModel.hideCastList()
        }
    }

    private func castCard(person: ServerPerson, index: Int) -> some View {
        let isFocused = focusedIndex == index

        return Button {
            onSelectPerson(person)
        } label: {
            VStack(spacing: SpaceTokens.spaceXs) {
                if let urlStr = viewModel.personImageUrl(for: person),
                   let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color(white: 0.15)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                Text(person.name)
                    .font(.bodySm)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2xs)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: 130)
            .overlay(
                RoundedRectangle(cornerRadius: RadiusTokens.small)
                    .stroke(Color.white, lineWidth: isFocused ? 2.5 : 0)
            )
        }
        .buttonStyle(PopupCardButtonStyle())
        .focused($focusedIndex, equals: index)
    }
}
