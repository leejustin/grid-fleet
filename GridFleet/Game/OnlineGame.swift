import Foundation
import GridFleetCore
import Observation

/// Moves a match ledger between this device and the opponent's.
@MainActor
protocol LedgerTransport: AnyObject {
    var matchID: String { get }
    var mode: GameMode { get }
    var localSeat: Int { get }
    var localPlayerID: String? { get }
    var opponentName: String { get }
    var opponentDetail: String { get }
    /// Whether the transport agrees it's this device's turn.
    var isLocalTurn: Bool { get }
    /// Seconds per turn, for live play. Nil for no limit.
    var turnTimeLimit: TimeInterval? { get }
    var onRemoteUpdate: ((MatchLedger) -> Void)? { get set }
    var onOpponentLeft: (() -> Void)? { get set }
    /// Called when a live connection drops or comes back. Transports that don't hold a connection never call it.
    var onConnectionChanged: ((Bool) -> Void)? { get set }
    /// Both players are present: results come back right away and both sides share as they go.
    var isRealtime: Bool { get }
    /// A seat that quit or ran out of time outside the ledger (Game Center turn timeouts), if any.
    var forfeitedSeat: Int? { get }

    /// The current ledger, or nil for a brand-new match.
    func load() async throws -> MatchLedger?
    /// Shares the ledger without passing the turn.
    func share(_ ledger: MatchLedger) async throws
    func endTurn(_ ledger: MatchLedger) async throws
    func endMatch(_ ledger: MatchLedger) async throws
    func resign(_ ledger: MatchLedger) async throws
    func close()
}

/// A game against someone on another device. Each side keeps its fleet secret and answers for its own waters.
@MainActor
@Observable
final class OnlineGame {
    enum Stage: Equatable {
        case loading
        case deploying
        case battle
        case failed(String)
    }

    let transport: any LedgerTransport
    let myName: String
    private(set) var ledger: MatchLedger
    private(set) var stage: Stage = .loading
    private(set) var session: BattleSession?

    var onComplete: ((GameSummary) -> Void)?

    private let store: SecretStore
    private var secret: FleetSecret?
    private var startedAt = Date.now
    private var advancing = false
    /// Set when the ledger changes while `advance` is mid-way, so it runs again with the new state.
    private var advanceAgain = false
    private var timerTask: Task<Void, Never>?

    init(transport: any LedgerTransport, rules: GameRules, myName: String, store: SecretStore) {
        self.transport = transport
        self.myName = myName
        self.store = store
        self.ledger = MatchLedger(rules: rules)
    }

    var seat: Int { transport.localSeat }
    var opponentSeat: Int { MatchLedger.opponent(of: seat) }
    var rules: GameRules { ledger.rules }
    var matchID: String { transport.matchID }

    var opponentName: String {
        ledger.seats[opponentSeat].displayName ?? transport.opponentName
    }

    // MARK: Lifecycle

    func start() async {
        transport.onRemoteUpdate = { [weak self] ledger in self?.received(ledger) }
        transport.onOpponentLeft = { [weak self] in self?.opponentLeft() }
        transport.onConnectionChanged = { [weak self] connected in self?.connectionChanged(connected) }
        do {
            if let loaded = try await transport.load() { ledger = loaded }
        } catch {
            stage = .failed("Couldn't load the match. \(error.localizedDescription)")
            Analytics.shared.capture("online_error", ["kind": "load", "mode": .string(transport.mode.rawValue)])
            return
        }
        secret = store.secret(for: matchID)
        if let forfeited = transport.forfeitedSeat, ledger.phase != .complete {
            // Someone quit or let their turn clock run out while the app was closed.
            ledger.resign(seat: forfeited, secret: forfeited == seat ? secret : nil)
            if forfeited != seat, transport.isLocalTurn {
                let snapshot = ledger
                Task { try? await transport.endMatch(snapshot) }
            }
        }
        if ledger.phase == .complete, secret == nil {
            stage = .failed(ledger.winner == seat ? "Your opponent left before you deployed. The match is over." : "This match is over.")
            return
        }
        if secret == nil {
            if ledger.isDeployed(seat) {
                stage = .failed("Your fleet for this match was deployed on another device. Open it there.")
            } else {
                stage = .deploying
            }
            return
        }
        enterBattle(previous: store.lastSeen(for: matchID))
    }

