import Foundation
import GridFleetCore
import Observation

/// A game on one device: against the computer, or pass and play.
@MainActor
@Observable
final class LocalGame {
    enum Opponent: Equatable {
        case computer(AIDifficulty)
        case human
    }

    enum HandoffPurpose: Equatable { case deploy, battle }

    enum Stage: Equatable {
        case deploying(Side)
        /// Pass and play: cover the screen until the next player is ready.
        case handoff(to: Side, purpose: HandoffPurpose)
        case battle
    }

    let rules: GameRules
    let opponent: Opponent
    let names: [String]
    private(set) var stage: Stage = .deploying(.home)
    private(set) var battle: Battle?
    private(set) var session: BattleSession?
    private(set) var viewer: Side = .home
    /// Pass and play: the fleet is covered (phone closed, app left, or Hide tapped).
    var isHidden = false

    var onComplete: ((GameSummary) -> Void)?
    /// Tips for a new player's first game.
    var coach: Coach?

    private var fleets: [Fleet?] = [nil, nil]
    private var pendingIncoming: TurnRecord?
    private var startedAt = Date.now
    private var rng = SystemRandomNumberGenerator()
    private var resignedSide: Side?
    private var director: RivalDirector?

    init(rules: GameRules, opponent: Opponent, names: [String]) {
        self.rules = rules
        self.opponent = opponent
        self.names = names
    }

    // MARK: Saving

    /// Everything needed to pick a battle back up.
    struct Snapshot: Codable {
        var rules: GameRules
        var difficulty: AIDifficulty?
        var names: [String]
        var battle: Battle
        var startedAt: Date
        var savedAt: Date
    }

    private var snapshot: Snapshot? {
        guard let battle, !battle.isOver, resignedSide == nil else { return nil }
        return Snapshot(rules: rules, difficulty: difficulty, names: names, battle: battle, startedAt: startedAt, savedAt: .now)
    }

    /// Picks up a saved battle where it left off.
    convenience init(resuming saved: Snapshot) {
        self.init(rules: saved.rules, opponent: saved.difficulty.map(Opponent.computer) ?? .human, names: saved.names)
        battle = saved.battle
        startedAt = saved.startedAt
        fleets = [saved.battle.ocean(.home).fleet, saved.battle.ocean(.away).fleet]
        if isPassAndPlay {
            viewer = saved.battle.current
            stage = .handoff(to: saved.battle.current, purpose: .battle)
        } else {
            viewer = .home
            makeSession(for: .home)
            stage = .battle
            if saved.battle.current == .away {
                Task { await computerTurn() }
            } else {
                session?.beginTurn()
            }
        }
    }

    private func save() {
        if let snapshot { SavedBattle.save(snapshot) } else { SavedBattle.clear() }
    }

    var isPassAndPlay: Bool { opponent == .human }
    var mode: GameMode { isPassAndPlay ? .passAndPlay : .computer }

    var difficulty: AIDifficulty? {
        if case .computer(let difficulty) = opponent { difficulty } else { nil }
    }

    func name(of side: Side) -> String { names[side.rawValue] }

    func rematch() -> LocalGame {
        let game = LocalGame(rules: rules, opponent: opponent, names: names)
        game.onComplete = onComplete
        return game
    }

    // MARK: Deployment

    func deploy(_ fleet: Fleet) {
        guard case .deploying(let side) = stage else { return }
        fleets[side.rawValue] = fleet
        switch (side, opponent) {
        case (.home, .computer(let difficulty)):
            fleets[Side.away.rawValue] = AIAdmiral(difficulty: difficulty).deployFleet(rules: rules, using: &rng)
            startBattle()
        case (.home, .human):
            stage = .handoff(to: .away, purpose: .deploy)
        case (.away, _):
            startBattle()
        }
    }

    private func startBattle() {
        guard let home = fleets[0], let away = fleets[1] else { return }
        battle = Battle(rules: rules, homeFleet: home, awayFleet: away, firstTurn: .home)
        startedAt = .now
        viewer = .home
        save()
        Analytics.shared.capture("game_started", rules.analyticsProperties.merging([
            "mode": .string(mode.rawValue),
            "difficulty": .string(difficulty?.rawValue ?? "none"),
        ]))
        if isPassAndPlay {
            stage = .handoff(to: .home, purpose: .battle)
        } else {
            makeSession(for: .home)
            stage = .battle
            if let session, session.rival != nil {
                session.introLine = director?.line(for: .opening)
                session.showsIntro = true
            }
            session?.beginTurn()
        }
    }

