import SwiftUI

enum ActionButtonID: Hashable {
    case resume, play, shuffle, instantMix, nextEpisode, selectVersion
    case audioTrack, subtitleTrack, trailer, watched, favorite, addToPlaylist, goToSeries, delete
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
    let onShuffle: (() -> Void)?
    let onInstantMix: (() -> Void)?
    let onNextEpisode: (() -> Void)?
    let onSelectVersion: (() -> Void)?
    let onAudioTrack: (() -> Void)?
    let onSubtitleTrack: (() -> Void)?
    let onTrailer: (() -> Void)?
    let onGoToSeries: (() -> Void)?
    let onAddToPlaylist: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: SpaceTokens.space3xl) {
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
                    isAssetIcon: true,
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

            if let onSelectVersion {
                ActionButton(
                    label: "Version",
                    icon: "film.stack",
                    action: onSelectVersion
                )
                .focused(focusedButton, equals: .selectVersion)
            }

            if let onAudioTrack {
                ActionButton(
                    label: "Audio",
                    icon: "speaker.wave.2",
                    action: onAudioTrack
                )
                .focused(focusedButton, equals: .audioTrack)
            }

            if let onSubtitleTrack {
                ActionButton(
                    label: "Subtitles",
                    icon: "captions.bubble",
                    action: onSubtitleTrack
                )
                .focused(focusedButton, equals: .subtitleTrack)
            }

            if let onTrailer {
                ActionButton(
                    label: "Trailer",
                    icon: "film",
                    action: onTrailer
                )
                .focused(focusedButton, equals: .trailer)
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

            if let onAddToPlaylist {
                ActionButton(
                    label: "Add to List",
                    icon: "text.badge.plus",
                    action: onAddToPlaylist
                )
                .focused(focusedButton, equals: .addToPlaylist)
            }

            if let onGoToSeries {
                ActionButton(
                    label: "Go to Series",
                    icon: "tv",
                    action: onGoToSeries
                )
                .focused(focusedButton, equals: .goToSeries)
            }

            if let onDelete {
                ActionButton(
                    label: "Delete",
                    icon: "trash",
                    action: onDelete
                )
                .focused(focusedButton, equals: .delete)
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }
}

private struct ActionButton: View {
    let label: String
    let icon: String
    var isAssetIcon: Bool = false
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
                        .fill(baseGlassTint)
                        .background(
                            RoundedRectangle(cornerRadius: RadiusTokens.large)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: RadiusTokens.large)
                                .stroke(glassBorderColor, lineWidth: isFocused ? 2.5 : 1)
                        )

                    if isAssetIcon {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .foregroundColor(iconColor)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(iconColor)
                    }
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

    private var baseGlassTint: Color {
        if isFocused {
            return Color.white.opacity(0.26)
        }
        if isActive {
            return (activeColor ?? theme.colorScheme.buttonActive).opacity(0.22)
        }
        return theme.colorScheme.button.opacity(0.22)
    }

    private var glassBorderColor: Color {
        if isFocused {
            return .white.opacity(0.95)
        }
        return Color.white.opacity(0.28)
    }

    private var iconColor: Color {
        if isFocused {
            return .white
        }
        if isActive, let activeColor {
            return activeColor
        }
        return theme.colorScheme.onButton
    }
}
