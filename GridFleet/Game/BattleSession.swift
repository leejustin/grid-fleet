import Foundation
import GridFleetCore
import Observation

struct Banner: Identifiable, Equatable {
    enum Tone { case hit, miss, sunk, info, danger }
    let id = UUID()
    var title: String
    var subtitle: String?
    var tone: Tone
    /// Shown over your fleet rather than the enemy's waters.
    var onOcean: Bool
}

enum TurnStatus: Equatable {
    case yourTurn
    /// The computer or a live opponent is choosing a shot.
    case opponentAiming
    /// An online opponent hasn't played yet.
    case waitingForOpponent
    /// Shots are landing.
    case resolving
    case finished
}

struct BattleOutcome: Equatable {
    var won: Bool
    var headline: String
    var detail: String
    var stats: BattleStats
    var shipsLost: Int
    var turns: Int
    var duration: TimeInterval
    var enemyFleet: Fleet?
    var medals: [Medal] = []
    /// For online games: the check of the opponent's revealed fleet.
    var audit: AuditResult?
    var opponentAudit: AuditResult?
}

/// What the battle screen shows and how the player interacts with it. Every mode drives one of these.
@MainActor
@Observable
final class BattleSession {
    let rules: GameRules
    var myName: String
    var opponentName: String
    var opponentDetail: String

    var ocean: OceanGrid
    var target: TargetBoard
    var inFlight: [Strike] = []
    var arsenal: Arsenal
    var shotsAllowed = 1
    var status: TurnStatus = .yourTurn
    var waitingNote: String?
    var turnDeadline: Date?
    var outcome: BattleOutcome?
    var revealedEnemyFleet: Fleet?

    var lastIncoming: Set<Coordinate> = []
    var lastOutgoing: Set<Coordinate> = []
    var targetFX = BoardFX()
    var oceanFX = BoardFX()
    var banner: Banner?
    /// Increments on each hit to your fleet; drives the shake.
    var oceanShake: CGFloat = 0
    /// Increments when a turn starts, for the periscope.
    var turnStartCount = 0
    /// Increments when the enemy starts firing, so a single-screen layout can swing to your fleet.
    var incomingCount = 0

    // Aiming
    var weapon: Weapon = .shell { didSet { if weapon != oldValue { aims = []; torpedoAlongColumns = false } } }
    var aims: [Coordinate] = []
    var torpedoAlongColumns = false

    var onFire: (([Strike]) -> Void)?
    var onResign: (() -> Void)?

    var reduceMotion = false
    /// Pegboard look: pegs click in instead of shells whistling down.
    var pegStyle = false

    /// Tips for a first game, if this is one.
    var coach: Coach?

    // Rival
    var rival: Rival?
    var rivalLine: RivalLine?
    var rivalMood: RivalMood = .smug
    /// The opening face-off is on screen.
    var showsIntro = false
    var introLine: RivalLine?
    /// The rival's parting words, kept for the result screen.
    var finalLine: RivalLine?
    /// Consecutive hits by this player.
    var streak = 0

    // Usability counters, for analytics.
    /// Taps on cells already fired at.
    var misfireTaps = 0
    /// Times the aim moved before firing: a sign of hesitation or a fiddly target.
    var aimChanges = 0
    var turnStartedAt = Date.now
    private(set) var aimSeconds: [Double] = []

    var medianAimSeconds: Double {
        guard !aimSeconds.isEmpty else { return 0 }
        return aimSeconds.sorted()[aimSeconds.count / 2]
    }

    /// Shows a rival's remark for a few seconds.
    func say(_ line: RivalLine?) {
        guard let line, rival != nil else { return }
        rivalLine = line
        rivalMood = line.mood
        let id = line.id
        Task {
            try? await Task.sleep(for: .seconds(1.6 + Double(line.text.count) * 0.045))
            if self.rivalLine?.id == id { self.rivalLine = nil }
        }
    }

    init(rules: GameRules, myName: String, opponentName: String, opponentDetail: String, ocean: OceanGrid) {
        self.rules = rules
        self.myName = myName
        self.opponentName = opponentName
        self.opponentDetail = opponentDetail
        self.ocean = ocean
        self.target = TargetBoard(rules: rules)
        self.arsenal = rules.startingArsenal
    }

    // MARK: Aiming

    var canAim: Bool { status == .yourTurn }

    /// Strikes the current aim would fire.
    var pendingStrikes: [Strike] {
        switch weapon {
        case .shell: return aims.map(Strike.shell)
        case .barrage: return aims.first.map { [.barrage($0)] } ?? []
        case .sonar: return aims.first.map { [.sonar($0)] } ?? []
        case .torpedo: return torpedoLane.map { [.torpedo($0)] } ?? []
        }
    }

