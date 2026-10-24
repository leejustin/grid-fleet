import Foundation
import Testing
@testable import GridFleetCore

private func ship(_ kind: ShipKind, _ row: Int, _ column: Int, _ orientation: Orientation = .horizontal) -> PlacedShip {
    PlacedShip(kind: kind, origin: Coordinate(row: row, column: column), orientation: orientation)
}

/// Rows 0, 2, 4, 6, 8 from the left edge.
private let stackedFleet = Fleet(ships: [
    ship(.carrier, 0, 0),
    ship(.cruiser, 2, 0),
    ship(.destroyer, 4, 0),
    ship(.submarine, 6, 0),
    ship(.patrol, 8, 0),
])

@Suite("Coordinates")
struct CoordinateTests {
    @Test func labels() {
        #expect(Coordinate(row: 0, column: 0).label == "A1")
        #expect(Coordinate(row: 9, column: 9).label == "J10")
        #expect(Coordinate(row: 6, column: 1).label == "B7")
    }

    @Test func compactCoding() throws {
        let c = Coordinate(row: 11, column: 7)
        let data = try JSONEncoder().encode(c)
        #expect(String(decoding: data, as: UTF8.self) == "359")
        #expect(try JSONDecoder().decode(Coordinate.self, from: data) == c)
    }
}

@Suite("Placement")
struct PlacementTests {
    @Test func validFleet() {
        #expect(stackedFleet.isValid(for: .classic))
    }

    @Test func outOfBounds() {
        var fleet = stackedFleet
        fleet.place(ship(.carrier, 0, 6))
        #expect(throws: PlacementError.outOfBounds("carrier")) { try fleet.validate(for: .classic) }
    }

    @Test func overlap() {
        var fleet = stackedFleet
        fleet.place(ship(.patrol, 0, 3, .vertical))
        #expect(throws: PlacementError.overlap("carrier")) { try fleet.validate(for: .classic) }
    }

    @Test func touchingOnlyMattersWhenTheRuleIsOn() {
        var fleet = stackedFleet
        fleet.place(ship(.patrol, 1, 5)) // diagonal to the carrier's end at A..E1
        let strict = GameRules(shipsMayTouch: false)
        #expect(fleet.isValid(for: .classic))
        #expect(!fleet.isValid(for: strict))
        // The stacked fleet has a gap row between ships, so it passes the strict rule.
        #expect(stackedFleet.isValid(for: strict))
    }

    @Test func wrongComposition() {
        var fleet = stackedFleet
        fleet.remove(id: "patrol")
        #expect(throws: PlacementError.wrongComposition) { try fleet.validate(for: .classic) }
    }

    @Test(arguments: BoardPreset.allCases, [true, false])
    func randomFleetsAreAlwaysLegal(preset: BoardPreset, mayTouch: Bool) {
        var rng = SeededGenerator(seed: 42)
        let rules = GameRules(preset: preset, shipsMayTouch: mayTouch)
        for style in [FleetLayoutStyle.random, .scattered] {
            for _ in 0..<40 {
                let fleet = Fleet.random(for: rules, style: style, using: &rng)
                #expect(fleet.isValid(for: rules))
            }
        }
    }
}

@Suite("Firing")
struct FiringTests {
    @Test func missHitSunk() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        #expect(try ocean.resolve(.shell(Coordinate(row: 1, column: 0))).outcomes.first?.result == .miss)
        #expect(try ocean.resolve(.shell(Coordinate(row: 8, column: 0))).outcomes.first?.result == .hit)
        let last = try ocean.resolve(.shell(Coordinate(row: 8, column: 1)))
        #expect(last.outcomes.first?.result == .sunk(ship(.patrol, 8, 0)))
        #expect(ocean.sunkShips.map(\.id) == ["patrol"])
    }

    @Test func cannotFireTwiceAtOneCell() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        _ = try ocean.resolve(.shell(Coordinate(row: 5, column: 5)))
        #expect(throws: VolleyError.alreadyTargeted(Coordinate(row: 5, column: 5))) {
            try ocean.resolve(.shell(Coordinate(row: 5, column: 5)))
        }
    }

    @Test func barrageSkipsCellsAlreadyHit() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        _ = try ocean.resolve(.shell(Coordinate(row: 2, column: 1)))
        let report = try ocean.resolve(.barrage(Coordinate(row: 2, column: 2)))
        #expect(report.outcomes.count == 4)
        #expect(report.hits == 2) // C3 and D3 on the cruiser
    }

    @Test func barrageAtCornerIsClipped() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        let report = try ocean.resolve(.barrage(Coordinate(row: 9, column: 9)))
        #expect(report.outcomes.count == 3)
    }

    @Test func torpedoStopsOnFirstShip() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        let report = try ocean.resolve(.torpedo(TorpedoLane(direction: .west, index: 4)))
        // J5 … D5 are water, C5 is the destroyer's tail.
        #expect(report.outcomes.map(\.coordinate.column) == [9, 8, 7, 6, 5, 4, 3, 2])
        #expect(report.outcomes.last?.result == .hit)
        #expect(report.outcomes.dropLast().allSatisfy { $0.result == .miss })
    }

    @Test func torpedoRunsThroughOldHits() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        _ = try ocean.resolve(.shell(Coordinate(row: 4, column: 0)))
        let report = try ocean.resolve(.torpedo(TorpedoLane(direction: .east, index: 4)))
        #expect(report.outcomes.map(\.coordinate.column) == [1])
    }

    @Test func sonarCountsIntactSections() throws {
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        #expect(try ocean.resolve(.sonar(Coordinate(row: 1, column: 1))).sonarContacts == 6)
        _ = try ocean.resolve(.shell(Coordinate(row: 0, column: 0)))
        #expect(try ocean.resolve(.sonar(Coordinate(row: 1, column: 1))).sonarContacts == 5)
        #expect(try ocean.resolve(.sonar(Coordinate(row: 5, column: 8))).sonarContacts == 0)
    }

    @Test func salvoAllowsOneShotPerShipAfloat() {
        let rules = GameRules(firing: .salvo)
        #expect(rules.shotsPerTurn(shipsAfloat: 5, untargetedCells: 100) == 5)
        #expect(rules.shotsPerTurn(shipsAfloat: 2, untargetedCells: 100) == 2)
        #expect(rules.shotsPerTurn(shipsAfloat: 5, untargetedCells: 3) == 3)
        #expect(GameRules.classic.shotsPerTurn(shipsAfloat: 5, untargetedCells: 100) == 1)
    }

    @Test func volleyValidation() {
        let target = TargetBoard(rules: .classic)
        let arsenal = Arsenal(stock: [.sonar: 1])
        let a = Coordinate(row: 0, column: 0)
        #expect(throws: VolleyError.empty) { try target.validate([], shotsAllowed: 1, arsenal: arsenal) }
        #expect(throws: VolleyError.tooManyShots(allowed: 1)) { try target.validate([.shell(a), .shell(a.offset(columns: 1))], shotsAllowed: 1, arsenal: arsenal) }
        #expect(throws: VolleyError.alreadyTargeted(a)) { try target.validate([.shell(a), .shell(a)], shotsAllowed: 3, arsenal: arsenal) }
        #expect(throws: VolleyError.weaponUnavailable(.barrage)) { try target.validate([.barrage(a)], shotsAllowed: 1, arsenal: arsenal) }
        #expect(throws: VolleyError.specialsMustFireAlone) { try target.validate([.sonar(a), .shell(a)], shotsAllowed: 3, arsenal: arsenal) }
        #expect(throws: Never.self) { try target.validate([.sonar(a)], shotsAllowed: 1, arsenal: arsenal) }
    }
}

