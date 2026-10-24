import GameKit
import GridFleetCore

/// A real-time Game Center match. Both players are in the app at once, with a turn timer.
@MainActor
final class LiveTransport: NSObject, LedgerTransport {
    let match: GKMatch
    let rules: GameRules
    let matchID = "live-\(UUID().uuidString)"
    let mode: GameMode = .live
    let turnTimeLimit: TimeInterval? = 30
    var onRemoteUpdate: ((MatchLedger) -> Void)?
    var onOpponentLeft: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var isRealtime: Bool { true }

    private var latest: MatchLedger?
    private var firstLedger: CheckedContinuation<MatchLedger?, Never>?
    private var heardFromOpponent = false
    private var handshakeTask: Task<Void, Never>?
    let forfeitedSeat: Int? = nil

    init(match: GKMatch, rules: GameRules) {
        self.match = match
        self.rules = rules
        super.init()
        match.delegate = self
    }

    var localPlayerID: String? { GKLocalPlayer.local.gamePlayerID }

    /// The player whose ID sorts first takes seat 0 and sets the rules.
    var localSeat: Int {
        let ids = ([GKLocalPlayer.local.gamePlayerID] + match.players.map(\.gamePlayerID)).sorted()
        return ids.first == GKLocalPlayer.local.gamePlayerID ? 0 : 1
    }

    var opponentName: String { match.players.first?.displayName ?? "Opponent" }
    var opponentDetail: String { "Live" }

    var isLocalTurn: Bool { (latest?.actingSeat ?? 0) == localSeat }

    func load() async throws -> MatchLedger? {
        if localSeat == 0 {
            let ledger = MatchLedger(rules: rules)
            latest = ledger
            try await share(ledger)
            // The other phone may not be listening yet. Repeat the opening until it answers.
            handshakeTask = Task { [weak self] in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard let self, !Task.isCancelled, !self.heardFromOpponent, let latest = self.latest else { return }
                    try? await self.share(latest)
                }
            }
            return ledger
        }
        if let latest { return latest }
        // Seat 1 waits for seat 0's opening ledger, which carries the rules.
        return await withCheckedContinuation { continuation in
            firstLedger = continuation
            Task {
                try? await Task.sleep(for: .seconds(20))
                if let pending = self.firstLedger {
                    self.firstLedger = nil
                    pending.resume(returning: nil)
                }
            }
        }
    }

    func share(_ ledger: MatchLedger) async throws {
        latest = ledger
        try match.sendData(toAllPlayers: try ledger.encoded(), with: .reliable)
    }

    func endTurn(_ ledger: MatchLedger) async throws { try await share(ledger) }
    func endMatch(_ ledger: MatchLedger) async throws { try await share(ledger) }
    func resign(_ ledger: MatchLedger) async throws { try await share(ledger) }

    func close() {
        handshakeTask?.cancel()
        match.delegate = nil
        match.disconnect()
    }

    fileprivate func received(_ data: Data) {
        guard let ledger = try? MatchLedger.decode(data) else { return }
        heardFromOpponent = true
        latest = ledger
        if let pending = firstLedger {
            firstLedger = nil
            // Answer, so seat 0 stops repeating the opening.
            try? match.sendData(toAllPlayers: data, with: .reliable)
            pending.resume(returning: ledger)
            return
        }
        onRemoteUpdate?(ledger)
    }

    fileprivate func playerDisconnected() {
        onOpponentLeft?()
    }
}

extension LiveTransport: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor in self.received(data) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        guard state == .disconnected else { return }
        Task { @MainActor in self.playerDisconnected() }
    }
}
