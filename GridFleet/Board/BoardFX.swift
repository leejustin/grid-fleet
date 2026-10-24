import Foundation
import GridFleetCore

/// A short-lived animation on a board.
struct BoardEffect: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A shell dropping onto a cell.
        case incoming
        case splash
        case blast(big: Bool)
        /// A torpedo running along a path, to `stopIndex` (inclusive).
        case torpedo(path: [Coordinate], stopIndex: Int, hit: Bool)
        case sonar
    }

    let id = UUID()
    let cell: Coordinate
    let kind: Kind
    let start: Date
    let duration: TimeInterval
    /// A per-effect seed so particles differ between explosions.
    let seed: UInt64 = .random(in: 0 ... .max)

    func progress(at date: Date) -> Double {
        (date.timeIntervalSince(start) / duration)
    }

    func isLive(at date: Date) -> Bool {
        let p = progress(at: date)
        return p >= 0 && p <= 1
    }
}

/// Timing for a board: running effects, and marks held back until their shell lands.
struct BoardFX: Equatable {
    var effects: [BoardEffect] = []
    /// A cell's mark is hidden until this time.
    var reveals: [Coordinate: Date] = [:]
    /// A sunk ship is drawn as merely hit until this time.
    var shipReveals: [String: Date] = [:]
    var sonarReveals: [Coordinate: Date] = [:]
    /// The last splash or blast, for the water ripple.
    var lastImpact: (cell: Coordinate, at: Date)?

    static func == (lhs: BoardFX, rhs: BoardFX) -> Bool {
        lhs.effects == rhs.effects && lhs.reveals == rhs.reveals && lhs.shipReveals == rhs.shipReveals
            && lhs.sonarReveals == rhs.sonarReveals && lhs.lastImpact?.cell == rhs.lastImpact?.cell && lhs.lastImpact?.at == rhs.lastImpact?.at
    }

    func isRevealed(_ c: Coordinate, at date: Date) -> Bool {
        guard let reveal = reveals[c] else { return true }
        return date >= reveal
    }

    func isShipRevealed(_ id: String, at date: Date) -> Bool {
        guard let reveal = shipReveals[id] else { return true }
        return date >= reveal
    }

    func isSonarRevealed(_ c: Coordinate, at date: Date) -> Bool {
        guard let reveal = sonarReveals[c] else { return true }
        return date >= reveal
    }

    /// Whether a ship is waiting on a shell to land on it, so it has to be redrawn as time passes.
    func isPending(_ ship: PlacedShip) -> Bool {
        shipReveals[ship.id] != nil || ship.cells.contains { reveals[$0] != nil }
    }

    /// When the last effect or reveal on this board finishes.
    var liveUntil: Date {
        let ends = effects.map { $0.start.addingTimeInterval($0.duration) }
            + Array(reveals.values) + Array(shipReveals.values) + Array(sonarReveals.values)
            + [lastImpact.map { $0.at.addingTimeInterval(0.4) } ?? .distantPast]
        return ends.max() ?? .distantPast
    }

    func hasLiveEffects(at date: Date) -> Bool {
        effects.contains { $0.progress(at: date) <= 1 }
    }

    mutating func prune(at date: Date) {
        effects.removeAll { $0.progress(at: date) > 1 }
        reveals = reveals.filter { $0.value > date }
        shipReveals = shipReveals.filter { $0.value > date }
        sonarReveals = sonarReveals.filter { $0.value > date }
    }

    mutating func reset() { self = BoardFX() }
}

/// A moment in an attack worth reacting to: haptics, a banner, a shake.
struct Beat {
    enum Kind {
        /// A weapon leaving the gun or tube.
        case launch(Weapon)
        case splash
        case hit
        case sunk(PlacedShip)
        case sonar(Int)
    }

    let at: Date
    let kind: Kind
}

/// Turns strike reports into timed effects.
enum Choreographer {
    static let shellFlight: TimeInterval = 0.42