    func close() {
        timerTask?.cancel()
        transport.close()
    }

    func deploy(_ fleet: Fleet) {
        let secret = FleetSecret(fleet: fleet)
        do {
            try ledger.deploy(seat: seat, secret: secret, playerID: transport.localPlayerID, displayName: myName)
        } catch {
            stage = .failed("Couldn't deploy: \(error)")
            return
        }
        self.secret = secret
        store.save(secret, for: matchID)
        startedAt = .now
        Analytics.shared.capture("game_started", ledger.rules.analyticsProperties.merging(["mode": .string(transport.mode.rawValue), "seat": .int(seat)]))
        if transport.isRealtime {
            let snapshot = ledger
            Task { try? await transport.share(snapshot) }
        }
        enterBattle(previous: ledger)
    }

    // MARK: Battle

    private func enterBattle(previous: MatchLedger?) {
        guard let secret else { return }
        let session = BattleSession(
            rules: ledger.rules,
            myName: myName,
            opponentName: opponentName,
            opponentDetail: transport.opponentDetail,
            ocean: ledger.ocean(for: seat, secret: secret)
        )
        session.onFire = { [weak self] strikes in self?.fire(strikes) }
        session.onResign = { [weak self] in self?.resign() }
        self.session = session
        syncSession()
        stage = .battle
        let news = resolvedSince(previous)
        if news.isEmpty {
            Task { await advance() }
        } else {
            let staged = session.stage(news, onOcean: false, delay: 0.6)
            Task {
                await session.perform(staged)
                await advance()
            }
        }
    }

    private func syncSession() {
        guard let session, let secret else { return }
        session.opponentName = opponentName
        session.ocean = ledger.ocean(for: seat, secret: secret)
        session.target = ledger.target(for: seat)
        session.inFlight = ledger.strikesInFlight(from: seat)
        session.arsenal = ledger.seats[seat].arsenal
        session.shotsAllowed = ledger.shotsAllowed(for: seat, secret: secret)
    }

    /// Reports on this player's shots that arrived since `previous`.
    private func resolvedSince(_ previous: MatchLedger?) -> [StrikeReport] {
        let mine = ledger.volleys.enumerated().filter { $0.element.seat == seat && $0.element.reports != nil }
        guard let previous else {
            // First look on this device: just replay the latest volley.
            return mine.last?.element.reports ?? []
        }
        return mine.filter { index, _ in
            index >= previous.volleys.count || previous.volleys[index].reports == nil
        }.flatMap { $0.element.reports ?? [] }
    }

    /// Does whatever this device owes the match right now. Updates that arrive while it's busy
    /// (the other phone can answer within an animation) make it run again rather than being dropped.
    private func advance() async {
        if advancing {
            advanceAgain = true
            return
        }
        advancing = true
        defer { advancing = false }
        repeat {
            advanceAgain = false
            await advanceOnce()
        } while advanceAgain
    }

    private func advanceOnce() async {
        guard let secret, let session else { return }

        if ledger.phase == .complete {
            finish()
            return
        }
        guard ledger.actingSeat == seat, transport.isLocalTurn else {
            showWaiting()
            return
        }

        if ledger.phase == .reveal {
            // We won; reveal our fleet so they can check it, and close the match.
            do {
                try ledger.revealAsWinner(seat: seat, secret: secret)
                try await transport.endMatch(ledger)
            } catch {
                session.show(Banner(title: "Connection trouble", subtitle: "Couldn't close the match. It'll retry next time.", tone: .danger, onOcean: false))
            }
            store.saveLastSeen(ledger, for: matchID)
            finish()
            return
        }

        let incoming: [StrikeReport]
        do {
            incoming = try ledger.resolveIncoming(seat: seat, secret: secret)
        } catch {
            stage = .failed("This device's fleet doesn't match the one sealed for this match.")
            return
        }
        syncSession()
        let lost = ledger.phase == .reveal
        if lost {
            // We lost. Pass the turn so the winner can reveal. Send before animating, so they aren't kept waiting.
            try? await transport.endTurn(ledger)
        } else if !incoming.isEmpty, transport.isRealtime {
            try? await transport.share(ledger)
        }
        if !incoming.isEmpty {
            await session.perform(session.stage(incoming, onOcean: true, delay: 0.3))
        }
        store.saveLastSeen(ledger, for: matchID)

        // The ledger may have moved on while the shots were landing (the winner can reveal that fast).
        if lost || ledger.phase != .battle {
            finish()
            return
        }
        guard ledger.actingSeat == seat else {
            showWaiting()
            return
        }
        session.waitingNote = nil
        session.beginTurn()
        startTurnTimer()
    }