    /// Pass and play: the next player has the phone.
    func handoffAccepted() {
        guard case .handoff(let side, let purpose) = stage else { return }
        viewer = side
        isHidden = false
        switch purpose {
        case .deploy:
            stage = .deploying(side)
        case .battle:
            makeSession(for: side)
            guard let session else { return }
            if let record = pendingIncoming {
                pendingIncoming = nil
                session.status = .resolving
                let staged = session.stage(record.reports, onOcean: true, delay: 0.5)
                stage = .battle
                Task {
                    await session.perform(staged)
                    session.beginTurn()
                }
            } else {
                stage = .battle
                session.beginTurn()
            }
        }
    }

    // MARK: Battle

    private func makeSession(for side: Side) {
        guard let battle else { return }
        let detail: String = switch opponent {
        case .computer(let difficulty): "Computer · \(difficulty.level)"
        case .human: "Pass & Play"
        }
        let session = BattleSession(rules: rules, myName: name(of: side), opponentName: name(of: side.opponent), opponentDetail: detail, ocean: battle.ocean(side))
        if case .computer(let difficulty) = opponent, coach != nil || UserDefaults.standard.flag("rivalChatter", default: true) {
            let rival = Rival.for(difficulty)
            session.rival = rival
            if director == nil { director = RivalDirector(rival: rival) }
        }
        session.coach = coach
        session.onFire = { [weak self] strikes in self?.fire(strikes) }
        session.onResign = { [weak self] in self?.resign() }
        self.session = session
        sync()
    }

    private func sync() {
        guard let battle, let session else { return }
        session.ocean = battle.ocean(viewer)
        session.target = battle.target(viewer)
        session.arsenal = battle.arsenal(viewer)
        session.shotsAllowed = battle.shotsAllowed(viewer)
    }

    private func fire(_ strikes: [Strike]) {
        guard var battle, let session, battle.current == viewer, !battle.isOver else { return }
        let record: TurnRecord
        do {
            record = try battle.fire(strikes, by: viewer)
        } catch {
            Haptics.warning()
            return
        }
        self.battle = battle
        save()
        session.status = .resolving
        sync()
        let staged = session.stage(record.reports, onOcean: false)
        Task {
            await session.perform(staged)
            if self.battle?.isOver == true {
                finish()
            } else if isPassAndPlay {
                pendingIncoming = record
                session.status = .waitingForOpponent
                try? await Task.sleep(for: .seconds(0.5))
                stage = .handoff(to: viewer.opponent, purpose: .battle)
            } else {
                reactToPlayer(record)
                await computerTurn()
            }
        }
    }

    private func reactToPlayer(_ record: TurnRecord) {
        guard var director, let session, let battle else { return }
        let line: RivalLine?
        if let ship = record.sunkShips.last {
            line = battle.ocean(.away).shipsAfloat.count == 1 ? director.line(for: .rivalLastShip) : director.line(for: .playerSank, subject: ship.kind.name.lowercased())
        } else if session.streak >= 3 {
            line = director.line(for: .playerStreak)
        } else if record.hits > 0 {
            line = director.line(for: .playerHit)
        } else {
            line = director.line(for: .playerMissed)
        }
        self.director = director
        session.say(line)
    }

    private func reactToRival(_ record: TurnRecord) {
        guard var director, let session, let battle else { return }
        let line: RivalLine?
        if let ship = record.sunkShips.last {
            line = battle.ocean(.home).shipsAfloat.count == 1 ? director.line(for: .playerLastShip) : director.line(for: .rivalSank, subject: ship.kind.name.lowercased())
        } else if record.hits > 0 {
            line = director.line(for: .rivalHit)
        } else {
            line = director.line(for: .rivalMissed)
        }
        self.director = director
        session.say(line)
    }

    private func computerTurn() async {
        guard case .computer(let difficulty) = opponent, var battle, let session else { return }
        session.status = .opponentAiming
        try? await Task.sleep(for: .seconds(difficulty.thinkingTime + Double.random(in: 0...0.4)))
        guard resignedSide == nil else { return }
        let ai = AIAdmiral(difficulty: difficulty)
        let strikes = ai.chooseVolley(target: battle.target(.away), shotsAllowed: battle.shotsAllowed(.away), arsenal: battle.arsenal(.away), using: &rng)
        guard let record = try? battle.fire(strikes, by: .away) else { return }
        self.battle = battle
        save()
        sync()
        let staged = session.stage(record.reports, onOcean: true)
        await session.perform(staged)
        if battle.isOver {
            finish()
        } else {
            reactToRival(record)
            session.beginTurn()
        }
    }