    var torpedoLane: TorpedoLane? {
        guard weapon == .torpedo, let cell = aims.first else { return nil }
        let n = rules.board.size
        if torpedoAlongColumns {
            return TorpedoLane(direction: cell.row < n / 2 ? .south : .north, index: cell.column)
        }
        return TorpedoLane(direction: cell.column < n / 2 ? .east : .west, index: cell.row)
    }

    var shotsToAim: Int { weapon == .shell ? shotsAllowed : 1 }

    var isReadyToFire: Bool {
        guard canAim, !pendingStrikes.isEmpty else { return false }
        return weapon != .shell || aims.count == shotsAllowed
    }

    func tapTarget(_ cell: Coordinate, oneTapFire: Bool) {
        guard canAim else { return }
        switch weapon {
        case .shell:
            guard !target.isTargeted(cell) else {
                misfireTaps += 1
                Haptics.warning()
                return
            }
            if let index = aims.firstIndex(of: cell) {
                if shotsAllowed == 1 {
                    fire()
                } else {
                    aims.remove(at: index)
                    Haptics.aim()
                }
                return
            }
            if shotsAllowed == 1 {
                if !aims.isEmpty { aimChanges += 1 }
                aims = [cell]
                Haptics.aim()
                SoundBoard.shared.play(.aim, volume: 0.6)
                if oneTapFire { fire() }
            } else if aims.count < shotsAllowed {
                aims.append(cell)
                Haptics.aim()
            } else {
                Haptics.warning()
            }
        case .barrage, .sonar, .torpedo:
            if aims.first == cell {
                fire()
            } else {
                aims = [cell]
                Haptics.aim()
            }
        }
    }

    func fire() {
        let strikes = pendingStrikes
        guard canAim, !strikes.isEmpty else { return }
        if weapon == .shell, aims.count < shotsAllowed { return }
        Haptics.fire()
        aimSeconds.append(Date.now.timeIntervalSince(turnStartedAt))
        aims = []
        weapon = .shell
        onFire?(strikes)
    }

    // MARK: Keyboard

    /// The cell a hardware keyboard is pointing at, once the arrow keys have been used.
    var cursor: Coordinate?

    /// Arrow keys. With one shot to place, the aim follows the cursor so Return fires straight away.
    func moveCursor(rows: Int, columns: Int) {
        guard canAim else { return }
        let n = rules.board.size
        let next: Coordinate
        if let current = cursor ?? aims.last {
            next = Coordinate(row: min(n - 1, max(0, current.row + rows)), column: min(n - 1, max(0, current.column + columns)))
        } else {
            next = Coordinate(row: n / 2, column: n / 2)
        }
        cursor = next
        guard shotsToAim == 1 else { return }
        if weapon == .shell, target.isTargeted(next) {
            aims = []
        } else if aims != [next] {
            aims = [next]
            Haptics.aim()
        }
    }

    /// Space: aims at the cursor, or takes the aim back off it.
    func toggleAimAtCursor() {
        guard let cursor else { return moveCursor(rows: 0, columns: 0) }
        tapTarget(cursor, oneTapFire: false)
    }

    /// Return: fires when the aim is complete.
    func fireFromKeyboard() {
        if isReadyToFire {
            fire()
        } else if let cursor {
            tapTarget(cursor, oneTapFire: false)
        }
    }

    /// Number keys pick a weapon, in the order the weapon tray shows them.
    func selectWeapon(at index: Int) {
        let all = Weapon.allCases
        guard canAim, rules.specialWeapons, all.indices.contains(index) else { return }
        let choice = all[index]
        guard choice == .shell || arsenal.count(of: choice) > 0 else { return Haptics.warning() }
        Haptics.aim()
        weapon = choice
        if let cursor, shotsToAim == 1 { aims = [cursor] }
    }

    // MARK: Scenes

    var targetScene: BoardScene {
        var scene = BoardScene.target(target, inFlight: inFlight, revealed: revealedEnemyFleet)
        scene.aims = weapon == .shell ? aims : (weapon == .torpedo ? [] : aims)
        if canAim, let strike = pendingStrikes.first, weapon != .shell {
            switch strike {
            case .torpedo(let lane): scene.footprint = .lane(lane)
            default: scene.footprint = .cells(strike.footprint(on: rules.board))
            }
        }
        scene.lastVolley = lastOutgoing
        scene.showsSweep = status == .yourTurn
        scene.dimmed = status != .yourTurn && status != .finished
        return scene
    }

    var oceanScene: BoardScene {
        var scene = BoardScene.ocean(ocean)
        scene.lastVolley = lastIncoming
        return scene
    }

