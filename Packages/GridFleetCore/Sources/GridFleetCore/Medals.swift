import Foundation

/// Awards for how a battle was won.
public enum Medal: String, Codable, Sendable, CaseIterable, Identifiable {
    case firstBlood
    case hatTrick
    case broadside
    case sharpshooter
    case untouched
    case comeback
    case swiftVictory
    case torpedoAce
    case admiralSlayer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstBlood: "First Blood"
        case .hatTrick: "Hat Trick"
        case .broadside: "Broadside"
        case .sharpshooter: "Sharpshooter"
        case .untouched: "Untouched"
        case .comeback: "Last Ship Standing"
        case .swiftVictory: "Swift Victory"
        case .torpedoAce: "Torpedo Ace"
        case .admiralSlayer: "Admiral Slayer"
        }
    }

    public var criterion: String {
        switch self {
        case .firstBlood: "Sink the first ship of the battle."
        case .hatTrick: "Land three hits in a row."
        case .broadside: "Land five hits in a row."
        case .sharpshooter: "Win with 55% accuracy or better."
        case .untouched: "Win without losing a ship."
        case .comeback: "Win with a single ship afloat."
        case .swiftVictory: "Win using fewer than half the board's cells in shots."
        case .torpedoAce: "Sink a ship with a torpedo."
        case .admiralSlayer: "Defeat Admiral Thorn."
        }
    }

    /// Rarer medals get gold.
    public var tier: Int {
        switch self {
        case .firstBlood, .hatTrick: 0
        case .sharpshooter, .swiftVictory, .torpedoAce, .comeback: 1
        case .broadside, .untouched, .admiralSlayer: 2
        }
    }
}

/// Follows one player's battle, shot by shot, to work out streaks and medals.
public struct MedalTracker: Hashable, Codable, Sendable {
    /// Consecutive hits on the current run.
    public private(set) var streak = 0
    public private(set) var bestStreak = 0
    public private(set) var shotsFired = 0
    public private(set) var hits = 0
    public private(set) var shipsSunk = 0
    public private(set) var shipsLost = 0
    public private(set) var sankFirstShip = false
    public private(set) var torpedoKill = false
    private var anyShipSunkYet = false

    public init() {}

    /// Rebuilds a tracker from a whole battle, in order. `mine` marks this player's own turns.
    public init(replaying turns: [(mine: Bool, reports: [StrikeReport])]) {
        for turn in turns {
            if turn.mine { recordOutgoing(turn.reports) } else { recordIncoming(turn.reports) }
        }
    }

    /// Records your shots landing. Returns the streak afterwards.
    @discardableResult
    public mutating func recordOutgoing(_ reports: [StrikeReport]) -> Int {
        for report in reports {
            for outcome in report.outcomes {
                shotsFired += 1
                if outcome.result.isHit {
                    hits += 1
                    streak += 1
                    bestStreak = max(bestStreak, streak)
                } else {
                    streak = 0
                }
                if case .sunk = outcome.result {
                    shipsSunk += 1
                    if !anyShipSunkYet { sankFirstShip = true }
                    anyShipSunkYet = true
                    if report.strike.weapon == .torpedo { torpedoKill = true }
                }
            }
        }
        return streak
    }

    /// Records the enemy's shots landing on you.
    public mutating func recordIncoming(_ reports: [StrikeReport]) {
        let lost = reports.flatMap(\.sunkShips).count
        if lost > 0 { anyShipSunkYet = true }
        shipsLost += lost
    }

    public var accuracy: Double { shotsFired == 0 ? 0 : Double(hits) / Double(shotsFired) }

    public func medals(won: Bool, rules: GameRules, beatAdmiral: Bool) -> [Medal] {
        var earned: [Medal] = []
        if sankFirstShip { earned.append(.firstBlood) }
        if bestStreak >= 5 { earned.append(.broadside) } else if bestStreak >= 3 { earned.append(.hatTrick) }
        if torpedoKill { earned.append(.torpedoAce) }
        guard won else { return earned }
        if accuracy >= 0.55 { earned.append(.sharpshooter) }
        if shipsLost == 0 { earned.append(.untouched) }
        if shipsLost == rules.fleet.count - 1 { earned.append(.comeback) }
        if shotsFired * 2 < rules.board.cellCount { earned.append(.swiftVictory) }
        if beatAdmiral { earned.append(.admiralSlayer) }
        return earned
    }

    /// A name for a streak worth calling out.
    public static func streakName(_ streak: Int) -> String? {
        switch streak {
        case ..<2: nil
        case 2: "Double tap"
        case 3: "Hat trick"
        case 4: "On fire"
        default: "Broadside!"
        }
    }
}
