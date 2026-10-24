import GameKit
import GridFleetCore
import SwiftUI

/// Game Center play: invite friends, find a match, play live, and pick up running games.
struct OnlineLobbyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme

    @State private var showsInvite = false
    @State private var showsLive = false
    @State private var showsRules = false
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        @Bindable var settings = settings
        ScreenScroll {
            if gameCenter.isAuthenticated {
                newMatch
                matchList
            } else {
                signIn
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(theme.danger)
            }
        }
        .oceanNavigation("Online")
        .refreshable { await gameCenter.refreshMatches() }
        .task { await gameCenter.refreshMatches() }
        .sheet(isPresented: $showsInvite) {
            TurnBasedMatchmakerSheet(request: settings.lastRules.matchRequest()) { showsInvite = false }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showsLive) {
            LiveMatchmakerSheet(source: .request(settings.lastRules.matchRequest())) { match in
                showsLive = false
                gameCenter.liveMatchToOpen = match
            } onCancel: {
                showsLive = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsRules) {
            NavigationStack {
                ScreenScroll { RulesPicker(rules: $settings.lastRules) }
                    .navigationTitle("Match rules")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsRules = false } } }
            }
            .presentationDetents([.large])
            .presentationBackground(theme.backdropBottom)
        }
        .onChange(of: router.activeGame?.id) { _, id in
            if id != nil { showsInvite = false; showsLive = false }
        }
        .onAppear {
            if !store.allows(settings.lastRules) { settings.lastRules = .classic }
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Sign in to Game Center").font(.headline)
                Text("Play friends and strangers on any iPhone or iPad. Turns can take minutes or days.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
            }
            Button("Sign in") { gameCenter.authenticate() }
                .buttonStyle(.fleet(.primary, compact: true))
            Text("No Game Center? A room code only needs iCloud.")
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .surface()
    }

    private var newMatch: some View {
        ContentSection("New match") {
            VStack(spacing: 0) {
                Button { showsRules = true } label: {
                    ListRow(systemImage: "slider.horizontal.3", title: "Rules", detail: settings.lastRules.summary)
                }
                RowDivider()
                Button {
                    Haptics.tap()
                    Analytics.shared.capture("matchmaking_opened", ["kind": "invite"])
                    showsInvite = true
                } label: {
                    ListRow(systemImage: "envelope", title: "Invite friends", detail: "Game Center friends or a link in Messages")
                }
                RowDivider()
                Button(action: quickMatch) {
                    ListRow(systemImage: "bolt.horizontal", title: "Quick match", detail: "Matched with someone using the same rules") {
                        if searching { ProgressView() } else { DisclosureChevron() }
                    }
                }
                .disabled(searching)
                RowDivider()
                Button {
                    Haptics.tap()
                    Analytics.shared.capture("matchmaking_opened", ["kind": "live"])
                    showsLive = true
                } label: {
                    ListRow(systemImage: "timer", title: "Live match", detail: "Both in the app, 30 seconds a turn")
                }
            }
            .buttonStyle(PressableStyle())
            .surface()
        }
    }

    private var matchList: some View {
        ContentSection("Your matches") {
            if gameCenter.matches.isEmpty {
                Text(gameCenter.isLoadingMatches ? "Loading…" : "No matches yet.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.m)
                    .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(gameCenter.matches.enumerated()), id: \.element.matchID) { index, match in
                        if index > 0 { RowDivider(inset: Space.m + 10 + Space.s) }
                        MatchRow(match: match)
                            .onTapGesture {
                                Haptics.tap()
                                gameCenter.matchToOpen = match
                            }
                            .contextMenu {
                                Button(match.status == .open ? "Resign and remove" : "Remove", systemImage: "trash", role: .destructive) {
                                    Task { await gameCenter.remove(match) }
                                }
                            }
                    }
                }
                .surface()
            }
        }
    }

    private func quickMatch() {
        searching = true
        error = nil
        Analytics.shared.capture("matchmaking_opened", ["kind": "quick"])
        Task {
            defer { searching = false }
            do {
                gameCenter.matchToOpen = try await gameCenter.quickMatch(rules: settings.lastRules)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct MatchRow: View {
    let match: GKTurnBasedMatch
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.opponent?.player?.displayName ?? "Waiting for an opponent").font(.body)
                Text(statusText).font(.footnote).foregroundStyle(theme.inkSecondary)
            }
            Spacer(minLength: Space.xs)
            Text(match.creationDate, format: .relative(presentation: .named))
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
            DisclosureChevron()
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.m)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the match")
    }

    private var statusText: String {
        switch match.status {
        case .ended:
            let me = match.participants.first { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID }
            return me?.matchOutcome == .won ? "Finished. You won." : "Finished. You lost."
        case .matching: return "Finding an opponent"
        default: return match.isLocalTurn ? "Your move" : "Their move"
        }
    }

    private var statusColor: Color {
        if match.status == .ended { return theme.inkSecondary.opacity(0.5) }
        return match.isLocalTurn ? theme.accent : theme.inkSecondary
    }
}

/// Game Center's own screen for inviting friends or auto-matching a turn-based game.
struct TurnBasedMatchmakerSheet: UIViewControllerRepresentable {
    let request: GKMatchRequest
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = context.coordinator
        controller.showExistingMatches = false
        return controller
    }

    func updateUIViewController(_ controller: GKTurnBasedMatchmakerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        nonisolated func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            Task { @MainActor in self.onClose() }
        }

        nonisolated func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController, didFailWithError error: Error) {
            Task { @MainActor in self.onClose() }
        }
    }
}

/// Game Center's screen for starting a live match, from a request or an accepted invite.
struct LiveMatchmakerSheet: UIViewControllerRepresentable {
    enum Source {
        case request(GKMatchRequest)
        case invite(GKInvite)
    }

    let source: Source
    let onMatch: (GKMatch) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller: GKMatchmakerViewController? = switch source {
        case .request(let request): GKMatchmakerViewController(matchRequest: request)
        case .invite(let invite): GKMatchmakerViewController(invite: invite)
        }
        guard let controller else { return UIViewController() }
        controller.matchmakerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onMatch: onMatch, onCancel: onCancel) }

    final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        let onMatch: (GKMatch) -> Void
        let onCancel: () -> Void
        init(onMatch: @escaping (GKMatch) -> Void, onCancel: @escaping () -> Void) {
            self.onMatch = onMatch
            self.onCancel = onCancel
        }

        nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
            let box = UncheckedBox(value: match)
            Task { @MainActor in self.onMatch(box.value) }
        }

        nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
            Task { @MainActor in self.onCancel() }
        }

        nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
            Task { @MainActor in self.onCancel() }
        }
    }
}