    // MARK: Playing out shots

    /// Shots staged on a board, waiting to be played out.
    struct StagedShots {
        let beats: [Beat]
        let end: Date
        let onOcean: Bool
    }

    /// Schedules reports landing on the enemy (`onOcean: false`) or on your fleet. Call this in the same
    /// update that changes the boards, so new marks stay hidden until their shells land.
    func stage(_ reports: [StrikeReport], onOcean: Bool, delay: TimeInterval = 0) -> StagedShots {
        let start = Date.now.addingTimeInterval(delay)
        let staged: (beats: [Beat], end: Date)
        if onOcean {
            incomingCount += 1
            lastIncoming = Set(reports.flatMap { $0.outcomes.map(\.coordinate) })
            staged = Choreographer.stage(reports, on: &oceanFX, board: rules.board, start: start.addingTimeInterval(0.25), reduceMotion: reduceMotion)
        } else {
            lastOutgoing = Set(reports.flatMap { $0.outcomes.map(\.coordinate) })
            staged = Choreographer.stage(reports, on: &targetFX, board: rules.board, start: start, reduceMotion: reduceMotion)
        }
        return StagedShots(beats: staged.beats, end: staged.end, onOcean: onOcean)
    }

    /// Plays out staged shots: haptics, banners and shakes on cue. Returns when the last one lands.
    func perform(_ staged: StagedShots) async {
        for beat in staged.beats.sorted(by: { $0.at < $1.at }) {
            let wait = beat.at.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            react(to: beat, onOcean: staged.onOcean)
        }
        let remaining = staged.end.timeIntervalSinceNow
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        pruneEffects()
    }

    private func react(to beat: Beat, onOcean: Bool) {
        let sounds = SoundBoard.shared
        let volume: Float = onOcean ? 1 : 0.85
        switch beat.kind {
        case .launch(let weapon):
            if pegStyle, weapon == .shell || weapon == .barrage { return }
            switch weapon {
            case .shell, .barrage: sounds.play(.whistle, volume: volume * 0.8)
            case .torpedo: sounds.play(.torpedo, volume: volume)
            case .sonar: sounds.play(.sonar, volume: volume)
            }
            return
        case .splash:
            sounds.play(pegStyle ? .peg : .splash, volume: pegStyle ? 0.9 : volume * 0.8)
            Haptics.splash()
            if !onOcean {
                streak = 0
                show(Banner(title: "Miss", tone: .miss, onOcean: false))
            }
        case .hit:
            if pegStyle { sounds.play(.peg) }
            sounds.play(.explosion, volume: pegStyle ? 0.35 : (onOcean ? 1 : 0.8))
            if onOcean {
                Haptics.takeHit()
                oceanShake += 1
                show(Banner(title: "We're hit", tone: .danger, onOcean: true))
            } else {
                Haptics.hit()
                streak += 1
                show(Banner(title: streak > 1 ? "Hit ×\(streak)" : "Hit", subtitle: MedalTracker.streakName(streak), tone: .hit, onOcean: false))
            }
        case .sunk(let ship):
            if pegStyle { sounds.play(.peg) }
            sounds.play(.sunk, volume: pegStyle ? 0.7 : 1)
            Haptics.sunk()
            if onOcean {
                oceanShake += 1
                show(Banner(title: "\(ship.kind.name) lost", tone: .danger, onOcean: true))
            } else {
                streak += 1
                show(Banner(title: "Sunk", subtitle: "Enemy \(ship.kind.name.lowercased()) destroyed", tone: .sunk, onOcean: false))
            }
        case .sonar(let contacts):
            Haptics.aim()
            show(Banner(title: contacts == 0 ? "Silence" : "\(contacts) contact\(contacts == 1 ? "" : "s")", subtitle: "Sonar ping", tone: .info, onOcean: onOcean))
        }
    }

    func show(_ banner: Banner) {
        self.banner = banner
        let id = banner.id
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if self.banner?.id == id { self.banner = nil }
        }
    }

    func beginTurn() {
        status = .yourTurn
        turnStartedAt = .now
        turnStartCount += 1
    }

    /// Properties describing how the player handled this battle.
    var usageProperties: [String: AnalyticsValue] {
        [
            "misfire_taps": .int(misfireTaps),
            "aim_changes": .int(aimChanges),
            "median_aim_seconds": .double((medianAimSeconds * 10).rounded() / 10),
            "shots": .int(target.shotsFired),
            "accuracy": .double((Double(target.hitCount) / Double(max(1, target.shotsFired)) * 100).rounded()),
        ]
    }

    func pruneEffects() {
        targetFX.prune(at: .now)
        oceanFX.prune(at: .now)
    }
}