    private func showWaiting() {
        guard let session else { return }
        if transport.isRealtime {
            session.status = .opponentAiming
            session.waitingNote = "\(opponentName) is aiming…"
        } else {
            session.status = .waitingForOpponent
            if !ledger.isDeployed(opponentSeat) && ledger.seats[opponentSeat].playerID == nil {
                session.waitingNote = "Shots away. When an opponent joins, they'll report the damage on their turn."
            } else {
                session.waitingNote = "Shots away. \(opponentName) reports the damage on their turn."
            }
        }
    }

    private func fire(_ strikes: [Strike]) {
        guard let secret, let session else { return }
        do {
            try ledger.fire(seat: seat, strikes: strikes, secret: secret)
        } catch {
            Haptics.warning()
            return
        }
        timerTask?.cancel()
        session.turnDeadline = nil
        syncSession()
        session.lastOutgoing = Set(strikes.flatMap { $0.footprint(on: rules.board) })
        showWaiting()
        store.saveLastSeen(ledger, for: matchID)
        let snapshot = ledger
        Task {
            do {
                try await transport.endTurn(snapshot)
            } catch {
                session.show(Banner(title: "Not sent", subtitle: error.localizedDescription, tone: .danger, onOcean: false))
            }
        }
    }

    private func received(_ remote: MatchLedger) {
        var remote = remote
        // Live: both sides deploy at once, so keep our own seat if their copy doesn't have it yet.
        if remote.seats[seat].commitment == nil, ledger.seats[seat].commitment != nil {
            remote.seats[seat] = ledger.seats[seat]
        }
        // Ignore anything older than what we have.
        let remoteResolved = remote.volleys.filter { $0.reports != nil }.count
        let localResolved = ledger.volleys.filter { $0.reports != nil }.count
        guard remote.phase != ledger.phase || remote.volleys.count > ledger.volleys.count || remoteResolved > localResolved
            || remote.seats.map(\.commitment) != ledger.seats.map(\.commitment) else { return }

        if secret == nil {
            ledger = remote
            return
        }
        let previous = ledger
        ledger = remote
        guard let session else { return }
        syncSession()
        let news = resolvedSince(previous)
        if news.isEmpty {
            Task { await advance() }
        } else {
            session.status = .resolving
            let staged = session.stage(news, onOcean: false)
            Task {
                await session.perform(staged)
                await advance()
            }
        }
    }

