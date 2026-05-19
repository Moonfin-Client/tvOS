import SwiftUI

enum ActionButtonID: Hashable {
    case resume, play, shuffle, instantMix, nextEpisode, selectVersion
    case audioTrack, subtitleTrack, downloadSubtitles, trailer, watched, favorite, addToPlaylist, goToSeries, delete
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
    let onDownloadSubtitles: (() -> Void)?
    let onTrailer: (() -> Void)?
    let onGoToSeries: (() -> Void)?
    let onAddToPlaylist: (() -> Void)?
    let onDelete: (() -> Void)?

    private struct ButtonConfig: Identifiable {
        let id: ActionButtonID
        let label: String
        let icon: String
        var isAssetIcon: Bool = false
        var detail: String? = nil
        var isActive: Bool = false
        var activeColor: Color? = nil
        let action: () -> Void
    }

    private var buttonConfigs: [ButtonConfig] {
        var buttons: [ButtonConfig] = []

        if canResume {
            buttons.append(ButtonConfig(
                id: .resume,
                label: Strings.resume,
                icon: "play.fill",
                detail: resumePositionText.map { "at \($0)" },
                action: onResume
            ))
        }

        buttons.append(ButtonConfig(
            id: .play,
            label: canResume ? Strings.restart : Strings.play,
            icon: canResume ? "arrow.counterclockwise" : "play.fill",
            action: onPlay
        ))

        if let onShuffle {
            buttons.append(ButtonConfig(
                id: .shuffle,
                label: Strings.shuffle,
                icon: "shuffle",
                isAssetIcon: true,
                action: onShuffle
            ))
        }

        if let onInstantMix {
            buttons.append(ButtonConfig(
                id: .instantMix,
                label: Strings.instantMix,
                icon: "wand.and.stars",
                action: onInstantMix
            ))
        }

        if let onNextEpisode {
            buttons.append(ButtonConfig(
                id: .nextEpisode,
                label: Strings.nextShort,
                icon: "forward.fill",
                action: onNextEpisode
            ))
        }

        if let onSelectVersion {
            buttons.append(ButtonConfig(
                id: .selectVersion,
                label: Strings.versionAction,
                icon: "film.stack",
                action: onSelectVersion
            ))
        }

        if let onAudioTrack {
            buttons.append(ButtonConfig(
                id: .audioTrack,
                label: Strings.audioAction,
                icon: "speaker.wave.2",
                action: onAudioTrack
            ))
        }

        if let onSubtitleTrack {
            buttons.append(ButtonConfig(
                id: .subtitleTrack,
                label: Strings.subtitlesAction,
                icon: "captions.bubble",
                action: onSubtitleTrack
            ))
        }

        if let onDownloadSubtitles {
            buttons.append(ButtonConfig(
                id: .downloadSubtitles,
                label: Strings.getSubs,
                icon: "square.and.arrow.down",
                action: onDownloadSubtitles
            ))
        }

        if let onTrailer {
            buttons.append(ButtonConfig(
                id: .trailer,
                label: Strings.trailer,
                icon: "film",
                action: onTrailer
            ))
        }

        buttons.append(ButtonConfig(
            id: .watched,
            label: isPlayed ? Strings.watched : Strings.unwatched,
            icon: "checkmark",
            isActive: isPlayed,
            activeColor: Color(hex: 0x2196F3),
            action: onToggleWatched
        ))

        buttons.append(ButtonConfig(
            id: .favorite,
            label: isFavorite ? Strings.favorited : Strings.favorite,
            icon: isFavorite ? "heart.fill" : "heart",
            isActive: isFavorite,
            activeColor: Color(hex: 0xFF4757),
            action: onToggleFavorite
        ))

        if let onAddToPlaylist {
            buttons.append(ButtonConfig(
                id: .addToPlaylist,
                label: Strings.addToList,
                icon: "text.badge.plus",
                action: onAddToPlaylist
            ))
        }

        if let onGoToSeries {
            buttons.append(ButtonConfig(
                id: .goToSeries,
                label: Strings.goToSeries,
                icon: "tv",
                action: onGoToSeries
            ))
        }

        if let onDelete {
            buttons.append(ButtonConfig(
                id: .delete,
                label: Strings.delete,
                icon: "trash",
                action: onDelete
            ))
        }

        return buttons
    }

    var body: some View {
        HStack(alignment: .top, spacing: SpaceTokens.space3xl) {
            ForEach(Array(buttonConfigs.enumerated()), id: \.element.id) { index, config in
                ActionButton(
                    label: config.label,
                    icon: config.icon,
                    isAssetIcon: config.isAssetIcon,
                    detail: config.detail,
                    isActive: config.isActive,
                    activeColor: config.activeColor,
                    colorIndex: index,
                    action: config.action
                )
                .focused(focusedButton, equals: config.id)
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
    let colorIndex: Int
    let action: () -> Void

    @EnvironmentObject var theme: MoonfinTheme
    @FocusState private var isFocused: Bool

    private var alternatingColor: Color {
        if theme.isNeonPulseTheme {
            return theme.navCycleColor(for: colorIndex)
        }
        if isActive, let activeColor {
            return activeColor
        }
        return theme.colorScheme.onButton
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpaceTokens.spaceXs) {
                ZStack {
                    RoundedRectangle(cornerRadius: RadiusTokens.large)
                        .fill(baseGlassTint)
                        .background(
                            RoundedRectangle(cornerRadius: RadiusTokens.large)
                                .fill(
                                    theme.isNeonPulseTheme
                                        ? AnyShapeStyle(Color.clear)
                                        : (isFocused ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.ultraThinMaterial))
                                )
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
                            .frame(width: 30, height: 30)
                            .foregroundColor(iconColor)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                }
                .frame(width: 96, height: 96)

                Text(label)
                    .font(.captionXs)
                    .fontWeight(.semibold)
                    .foregroundColor(theme.isNeonPulseTheme ? alternatingColor : (isFocused ? theme.colorScheme.onButtonFocused : theme.colorScheme.onBackground.opacity(0.8)))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detail {
                    Text(detail)
                        .font(.caption2xs)
                        .foregroundColor(theme.isNeonPulseTheme ? alternatingColor.opacity(0.85) : (isFocused ? theme.colorScheme.onButtonFocused.opacity(0.7) : theme.colorScheme.onBackground.opacity(0.5)))
                        .lineLimit(isFocused ? 2 : 1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 112)
        }
        .buttonStyle(CleanButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.10 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var baseGlassTint: Color {
        if theme.isNeonPulseTheme { return .clear }
        if isFocused { return theme.colorScheme.buttonFocused }
        if isActive {
            return (activeColor ?? theme.colorScheme.buttonActive).opacity(0.22)
        }
        return theme.colorScheme.button.opacity(0.22)
    }

    private var glassBorderColor: Color {
        isFocused ? theme.effectiveFocusColor : .clear
    }

    private var iconColor: Color {
        if theme.isNeonPulseTheme { return alternatingColor }
        if isFocused { return theme.colorScheme.onButtonFocused }
        if isActive, let activeColor { return activeColor }
        return theme.colorScheme.onButton
    }
}
