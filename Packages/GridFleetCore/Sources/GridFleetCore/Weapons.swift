import Foundation

public enum Weapon: String, Codable, Sendable, CaseIterable, Identifiable {
    case shell
    case barrage
    case torpedo
    case sonar

    public var id: String { rawValue }

    public var isSpecial: Bool { self != .shell }

    public var displayName: String {
        switch self {
        case .shell: "Shell"
        case .barrage: "Barrage"
        case .torpedo: "Torpedo"
        case .sonar: "Sonar Ping"
        }
    }

    public var explanation: String {
        switch self {
        case .shell: "One shot at one cell."
        case .barrage: "Five shots in a plus shape."
        case .torpedo: "Runs along a row or column from the edge and detonates on the first ship it meets."
        case .sonar: "Counts intact ship sections in a 3 × 3 area. Doesn't fire."
        }
    }
}

/// Which way a torpedo runs. It enters from one edge of `index` (a row or column) and travels to the other.
public struct TorpedoLane: Hashable, Codable, Sendable {
    public enum Direction: String, Codable, Sendable, CaseIterable {
        /// Along a row, from column 0 rightwards.
        case east
        /// Along a row, from the last column leftwards.
        case west
        /// Down a column, from row 0.
        case south
        /// Up a column, from the last row.
        case north
    }

    public var direction: Direction
    public var index: Int

    public init(direction: Direction, index: Int) {
        self.direction = direction
        self.index = index
    }

    public func path(on board: Board) -> [Coordinate] {
        let n = board.size
        switch direction {
        case .east: return (0..<n).map { Coordinate(row: index, column: $0) }
        case .west: return (0..<n).reversed().map { Coordinate(row: index, column: $0) }
        case .south: return (0..<n).map { Coordinate(row: $0, column: index) }
        case .north: return (0..<n).reversed().map { Coordinate(row: $0, column: index) }
        }
    }
}

public enum Strike: Hashable, Codable, Sendable {
    case shell(Coordinate)
    case barrage(Coordinate)
    case torpedo(TorpedoLane)
    case sonar(Coordinate)

    public var weapon: Weapon {
        switch self {
        case .shell: .shell
        case .barrage: .barrage
        case .torpedo: .torpedo
        case .sonar: .sonar
        }
    }

    /// The cells a barrage or shell can hit, or the cells a sonar ping listens to.
    public func footprint(on board: Board) -> [Coordinate] {
        switch self {
        case .shell(let c):
            return board.contains(c) ? [c] : []
        case .barrage(let c):
            return ([c] + c.orthogonalNeighbors).filter(board.contains)
        case .torpedo(let lane):
            return lane.path(on: board)
        case .sonar(let c):
            return ([c] + c.surroundingCells).filter(board.contains)
        }
    }
}

public enum ShotResult: Hashable, Codable, Sendable {
    case miss
    case hit
    /// The shot sank this ship. Its position is revealed to the attacker.
    case sunk(PlacedShip)

    public var isHit: Bool {
        if case .miss = self { return false }
        return true
    }
}

public struct ShotOutcome: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    public var result: ShotResult

    public init(coordinate: Coordinate, result: ShotResult) {
        self.coordinate = coordinate
        self.result = result
    }
}

/// The defender's answer to one strike.
public struct StrikeReport: Hashable, Codable, Sendable {
    public var strike: Strike
    public var outcomes: [ShotOutcome]
    /// Only for sonar: intact ship sections inside the 3 × 3 area.
    public var sonarContacts: Int?

    public init(strike: Strike, outcomes: [ShotOutcome], sonarContacts: Int? = nil) {
        self.strike = strike
        self.outcomes = outcomes
        self.sonarContacts = sonarContacts
    }

    public var hits: Int { outcomes.filter(\.result.isHit).count }

    public var sunkShips: [PlacedShip] {
        outcomes.compactMap { if case .sunk(let ship) = $0.result { ship } else { nil } }
    }
}

/// Special weapons left. Shells are unlimited.
public struct Arsenal: Hashable, Codable, Sendable {
    public var stock: [Weapon: Int]

    public init(stock: [Weapon: Int]) {
        self.stock = stock
    }

    public func count(of weapon: Weapon) -> Int {
        weapon == .shell ? .max : stock[weapon, default: 0]
    }

    public func has(_ weapon: Weapon) -> Bool { count(of: weapon) > 0 }

    public var specials: [Weapon] {
        Weapon.allCases.filter { $0.isSpecial && stock[$0, default: 0] > 0 }
    }

    public mutating func spend(_ weapon: Weapon) {
        guard weapon.isSpecial else { return }
        stock[weapon, default: 0] = max(0, stock[weapon, default: 0] - 1)
    }
}

public enum VolleyError: Error, Equatable, Sendable {
    case notYourTurn
    case gameOver
    case empty
    case tooManyShots(allowed: Int)
    case alreadyTargeted(Coordinate)
    case offBoard
    case weaponUnavailable(Weapon)
    case specialsMustFireAlone
    case notDeployed
}
