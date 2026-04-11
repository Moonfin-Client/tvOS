import SwiftUI

struct SettingsSyncPlayScreen: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var settingsRouter: SettingsRouter
    @FocusState private var focusedRoute: SettingsRoute?

    private var prefs: UserPreferences { container.userPreferences }
    private var syncPlayManager: SyncPlayManager { container.syncPlayManager }

    var body: some View {
        SettingsScreenLayout(title: "SyncPlay") {
            SettingsToggleButton(
                icon: "person.2.fill",
                heading: "Enabled",
                caption: "Enable SyncPlay synchronized playback",
                isOn: prefs.binding(for: UserPreferences.syncPlayEnabled)
            )

            SettingsToggleButton(
                icon: "person.badge.shield.checkmark",
                heading: "Internal Rollout Access",
                caption: "Restrict SyncPlay to internal test users",
                isOn: prefs.binding(for: UserPreferences.syncPlayInternalRolloutEnabled)
            )

            SettingsToggleButton(
                icon: "exclamationmark.shield",
                heading: "Advanced Correction",
                caption: "Kill switch for advanced SyncPlay timing corrections",
                isOn: prefs.binding(for: UserPreferences.syncPlayAdvancedCorrectionEnabled)
            )

            SettingsToggleButton(
                icon: "arrow.trianglehead.2.clockwise",
                heading: "Sync Correction",
                caption: "Automatically correct playback drift",
                isOn: prefs.binding(for: UserPreferences.syncPlayEnableSyncCorrection)
            )

            SettingsToggleButton(
                icon: "speedometer",
                heading: "Speed to Sync",
                caption: "Adjust playback speed to sync",
                isOn: prefs.binding(for: UserPreferences.syncPlayUseSpeedToSync)
            )

            SettingsToggleButton(
                icon: "forward.fill",
                heading: "Skip to Sync",
                caption: "Skip ahead/back to sync position",
                isOn: prefs.binding(for: UserPreferences.syncPlayUseSkipToSync)
            )

            SettingsListButton(
                icon: "timer",
                heading: "Min Delay (Speed)",
                caption: "Minimum drift before speed correction (ms)",
                trailingText: "\(prefs[UserPreferences.syncPlayMinDelaySpeedToSync])",
                action: { settingsRouter.navigate(to: .moonfinSyncPlayMinDelay) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlayMinDelay)

            SettingsListButton(
                icon: "timer",
                heading: "Max Delay (Speed)",
                caption: "Maximum drift for speed correction (ms)",
                trailingText: "\(prefs[UserPreferences.syncPlayMaxDelaySpeedToSync])",
                action: { settingsRouter.navigate(to: .moonfinSyncPlayMaxDelay) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlayMaxDelay)

            SettingsListButton(
                icon: "clock.arrow.circlepath",
                heading: "Speed Duration",
                caption: "How long to adjust speed (ms)",
                trailingText: "\(prefs[UserPreferences.syncPlaySpeedToSyncDuration])",
                action: { settingsRouter.navigate(to: .moonfinSyncPlayDuration) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlayDuration)

            SettingsListButton(
                icon: "forward.end.fill",
                heading: "Min Delay (Skip)",
                caption: "Minimum drift before skip correction (ms)",
                trailingText: "\(prefs[UserPreferences.syncPlayMinDelaySkipToSync])",
                action: { settingsRouter.navigate(to: .moonfinSyncPlayMinDelaySkip) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlayMinDelaySkip)

            SettingsListButton(
                icon: "clock.badge.questionmark",
                heading: "Extra Time Offset",
                caption: "Additional offset in milliseconds",
                trailingText: "\(prefs[UserPreferences.syncPlayExtraTimeOffset])",
                action: { settingsRouter.navigate(to: .moonfinSyncPlayExtraOffset) }
            )
            .focused($focusedRoute, equals: .moonfinSyncPlayExtraOffset)

            if syncPlayManager.state.enabled {
                SettingsToggleButton(
                    icon: "hourglass",
                    heading: "Ignore Wait (Current Group)",
                    caption: "Bypass waiting for other participants",
                    isOn: Binding(
                        get: { syncPlayManager.ignoreWaitEnabled },
                        set: { syncPlayManager.requestSetIgnoreWait($0) }
                    )
                )
            }
        }
        .restoresFocus($focusedRoute)
    }
}
