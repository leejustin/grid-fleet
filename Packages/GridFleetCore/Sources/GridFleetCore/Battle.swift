import Foundation

public enum Side: Int, Codable, Sendable, CaseIterable {
    case home = 0
    case away = 1

    public var opponent: Side { self == .home ? .away : .home }
}

public struct TurnRecord: Hashable, Codable, Sendable, Identifiable {
    public var number: Int
    public var side: Side
    public var reports: [StrikeReport]

    public var id: Int { number }

    public var hits: Int { reports.reduce(0) { $0 + $1.hits } }
    public var sunkShips: [PlacedShip] { reports.flatMap(\.sunkShips) }
}

/// A game where one device knows both fleets: vs computer, and pass and play.
public struct Battle: Hashable, Codable, Sendable {
    public let rules: GameRules
    public private(set) var oceans: [OceanGrid]
    public private(set) var targets: [TargetBoard]
    public private(set) var arsenals: [Arsenal]
    public private(set) var current: Side
    public private(set) var winner: Side?
    public private(set) var log: [TurnRecord] = []
    public let startedAt: Date

    public init(rules: GameRules, homeFleet: Fleet, awayFleet: Fleet, firstTurn: Side = .home, startedAt: Date = .now) {
        self.rules = rules
        self.oceans = [OceanGrid(rules: rules, fleet: homeFleet), OceanGrid(rules: rules, fleet: awayFleet)]
        self.targets = [TargetBoard(rules: rules), TargetBoard(rules: rules)]
        self.arsenals = [rules.startingArsenal, rules.startingArsenal]
        self.current = firstTurn
        self.startedAt = startedAt
    }

    public func ocean(_ side: Side) -> OceanGrid { oceans[side.rawValue] }
    /// What `side` knows about its opponent.
    public func target(_ side: Side) -> TargetBoard { targets[side.rawValue] }
    public func arsenal(_ side: Side) -> Arsenal { arsenals[side.rawValue] }
    public var isOver: Bool { winner != nil }

    public func shotsAllowed(_ side: Side) -> Int {
        rules.shotsPerTurn(shipsAfloat: ocean(side).shipsAfloat.count, untargetedCells: target(side).untargeted.count)
    }

    public func validate(_ strikes: [Strike], by side: Side) throws {
        guard winner == nil else { throw VolleyError.gameOver }
        guard side == current else { throw VolleyError.notYourTurn }
        try target(side).validate(strikes, shotsAllowed: shotsAllowed(side), arsenal: arsenal(side))
    }

    @discardableResult
    public mutating func fire(_ strikes: [Strike], by side: Side) throws -> TurnRecord {
        try validate(strikes, by: side)
        var defenderOcean = oceans[side.opponent.rawValue]
        var reports: [StrikeReport] = []
        for strike in strikes {
            reports.append(try defenderOcean.resolve(strike))
        }
        oceans[side.opponent.rawValue] = defenderOcean
        for report in reports {
            targets[side.rawValue].record(report)
            arsenals[side.rawValue].spend(report.strike.weapon)
        }
        let record = TurnRecord(number: log.count + 1, side: side, reports: reports)
        log.append(record)
        if defenderOcean.isDefeated {
            winner = side
        } else {
            current = side.opponent
        }
        return record
    }

    public func stats(for side: Side) -> BattleStats {
        BattleStats(turns: log.filter { $0.side == side }, target: target(side))
    }
}

public struct BattleStats: Hashable, Codable, Sendable {
    public var turns: Int
    public var shotsFired: Int
    public var hits: Int
    public var shipsSunk: Int
    /// Longest run of consecutive turns with at least one hit.
    public var bestStreak: Int

    public init(turns: [TurnRecord], target: TargetBoard) {
        self.turns = turns.count
        self.shotsFired = target.shotsFired
        self.hits = target.hitCount
        self.shipsSunk = target.sunkShips.count
        var streak = 0
        var best = 0
        for turn in turns {
            if turn.hits > 0 { streak += 1; best = max(best, streak) } else if turn.reports.contains(where: { $0.sonarContacts == nil }) { streak = 0 }
        }
        self.bestStreak = best
    }

    public var accuracy: Double { shotsFired == 0 ? 0 : Double(hits) / Double(shotsFired) }
}