    private func startTurnTimer() {
        timerTask?.cancel()
        guard let limit = transport.turnTimeLimit, let session else { return }
        let deadline = Date.now.addingTimeInterval(limit)
        session.turnDeadline = deadline
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, let session = self.session, session.status == .yourTurn else { return }
            // Out of time: the gunners pick a target themselves.
            var rng = SystemRandomNumberGenerator()
            let strikes = AIAdmiral(difficulty: .medium).chooseVolley(target: session.target, shotsAllowed: session.shotsAllowed, arsenal: Arsenal(stock: [:]), using: &rng)
            session.show(Banner(title: "Time's up", subtitle: "Your gunners fired on their own", tone: .info, onOcean: false))
            session.aims = []
            session.weapon = .shell
            self.fire(strikes)
        }
    }

    // MARK: Ending

    func resign() {
        guard ledger.phase != .complete else { return }
        ledger.resign(seat: seat, secret: secret)
        let snapshot = ledger
        Task { try? await transport.resign(snapshot) }
        finish()
    }

    private func connectionChanged(_ connected: Bool) {
        guard let session, ledger.phase != .complete else { return }
        if connected {
            session.show(Banner(title: "Reconnected", tone: .info, onOcean: false))
            session.waitingNote = nil
            Task { await advance() }
        } else {
            session.show(Banner(title: "Connection lost", subtitle: "Keep both phones open and close by", tone: .danger, onOcean: false))
            session.waitingNote = "Lost touch with \(opponentName). Keep both phones open and close together; the game picks up where it left off."
        }
    }

    private func opponentLeft() {
        guard ledger.phase != .complete else { return }
        ledger.resign(seat: opponentSeat, secret: nil)
        if transport.isLocalTurn {
            let snapshot = ledger
            Task { try? await transport.endMatch(snapshot) }
        }
        finish()
    }

    private func finish() {
        timerTask?.cancel()
        guard let session, let secret else { return }
        // finish() runs again when the winner's reveal arrives, to add the fleet check. Only celebrate once.
        let firstTime = session.outcome == nil
        syncSession()
        let won = ledger.winner == seat
        let stats = BattleStats(turns: [], target: ledger.target(for: seat))
        let turns = ledger.volleys.filter { $0.seat == seat }.count
        let shipsLost = ledger.ocean(for: seat, secret: secret).sunkShips.count
        let audit = ledger.audit(of: opponentSeat)
        session.revealedEnemyFleet = ledger.seats[opponentSeat].reveal?.fleet
        session.status = .finished
        session.turnDeadline = nil
        session.waitingNote = nil

        let detail: String
        if ledger.resignedSeat == opponentSeat {
            detail = "\(opponentName) struck their colors."
        } else if ledger.resignedSeat == seat {
            detail = "You struck your colors."
        } else if won {
            detail = "\(opponentName)'s fleet destroyed in \(turns) turns."
        } else {
            detail = "Your fleet rests on the seabed."
        }
        session.outcome = BattleOutcome(
            won: won,
            headline: won ? "Victory" : "Defeat",
            detail: detail,
            stats: BattleStats(turns: [], target: ledger.target(for: seat)),
            shipsLost: shipsLost,
            turns: turns,
            duration: Date.now.timeIntervalSince(startedAt),
            enemyFleet: ledger.seats[opponentSeat].reveal?.fleet,
            audit: audit,
            opponentAudit: ledger.audit(of: seat)
        )
        if firstTime {
            if won { Haptics.victory() } else { Haptics.defeat() }
        }
        let tracker = MedalTracker(replaying: ledger.volleys.map { ($0.seat == seat, $0.reports ?? []) })
        let medals = tracker.medals(won: won, rules: rules, beatAdmiral: false)
        session.outcome?.medals = medals
        if store.markRecorded("analytics-\(matchID)") {
            Analytics.shared.capture("game_finished", rules.analyticsProperties.merging(session.usageProperties).merging([
                "mode": .string(transport.mode.rawValue),
                "result": .string(ledger.resignedSeat != nil ? "resigned" : (won ? "won" : "lost")),
                "turns": .int(turns),
                "audit": .string(audit.map { $0.isClean ? "verified" : "failed" } ?? "pending"),
                "medals": .int(medals.count),
            ]))
        }

        if transport.mode == .nearby, ledger.phase == .complete, SavedNearbyGame.load()?.matchID == matchID {
            SavedNearbyGame.clear()
        }
        if store.markRecorded(matchID) {
            var summaryStats = stats
            summaryStats.turns = turns
            onComplete?(GameSummary(
                mode: transport.mode,
                difficulty: nil,
                rules: rules,
                won: won,
                opponentName: opponentName,
                stats: summaryStats,
                shipsLost: shipsLost,
                duration: Date.now.timeIntervalSince(startedAt),
                verified: audit.map(\.isClean),
                medals: medals
            ))
        }
    }
}