    /// Stages the reports on `fx`, starting at `start`. Returns the beats and when the last one lands.
    static func stage(_ reports: [StrikeReport], on fx: inout BoardFX, board: Board, start: Date, reduceMotion: Bool = false) -> (beats: [Beat], end: Date) {
        var beats: [Beat] = []
        var end = start
        var launch = start
        let stagger = reduceMotion ? 0.05 : 0.16

        func impact(_ outcome: ShotOutcome, at time: Date) {
            fx.reveals[outcome.coordinate] = time
            fx.lastImpact = (outcome.coordinate, time)
            switch outcome.result {
            case .miss:
                fx.effects.append(BoardEffect(cell: outcome.coordinate, kind: .splash, start: time, duration: 1.1))
                beats.append(Beat(at: time, kind: .splash))
            case .hit:
                fx.effects.append(BoardEffect(cell: outcome.coordinate, kind: .blast(big: false), start: time, duration: 1.3))
                beats.append(Beat(at: time, kind: .hit))
            case .sunk(let ship):
                fx.effects.append(BoardEffect(cell: outcome.coordinate, kind: .blast(big: true), start: time, duration: 1.5))
                fx.shipReveals[ship.id] = time
                // Secondary explosions ripple down the hull.
                let ordered = ship.cells.sorted { a, b in
                    abs(a.row - outcome.coordinate.row) + abs(a.column - outcome.coordinate.column) < abs(b.row - outcome.coordinate.row) + abs(b.column - outcome.coordinate.column)
                }
                for (i, cell) in ordered.enumerated() where cell != outcome.coordinate {
                    fx.effects.append(BoardEffect(cell: cell, kind: .blast(big: false), start: time.addingTimeInterval(0.09 * Double(i)), duration: 1.2))
                }
                beats.append(Beat(at: time, kind: .sunk(ship)))
            }
            end = max(end, time.addingTimeInterval(0.35))
        }

        for report in reports {
            switch report.strike {
            case .shell, .barrage:
                let isBarrage = report.strike.weapon == .barrage
                beats.append(Beat(at: launch, kind: .launch(report.strike.weapon)))
                for (i, outcome) in report.outcomes.enumerated() {
                    let fire = launch.addingTimeInterval(isBarrage ? Double(i) * 0.07 : 0)
                    fx.reveals[outcome.coordinate] = fire.addingTimeInterval(shellFlight)
                    fx.effects.append(BoardEffect(cell: outcome.coordinate, kind: .incoming, start: fire, duration: shellFlight))
                    impact(outcome, at: fire.addingTimeInterval(shellFlight))
                }
                launch = launch.addingTimeInterval(stagger)

            case .torpedo(let lane):
                let path = lane.path(on: board)
                let perCell = reduceMotion ? 0.02 : 0.075
                let lastCell = report.outcomes.last?.coordinate
                let stopIndex = lastCell.flatMap { path.firstIndex(of: $0) } ?? path.count - 1
                let hit = report.outcomes.last?.result.isHit ?? false
                let runStart = launch
                beats.append(Beat(at: runStart, kind: .launch(.torpedo)))
                fx.effects.append(BoardEffect(cell: path[0], kind: .torpedo(path: path, stopIndex: stopIndex, hit: hit), start: runStart, duration: 0.2 + perCell * Double(stopIndex + 1) + 0.6))
                for outcome in report.outcomes {
                    let index = path.firstIndex(of: outcome.coordinate) ?? 0
                    let time = runStart.addingTimeInterval(0.2 + perCell * Double(index + 1))
                    if outcome.result.isHit {
                        impact(outcome, at: time)
                    } else {
                        fx.reveals[outcome.coordinate] = time
                        end = max(end, time)
                    }
                }
                if report.outcomes.isEmpty { end = max(end, runStart.addingTimeInterval(0.2 + perCell * Double(path.count))) }
                launch = end

            case .sonar(let center):
                beats.append(Beat(at: launch, kind: .launch(.sonar)))
                fx.effects.append(BoardEffect(cell: center, kind: .sonar, start: launch, duration: 1.6))
                let readout = launch.addingTimeInterval(reduceMotion ? 0.2 : 1.0)
                fx.sonarReveals[center] = readout
                beats.append(Beat(at: readout, kind: .sonar(report.sonarContacts ?? 0)))
                end = max(end, readout.addingTimeInterval(0.4))
                launch = end
            }
        }
        return (beats, end)
    }
}
