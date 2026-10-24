import GameKit
import GridFleetCore
import Observation
import SwiftUI

/// Wraps a value that isn't Sendable so it can hop to the main actor. GameKit objects are only touched there.
nonisolated struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

extension GameRules {
    /// Matchmaking only pairs players who chose the same rules.
    var playerGroup: Int {
        let preset = BoardPreset.allCases.firstIndex(of: self.preset) ?? 0
        return 1 + preset * 8 + (firing == .salvo ? 4 : 0) + (specialWeapons ? 2 : 0) + (shipsMayTouch ? 0 : 1)
    }

    func matchRequest() -> GKMatchRequest {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.playerGroup = playerGroup
        request.inviteMessage = "Sea battle? \(summary)."
        return request
    }
}

/// Game Center sign-in, the list of turn-based matches, and routing of turn events.
@MainActor
@Observable
final class GameCenterService {
    private(set) var isAuthenticated = false
    private(set) var playerName: String?
    private(set) var authError: String?
    private(set) var matches: [GKTurnBasedMatch] = []
    private(set) var isLoadingMatches = false

    /// A match the player chose or was sent to. The home screen opens it.
    var matchToOpen: GKTurnBasedMatch?
    /// A live match that just started.
    var liveMatchToOpen: GKMatch?
    /// A live invite accepted from outside the app.
    var pendingInvite: GKInvite?

    /// Open matches route their turn events here, keyed by match ID.
    var turnHandlers: [String: (GKTurnBasedMatch) -> Void] = [:]

    private let listener = GameCenterListener()

    var localPlayerID: String? { isAuthenticated ? GKLocalPlayer.local.gamePlayerID : nil }

    var matchesAwaitingMe: Int {
        matches.filter { $0.status == .open && $0.isLocalTurn }.count
    }

    func authenticate() {
        listener.service = self
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            let box = UncheckedBox(value: viewController)
            let message = error?.localizedDescription
            Task { @MainActor in
                self.handleAuthentication(viewController: box.value, error: message)
            }
        }
    }

    private func handleAuthentication(viewController: UIViewController?, error: String?) {
        if let viewController {
            UIApplication.shared.topViewController?.present(viewController, animated: true)
            return
        }
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        playerName = isAuthenticated ? GKLocalPlayer.local.displayName : nil
        authError = error
        if isAuthenticated {
            GKLocalPlayer.local.register(listener)
            Task { await refreshMatches() }
        }
    }

    func refreshMatches() async {
        guard isAuthenticated else { return }
        isLoadingMatches = true
        defer { isLoadingMatches = false }
        do {
            let loaded = try await GKTurnBasedMatch.loadMatches()
            matches = loaded.sorted { ($0.isLocalTurn ? 0 : 1, -($0.creationDate.timeIntervalSince1970)) < ($1.isLocalTurn ? 0 : 1, -($1.creationDate.timeIntervalSince1970)) }
        } catch {
            authError = error.localizedDescription
        }
    }

    /// Finds an opponent through Game Center matchmaking.
    func quickMatch(rules: GameRules) async throws -> GKTurnBasedMatch {
        let match = try await GKTurnBasedMatch.find(for: rules.matchRequest())
        await refreshMatches()
        return match
    }

    func liveQuickMatch(rules: GameRules) async throws -> GKMatch {
        try await GKMatchmaker.shared().findMatch(for: rules.matchRequest())
    }

    func cancelLiveSearch() {
        GKMatchmaker.shared().cancel()
    }

    func remove(_ match: GKTurnBasedMatch) async {
        if match.status == .open {
            if match.isLocalTurn {
                for participant in match.participants where participant.matchOutcome == .none {
                    participant.matchOutcome = participant.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID ? .quit : .won
                }
                try? await match.endMatchInTurn(withMatch: match.matchData ?? Data())
            } else {
                try? await match.participantQuitOutOfTurn(with: .quit)
            }
        }
        try? await match.remove()
        await refreshMatches()
    }

    func showDashboard() {
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    // MARK: Events

    fileprivate func receivedTurnEvent(_ match: GKTurnBasedMatch, didBecomeActive: Bool) {
        if let handler = turnHandlers[match.matchID] {
            handler(match)
        } else if didBecomeActive {
            matchToOpen = match
        }
        Task { await refreshMatches() }
    }

    fileprivate func receivedInvite(_ invite: GKInvite) {
        pendingInvite = invite
    }
}

extension GKTurnBasedMatch {
    var isLocalTurn: Bool {
        currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    var opponent: GKTurnBasedParticipant? {
        participants.first { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
    }
}

/// Receives Game Center events and hands them to the service on the main actor.
final class GameCenterListener: NSObject, GKLocalPlayerListener {
    weak var service: GameCenterService?

    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        let box = UncheckedBox(value: match)
        Task { @MainActor in self.service?.receivedTurnEvent(box.value, didBecomeActive: didBecomeActive) }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        let box = UncheckedBox(value: match)
        Task { @MainActor in self.service?.receivedTurnEvent(box.value, didBecomeActive: false) }
    }

    nonisolated func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        let box = UncheckedBox(value: invite)
        Task { @MainActor in self.service?.receivedInvite(box.value) }
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
