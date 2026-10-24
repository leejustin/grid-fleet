import Foundation

public enum PlacementError: Error, Equatable, Sendable {
    case outOfBounds(String)
    case overlap(String)
    case touching(String)
    case wrongComposition
}

/// A player's ships.
public struct Fleet: Hashable, Codable, Sendable {
    public var ships: [PlacedShip]

    public init(ships: [PlacedShip]) {
        self.ships = ships
    }

    public func ship(at c: Coordinate) -> PlacedShip? {
        ships.first { $0.occupies(c) }
    }

    public func ship(id: String) -> PlacedShip? {
        ships.first { $0.id == id }
    }

    public var occupiedCells: Set<Coordinate> {
        Set(ships.flatMap(\.cells))
    }

    /// Whether `ship` fits on the board alongside the other ships (ignoring any ship with the same id).
    public func canPlace(_ ship: PlacedShip, rules: GameRules) -> Bool {
        placementProblem(for: ship, rules: rules) == nil
    }

    public func placementProblem(for ship: PlacedShip, rules: GameRules) -> PlacementError? {
        let board = rules.board
        guard ship.cells.allSatisfy(board.contains) else { return .outOfBounds(ship.id) }
        let others = ships.filter { $0.id != ship.id }
        let taken = Set(others.flatMap(\.cells))
        if ship.cells.contains(where: taken.contains) { return .overlap(ship.id) }
        if !rules.shipsMayTouch {
            let halo = ship.halo
            if others.contains(where: { $0.cells.contains(where: halo.contains) }) { return .touching(ship.id) }
        }
        return nil
    }

    /// Replaces the ship with the same id, or adds it.
    public mutating func place(_ ship: PlacedShip) {
        if let index = ships.firstIndex(where: { $0.id == ship.id }) {
            ships[index] = ship
        } else {
            ships.append(ship)
        }
    }

    public mutating func remove(id: String) {
        ships.removeAll { $0.id == id }
    }

    /// Throws if the fleet doesn't match the rules exactly.
    public func validate(for rules: GameRules) throws {
        let expected = rules.fleet.map(\.id).sorted()
        guard ships.map(\.id).sorted() == expected else { throw PlacementError.wrongComposition }
        for (ship, kind) in zip(ships.sorted { $0.id < $1.id }, rules.fleet.sorted { $0.id < $1.id }) where ship.kind != kind {
            throw PlacementError.wrongComposition
        }
        for ship in ships {
            if let problem = placementProblem(for: ship, rules: rules) { throw problem }
        }
    }

    public func isValid(for rules: GameRules) -> Bool {
        (try? validate(for: rules)) != nil
    }
}

public enum FleetLayoutStyle: Sendable {
    /// Uniformly random legal placement.
    case random
    /// Avoids clumps and edge-hugging lines, which strong opponents find faster.
    case scattered
}

extension Fleet {
    /// A random legal fleet. Retries from scratch if it paints itself into a corner.
    public static func random(for rules: GameRules, style: FleetLayoutStyle = .random, using rng: inout some RandomNumberGenerator) -> Fleet {
        switch style {
        case .random:
            return randomAttempt(rules: rules, using: &rng)
        case .scattered:
            var best = randomAttempt(rules: rules, using: &rng)
            var bestScore = best.scatterScore(rules: rules)
            for _ in 0..<24 {
                let candidate = randomAttempt(rules: rules, using: &rng)
                let score = candidate.scatterScore(rules: rules)
                if score > bestScore {
                    best = candidate
                    bestScore = score
                }
            }
            return best
        }
    }

    public static func random(for rules: GameRules, style: FleetLayoutStyle = .random) -> Fleet {
        var rng = SystemRandomNumberGenerator()
        return random(for: rules, style: style, using: &rng)
    }

    private static func randomAttempt(rules: GameRules, using rng: inout some RandomNumberGenerator) -> Fleet {
        let size = rules.board.size
        // Longest first: they're hardest to fit.
        let kinds = rules.fleet.sorted { $0.length > $1.length }
        while true {
            var fleet = Fleet(ships: [])
            // Cells a new ship may not use: other ships, plus their halos when ships may not touch.
            var blocked = Set<Coordinate>()
            var stuck = false
            for kind in kinds {
                var options: [PlacedShip] = []
                for orientation in Orientation.allCases {
                    let maxRow = orientation == .vertical ? size - kind.length : size - 1
                    let maxColumn = orientation == .horizontal ? size - kind.length : size - 1
                    guard maxRow >= 0, maxColumn >= 0 else { continue }
                    for row in 0...maxRow {
                        for column in 0...maxColumn {
                            let ship = PlacedShip(kind: kind, origin: Coordinate(row: row, column: column), orientation: orientation)
                            if !ship.cells.contains(where: blocked.contains) { options.append(ship) }
                        }
                    }
                }
                guard let pick = options.randomElement(using: &rng) else {
                    stuck = true
                    break
                }
                fleet.place(pick)
                blocked.formUnion(pick.cells)
                if !rules.shipsMayTouch { blocked.formUnion(pick.halo) }
            }
            if !stuck { return fleet }
        }
    }

    /// Higher is more spread out: rewards space between ships and penalises ships along the edge.
    func scatterScore(rules: GameRules) -> Double {
        let size = rules.board.size
        var score = 0.0
        for (i, a) in ships.enumerated() {
            for b in ships[(i + 1)...] {
                let distance = a.cells.flatMap { ca in b.cells.map { cb in abs(ca.row - cb.row) + abs(ca.column - cb.column) } }.min() ?? 0
                score += Double(min(distance, 4))
                if distance <= 1 { score -= 3 }
            }
            let edgeCells = a.cells.filter { $0.row == 0 || $0.column == 0 || $0.row == size - 1 || $0.column == size - 1 }.count
            if edgeCells == a.kind.length { score -= 2 }
        }
        return score
    }
}