@Suite("Battle")
struct BattleTests {
    @Test func turnsAlternateAndTheFirstToSinkEverythingWins() throws {
        var rng = SeededGenerator(seed: 7)
        let away = Fleet.random(for: .classic, using: &rng)
        var battle = Battle(rules: .classic, homeFleet: stackedFleet, awayFleet: away)
        #expect(throws: VolleyError.notYourTurn) { try battle.fire([.shell(Coordinate(row: 0, column: 0))], by: .away) }

        let awayCells = away.ships.flatMap(\.cells)
        var homeMisses = Board(size: 10).allCoordinates.filter { stackedFleet.ship(at: $0) == nil }.makeIterator()
        for (i, cell) in awayCells.enumerated() {
            try battle.fire([.shell(cell)], by: .home)
            if i < awayCells.count - 1 {
                #expect(battle.current == .away)
                try battle.fire([.shell(homeMisses.next()!)], by: .away)
            }
        }
        #expect(battle.winner == .home)
        #expect(battle.stats(for: .home).accuracy == 1)
        #expect(throws: VolleyError.gameOver) { try battle.fire([.shell(Coordinate(row: 9, column: 9))], by: .away) }
    }

    @Test func specialsAreSpent() throws {
        let rules = GameRules(specialWeapons: true)
        var battle = Battle(rules: rules, homeFleet: stackedFleet, awayFleet: stackedFleet)
        try battle.fire([.sonar(Coordinate(row: 5, column: 5))], by: .home)
        #expect(battle.arsenal(.home).count(of: .sonar) == 1)
        try battle.fire([.barrage(Coordinate(row: 5, column: 5))], by: .away)
        #expect(!battle.arsenal(.away).has(.barrage))
        try battle.fire([.sonar(Coordinate(row: 5, column: 5))], by: .home)
        try battle.fire([.shell(Coordinate(row: 0, column: 9))], by: .away)
        #expect(throws: VolleyError.weaponUnavailable(.sonar)) { try battle.fire([.sonar(Coordinate(row: 1, column: 5))], by: .home) }
    }
}

@Suite("Commitments")
struct CommitmentTests {
    @Test func sameFleetDifferentSaltGivesDifferentHash() {
        let a = FleetSecret(fleet: stackedFleet)
        let b = FleetSecret(fleet: stackedFleet)
        #expect(a.commitment != b.commitment)
        #expect(a.commitment == FleetSecret(fleet: Fleet(ships: stackedFleet.ships.reversed()), salt: a.salt).commitment)
    }

    @Test func auditCatchesAMovedShip() {
        let secret = FleetSecret(fleet: stackedFleet)
        var moved = secret
        moved.fleet.place(ship(.patrol, 9, 5))
        #expect(FleetAudit.audit(secret: secret, commitment: secret.commitment, rules: .classic, reports: []) == .verified)
        #expect(FleetAudit.audit(secret: moved, commitment: secret.commitment, rules: .classic, reports: []) == .commitmentMismatch)
    }

    @Test func auditCatchesALie() throws {
        let secret = FleetSecret(fleet: stackedFleet)
        var ocean = OceanGrid(rules: .classic, fleet: stackedFleet)
        var reports = [try ocean.resolve(.shell(Coordinate(row: 0, column: 0)))]
        #expect(FleetAudit.audit(secret: secret, commitment: secret.commitment, rules: .classic, reports: reports) == .verified)
        reports[0].outcomes[0].result = .miss
        #expect(FleetAudit.audit(secret: secret, commitment: secret.commitment, rules: .classic, reports: reports) == .falseReport(.shell(Coordinate(row: 0, column: 0))))
    }
}
