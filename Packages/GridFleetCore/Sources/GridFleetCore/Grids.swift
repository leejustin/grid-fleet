import Foundation

/// The defender's side: their own fleet plus every shot that has landed on it.
public struct OceanGrid: Hashable, Codable, Sendable {
    public let rules: GameRules
    public private(set) var fleet: Fleet
    /// Every cell the opponent has fired on, and whether it hit.
    public private(set) var incoming: [Coordinate: Bool]

    public init(rules: GameRules, fleet: Fleet) {
        self.rules = rules
        self.fleet = fleet
        self.incoming = [:]
    }

    public var board: Board { rules.board }

    public func isSunk(_ ship: PlacedShip) -> Bool {
        ship.cells.allSatisfy { incoming[$0] == true }
    }

    public var shipsAfloat: [PlacedShip] { fleet.ships.filter { !isSunk($0) } }
    public var sunkShips: [PlacedShip] { fleet.ships.filter(isSunk) }
    public var isDefeated: Bool { fleet.ships.allSatisfy(isSunk) }

    public func wasTargeted(_ c: Coordinate) -> Bool { incoming[c] != nil }

    /// Resolves a strike against this fleet and records it.
    public mutating func resolve(_ strike: Strike) throws -> StrikeReport {
        switch strike {
        case .shell(let c):
            guard board.contains(c) else { throw VolleyError.offBoard }
            guard incoming[c] == nil else { throw VolleyError.alreadyTargeted(c) }
            return StrikeReport(strike: strike, outcomes: [land(at: c)])

        case .barrage(let c):
            guard board.contains(c) else { throw VolleyError.offBoard }
            let outcomes = strike.footprint(on: board).filter { incoming[$0] == nil }.map { land(at: $0) }
            return StrikeReport(strike: strike, outcomes: outcomes)

        case .torpedo(let lane):
            guard lane.index >= 0, lane.index < board.size else { throw VolleyError.offBoard }
            var outcomes: [ShotOutcome] = []
            for c in lane.path(on: board) where incoming[c] == nil {
                let outcome = land(at: c)
                outcomes.append(outcome)
                if outcome.result.isHit { break }
            }
            return StrikeReport(strike: strike, outcomes: outcomes)

        case .sonar(let c):
            guard board.contains(c) else { throw VolleyError.offBoard }
            let contacts = strike.footprint(on: board).filter { fleet.ship(at: $0) != nil && incoming[$0] != true }.count
            return StrikeReport(strike: strike, outcomes: [], sonarContacts: contacts)
        }
    }

    private mutating func land(at c: Coordinate) -> ShotOutcome {
        guard let ship = fleet.ship(at: c) else {
            incoming[c] = false
            return ShotOutcome(coordinate: c, result: .miss)
        }
        incoming[c] = true
        return ShotOutcome(coordinate: c, result: isSunk(ship) ? .sunk(ship) : .hit)
    }
}

public enum TargetMark: Hashable, Codable, Sendable {
    case miss
    case hit
    case sunk
}

public struct SonarReading: Hashable, Codable, Sendable {
    public var center: Coordinate
    public var contacts: Int

    public init(center: Coordinate, contacts: Int) {
        self.center = center
        self.contacts = contacts
    }
}

/// The attacker's side: what they know about the enemy fleet.
public struct TargetBoard: Hashable, Codable, Sendable {
    public let rules: GameRules
    public private(set) var marks: [Coordinate: TargetMark] = [:]
    public private(set) var sunkShips: [PlacedShip] = []
    public private(set) var sonarReadings: [SonarReading] = []

    public init(rules: GameRules) {
        self.rules = rules
    }

    public var board: Board { rules.board }

    public func isTargeted(_ c: Coordinate) -> Bool { marks[c] != nil }

    public var untargeted: [Coordinate] { board.allCoordinates.filter { marks[$0] == nil } }

    /// Hits on ships that haven't sunk yet.
    public var openHits: [Coordinate] {
        marks.filter { $0.value == .hit }.map(\.key).sorted()
    }

    public var remainingKinds: [ShipKind] {
        let sunk = Set(sunkShips.map(\.id))
        return rules.fleet.filter { !sunk.contains($0.id) }
    }

    public var shotsFired: Int { marks.count }
    public var hitCount: Int { marks.values.filter { $0 != .miss }.count }
    public var allSunk: Bool { sunkShips.count == rules.fleet.count }

    /// Cells that can't hold a ship: zero-contact sonar areas, and (if ships may not touch) cells around sunk ships.
    public var knownEmpty: Set<Coordinate> {
        var empty = Set<Coordinate>()
        for reading in sonarReadings where reading.contacts == 0 {
            empty.formUnion(Strike.sonar(reading.center).footprint(on: board))
        }
        if !rules.shipsMayTouch {
            for ship in sunkShips { empty.formUnion(ship.halo.filter(board.contains)) }
        }
        return empty.filter { marks[$0] == nil }
    }

    public mutating func record(_ report: StrikeReport) {
        if let contacts = report.sonarContacts, case .sonar(let center) = report.strike {
            sonarReadings.append(SonarReading(center: center, contacts: contacts))
        }
        for outcome in report.outcomes {
            switch outcome.result {
            case .miss:
                marks[outcome.coordinate] = .miss
            case .hit:
                marks[outcome.coordinate] = .hit
            case .sunk(let ship):
                for cell in ship.cells { marks[cell] = .sunk }
                if !sunkShips.contains(where: { $0.id == ship.id }) { sunkShips.append(ship) }
            }
        }
    }

    /// Checks a volley before firing it.
    public func validate(_ strikes: [Strike], shotsAllowed: Int, arsenal: Arsenal) throws {
        guard !strikes.isEmpty else { throw VolleyError.empty }
        if let special = strikes.first(where: { $0.weapon.isSpecial }) {
            guard strikes.count == 1 else { throw VolleyError.specialsMustFireAlone }
            guard arsenal.has(special.weapon) else { throw VolleyError.weaponUnavailable(special.weapon) }
            switch special {
            case .barrage(let c), .sonar(let c):
                guard board.contains(c) else { throw VolleyError.offBoard }
            case .torpedo(let lane):
                guard lane.index >= 0, lane.index < board.size else { throw VolleyError.offBoard }
            case .shell:
                break
            }
            return
        }
        guard strikes.count <= max(1, shotsAllowed) else { throw VolleyError.tooManyShots(allowed: shotsAllowed) }
        var seen = Set<Coordinate>()
        for case .shell(let c) in strikes {
            guard board.contains(c) else { throw VolleyError.offBoard }
            guard marks[c] == nil, seen.insert(c).inserted else { throw VolleyError.alreadyTargeted(c) }
        }
    }
}

extension GameRules {
    /// Shots a side may fire this turn, given how many of its own ships are afloat.
    public func shotsPerTurn(shipsAfloat: Int, untargetedCells: Int) -> Int {
        let base = firing == .salvo ? max(1, shipsAfloat) : 1
        return max(1, min(base, untargetedCells))
    }
}
