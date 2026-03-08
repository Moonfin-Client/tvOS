import SwiftUI

enum ActionButtonID: Hashable {
    case resume, play, shuffle, instantMix, nextEpisode, watched, favorite, goToSeries
}

struct ActionButtonsRow: View {
    let isFavorite: Bool
    let isPlayed: Bool
    let canResume: Bool
    let resumePositionText: String?
    var focusedButton: FocusState<ActionButtonID?>.Binding

    let onPlay: () -> Void
    let onResume: () -> Void
    let onToggleWatched: () -> Void
    let onToggleFavorite: () -> Void
    let onGoToSeries: (() -> Void)?
    let onNextEpisode: (() -> Void)?
    let onShuffle: (() -> Void)?
    let onInstantMix: (() -> Void)?

    var body: some View {
        HStack {
            Spacer()
            HStack(alignment: .top, spacing: SpaceTokens.spaceMd) {
                if canResume {
                    ActionButton(
                        label: "Resume",
                        icon: "play.fill",
                        detail: resumePositionText.map { "at \($0)" },
                        action: onResume
                    )
                    .focused(focusedButton, equals: .resume)
                }

                ActionButton(
                    label: canResume ? "Restart" : "Play",
                    icon: canResume ? "arrow.counterclockwise" : "play.fill",
                    action: onPlay
                )
                .focused(focusedButton, equals: .play)

                if let onShuffle {
                    ActionButton(
                        label: "Shuffle",
                        icon: "shuffle",
                        action: onShuffle
                    )
                    .focused(focusedButton, equals: .shuffle)
                }

                if let onInstantMix {
                    ActionButton(
                        label: "Instant Mix",
                        icon: "wand.and.stars",
                        action: onInstantMix
                    )
                    .focused(focusedButton, equals: .instantMix)
                }

                if let onNextEpisode {
                    ActionButton(
                        label: "Next",
                        icon: "forward.fill",
                        action: onNextEpisode
                    )
                    .focused(focusedButton, equals: .nextEpisode)
                }

                ActionButton(
                    label: isPlayed ? "Watched" : "Unwatched",
                    icon: "checkmark",
                    isActive: isPlayed,
                    activeColor: Color(hex: 0x2196F3),
                    action: onToggleWatched
                )
                .focused(focusedButton, equals: .watched)

                ActionButton(
                    label: isFavorite ? "Favorited" : "Favorite",
                    icon: isFavorite ? "heart.fill" : "heart",
                    isActive: isFavorite,
                    activeColor: Color(hex: 0xFF4757),
                    action: onToggleFavorite
                )
                .focused(focusedButton, equals: .favorite)

                if let onGoToSeries {
                    ActionButton(
                        label: "Go to Series",
                        icon: "tv",
                        action: onGoToSeries
                    )
                    .focused(focusedButton, equals: .goToSeries)
                }
            }
            Spacer()
        }
        .focusSection()
    }
}

private struct ActionButton: View {
    let label: String
    let icon: String
    var detail: String? = nil
    var isActive: Bool = false
    var activeColor: Color? = nil
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpaceTokens.spaceXs) {
                ZStack {
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: RadiusTokens.large)
                                .stroke(borderColor, lineWidth: isFocused ? 3 : 1)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor)
                }
                .frame(width: 72, height: 72)

                Text(label)
                    .font(.captionXs)
                    .fontWeight(.semibold)
                    .foregroundColor(isFocused ? .white : theme.colorScheme.onBackground.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detail {
                    Text(detail)
                        .font(.caption2xs)
                        .foregroundColor(isFocused ? .white.opacity(0.7) : theme.colorScheme.onBackground.opacity(0.5))
                        .lineLimit(isFocused ? 2 : 1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 80)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var backgroundColor: Color {
        if isFocused {
            return .white
        }
        if isActive {
            return theme.colorScheme.buttonActive
        }
        return theme.colorScheme.button
    }

    private var borderColor: Color {
        if isFocused {
            return .clear
        }
        return Color.white.opacity(0.15)
    }

    private var iconColor: Color {
        if isFocused {
            return Color(white: 0.3)
        }
        if isActive, let activeColor {
            return activeColor
        }
        return theme.colorScheme.onButton
    }
}