    /// Called when the player walks away mid-battle. The battle stays saved for later.
    func abandon() {
        guard let battle, !battle.isOver, resignedSide == nil else { return }
        Analytics.shared.capture("game_abandoned", [
            "mode": .string(mode.rawValue),
            "difficulty": .string(difficulty?.rawValue ?? "none"),
            "turns": .int(battle.log.count),
        ].merging(session?.usageProperties ?? [:]))
    }

    func resign() {
        guard let battle, !battle.isOver, resignedSide == nil else { return }
        resignedSide = viewer
        finish()
    }

    private func finish() {
        SavedBattle.clear()
        guard let battle, let session else { return }
        let winner = resignedSide?.opponent ?? battle.winner ?? .home
        let won = winner == viewer
        let stats = battle.stats(for: viewer)
        let duration = Date.now.timeIntervalSince(startedAt)
        session.revealedEnemyFleet = battle.ocean(viewer.opponent).fleet
        session.status = .finished
        let headline: String
        let detail: String
        if isPassAndPlay {
            headline = "\(name(of: winner)) wins"
            detail = resignedSide != nil ? "\(name(of: winner.opponent)) struck their colors." : "Every ship of \(name(of: winner.opponent))'s fleet is down."
        } else if won {
            headline = "Victory"
            detail = "Enemy fleet destroyed in \(stats.turns) turns."
        } else {
            headline = "Defeat"
            detail = resignedSide != nil ? "You struck your colors." : "Your fleet rests on the seabed."
        }
        session.outcome = BattleOutcome(
            won: won || isPassAndPlay,
            headline: headline,
            detail: detail,
            stats: stats,
            shipsLost: battle.ocean(viewer).sunkShips.count,
            turns: stats.turns,
            duration: duration,
            enemyFleet: battle.ocean(viewer.opponent).fleet
        )
        if won || isPassAndPlay { Haptics.victory() } else { Haptics.defeat() }
        let tracker = MedalTracker(replaying: battle.log.map { ($0.side == viewer, $0.reports) })
        let medals = tracker.medals(won: won, rules: rules, beatAdmiral: won && difficulty == .hard)
        session.outcome?.medals = medals
        Analytics.shared.capture("game_finished", rules.analyticsProperties.merging(session.usageProperties).merging([
            "mode": .string(mode.rawValue),
            "difficulty": .string(difficulty?.rawValue ?? "none"),
            "result": .string(resignedSide != nil ? "resigned" : (winner == .home ? "won" : "lost")),
            "turns": .int(battle.log.count),
            "seconds": .int(Int(duration)),
            "medals": .int(medals.count),
        ]))
        if var director {
            let moment: RivalMoment = resignedSide != nil ? .playerResigned : (won ? .rivalLost : .rivalWon)
            let line = director.line(for: moment)
            session.finalLine = line
            session.say(line)
            self.director = director
        }

        let homeStats = battle.stats(for: .home)
        onComplete?(GameSummary(
            mode: mode,
            difficulty: difficulty,
            rules: rules,
            won: winner == .home,
            opponentName: name(of: .away),
            stats: homeStats,
            shipsLost: battle.ocean(.home).sunkShips.count,
            duration: duration,
            verified: nil,
            medals: isPassAndPlay ? [] : medals
        ))
    }

    #if DEBUG
    /// Plays both sides instantly until the enemy has `cellsLeft` ship sections afloat, on our turn.
    func debugFastForward(enemyCellsLeft cellsLeft: Int) -> Coordinate? {
        guard var battle else { return nil }
        let ai = AIAdmiral(difficulty: .hard)
        func remaining() -> [Coordinate] {
            battle.ocean(.away).fleet.ships.flatMap(\.cells).filter { battle.ocean(.away).incoming[$0] != true }
        }
        while !battle.isOver {
            if battle.current == .home, remaining().count <= cellsLeft { break }
            let side = battle.current
            var strikes = ai.chooseVolley(target: battle.target(side), shotsAllowed: battle.shotsAllowed(side), arsenal: battle.arsenal(side), using: &rng)
            // Keep our own fleet mostly afloat for a good-looking finish.
            if side == .away, let miss = battle.target(.away).untargeted.first(where: { battle.ocean(.home).fleet.ship(at: $0) == nil }), Bool.random() {
                strikes = [.shell(miss)]
            }
            guard (try? battle.fire(strikes, by: side)) != nil else { break }
        }
        self.battle = battle
        sync()
        return remaining().first
    }
    #endif
}

/// The one unfinished battle on this device, kept so it survives the app being closed.
enum SavedBattle {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "saved-battle.json")
    }

    static func load() -> LocalGame.Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LocalGame.Snapshot.self, from: data)
    }

    static func save(_ snapshot: LocalGame.Snapshot) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
