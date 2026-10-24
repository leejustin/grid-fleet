import FoldKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme
    @State private var showsHowToPlay = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var store = store
        ScreenScroll {
            ContentSection("Captain", footer: "Shown to friends across the table and in pass and play.") {
                TextField("Your name", text: $settings.playerName)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 52)
                    .surface()
            }

            ContentSection("Gameplay") {
                VStack(spacing: 0) {
                    ToggleRow(title: "Fire on first tap", detail: "Off: tap once to aim, again to fire", isOn: $settings.oneTapFire)
                    RowDivider(inset: Space.m)
                    ToggleRow(title: "Follow the action", detail: "Swing to your fleet while the enemy fires", isOn: $settings.followAction)
                    RowDivider(inset: Space.m)
                    ToggleRow(title: "Rival chatter", isOn: $settings.rivalChatter)
                    RowDivider(inset: Space.m)
                    ToggleRow(title: "Sound effects", isOn: $settings.soundEnabled)
                    RowDivider(inset: Space.m)
                    ToggleRow(title: "Haptics", isOn: $settings.hapticsEnabled)
                }
                .surface()
            }

            ContentSection("Board", footer: "Pegs look like the folding board game: white for a miss, red for a hit.") {
                VStack(spacing: 0) {
                    MenuRow(title: "Board style", value: settings.boardStylePreference.displayName, selection: $settings.boardStylePreference) {
                        ForEach(BoardStylePreference.allCases) { Text($0.displayName).tag($0) }
                    }
                    RowDivider(inset: Space.m)
                    ValueRow(title: "Theme and skins", value: Theme.with(id: settings.themeID).name) {
                        router.openShipyard()
                    }
                }
                .surface()
            }

            ContentSection("Game Center") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Status").font(.body)
                        Spacer()
                        Text(gameCenter.isAuthenticated ? (gameCenter.playerName ?? "Signed in") : "Not signed in")
                            .font(.body)
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 52)
                    RowDivider(inset: Space.m)
                    if gameCenter.isAuthenticated {
                        ActionRow(title: "Open dashboard") { gameCenter.showDashboard() }
                    } else {
                        ActionRow(title: "Sign in") { gameCenter.authenticate() }
                    }
                }
                .foregroundStyle(theme.ink)
                .surface()
            }

            if Analytics.shared.isConfigured {
                ContentSection("Privacy", footer: "Sends gameplay events (like games started and finished, time spent deploying, missed taps and fold posture) with a random install ID. Never your name, Game Center or iCloud identity. Turning it off deletes anything not yet sent.") {
                    ToggleRow(title: "Share anonymous usage", isOn: Binding(
                        get: { Analytics.shared.optedIn },
                        set: { Analytics.shared.setOptedIn($0) }
                    ))
                    .surface()
                }
            }

            ContentSection("Help") {
                VStack(spacing: 0) {
                    ActionRow(title: "How to play") { showsHowToPlay = true }
                    RowDivider(inset: Space.m)
                    ActionRow(title: "Restore purchases") { Task { await store.restore() } }
                }
                .surface()
            }

            #if DEBUG
            ContentSection("Developer", footer: "Fold posture overrides the real hinge so every layout can be tried on any device.") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Fold posture").font(.body)
                        Spacer()
                        FoldSimulatorPicker()
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(theme.inkSecondary)
                    }
                    .padding(.leading, Space.m)
                    .padding(.trailing, Space.xxs)
                    .frame(minHeight: 52)
                    RowDivider(inset: Space.m)
                    ToggleRow(title: "Unlock everything", isOn: $store.unlockAllForTesting)
                    RowDivider(inset: Space.m)
                    NavigationLink { SoundLabView() } label: {
                        HStack {
                            Text("Sound and haptics lab").font(.body)
                            Spacer()
                            DisclosureChevron()
                        }
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    RowDivider(inset: Space.m)
                    ActionRow(title: "Replay the guided first game") { settings.hasSeenTutorial = false }
                }
                .foregroundStyle(theme.ink)
                .surface()
            }
            #endif

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Grid Fleet \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.footnote.weight(.semibold))
                Text("An original game, not affiliated with or endorsed by Hasbro. No ads, and no tracking across apps.")
                    .font(.footnote)
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, Space.xxs)
        }
        .oceanNavigation("Settings")
        .sheet(isPresented: $showsHowToPlay) {
            NavigationStack { HowToPlayView() }
        }
    }
}
