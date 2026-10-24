import GameKit
import GridFleetCore

/// A Game Center turn-based match. Apple's servers hold the ledger between turns.
@MainActor
final class TurnBasedTransport: LedgerTransport {
    private(set) var match: GKTurnBasedMatch
    private weak var gameCenter: GameCenterService?

    /// A week to take each turn, matching Game Center's default.
    static let turnTimeout: TimeInterval = 7 * 24 * 60 * 60

    let mode: GameMode = .online
    let turnTimeLimit: TimeInterval? = nil
    var onRemoteUpdate: ((MatchLedger) -> Void)?
    var onOpponentLeft: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var isRealtime: Bool { false }

    init(match: GKTurnBasedMatch, gameCenter: GameCenterService) {
        self.match = match
        self.gameCenter = gameCenter
        gameCenter.turnHandlers[match.matchID] = { [weak self] updated in self?.handle(updated) }
    }

    var matchID: String { match.matchID }
    var localPlayerID: String? { GKLocalPlayer.local.gamePlayerID }

    var localSeat: Int {
        if let index = match.participants.firstIndex(where: { $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID }) {
            return index
        }
        // Just joined through matchmaking: our slot is the current one.
        return match.participants.firstIndex { $0 == match.currentParticipant } ?? 0
    }

    private var opponentParticipant: GKTurnBasedParticipant? {
        let seat = MatchLedger.opponent(of: localSeat)
        return match.participants.indices.contains(seat) ? match.participants[seat] : nil
    }

    var opponentName: String {
        guard let opponent = opponentParticipant else { return "Opponent" }
        if let name = opponent.player?.displayName { return name }
        return opponent.status == .matching ? "Finding opponent" : "Invited player"
    }

    var opponentDetail: String { "Game Center" }

    var forfeitedSeat: Int? {
        match.participants.firstIndex { $0.matchOutcome == .quit || $0.matchOutcome == .timeExpired }
    }

    var isLocalTurn: Bool { match.isLocalTurn }

    func load() async throws -> MatchLedger? {
        let data = try await match.loadMatchData()
        guard let data, !data.isEmpty else { return nil }
        return try MatchLedger.decode(data)
    }

    func share(_ ledger: MatchLedger) async throws {
        try await match.saveCurrentTurn(withMatch: try ledger.encoded())
    }

    func endTurn(_ ledger: MatchLedger) async throws {
        let data = try ledger.encoded()
        let next = match.participants.filter { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
        match.message = ledger.phase == .reveal ? "The battle is decided. Open to see the result." : "Incoming fire. Your move."
        try await match.endTurn(withNextParticipants: next.isEmpty ? match.participants : next, turnTimeout: Self.turnTimeout, match: data)
    }

    func endMatch(_ ledger: MatchLedger) async throws {
        for (index, participant) in match.participants.enumerated() where participant.matchOutcome == .none {
            participant.matchOutcome = index == ledger.winner ? .won : (index == ledger.resignedSeat ? .quit : .lost)
        }
        match.message = "Battle over."
        try await match.endMatchInTurn(withMatch: try ledger.encoded())
    }

    func resign(_ ledger: MatchLedger) async throws {
        if match.isLocalTurn {
            let next = match.participants.filter { $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID }
            try await match.participantQuitInTurn(with: .quit, nextParticipants: next, turnTimeout: Self.turnTimeout, match: try ledger.encoded())
        } else {
            try await match.participantQuitOutOfTurn(with: .quit)
        }
    }

    func close() {
        gameCenter?.turnHandlers[match.matchID] = nil
    }

    private func handle(_ updated: GKTurnBasedMatch) {
        match = updated
        if let opponent = opponentParticipant, opponent.matchOutcome == .quit || opponent.matchOutcome == .timeExpired {
            Task {
                if let ledger = try? await load(), ledger.phase == .complete {
                    onRemoteUpdate?(ledger)
                } else {
                    onOpponentLeft?()
                }
            }
            return
        }
        Task {
            if let ledger = try? await load() { onRemoteUpdate?(ledger) }
        }
    }
}
