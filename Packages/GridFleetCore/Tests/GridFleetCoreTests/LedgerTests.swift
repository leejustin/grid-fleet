import Foundation
import Testing
@testable import GridFleetCore

@Suite("Match ledger")
struct LedgerTests {
    /// Plays a whole online game between two simulated devices, passing the encoded ledger back and forth.
    @Test(arguments: [GameRules.classic, GameRules(preset: .skirmish, firing: .salvo, specialWeapons: true)])
    func fullGameBetweenTwoDevices(rules: GameRules) throws {
        var rng = SeededGenerator(seed: 99)
        let secrets = [FleetSecret(fleet: .random(for: rules, using: &rng)), FleetSecret(fleet: .random(for: rules, using: &rng))]
        let ai = [AIAdmiral(difficulty: .hard), AIAdmiral(difficulty: .medium)]
        var wire = try MatchLedger(rules: rules).encoded()

        var turns = 0
        while true {
            var ledger = try MatchLedger.decode(wire)
            guard let seat = ledger.actingSeat else { break }
            let secret = secrets[seat]

            if ledger.phase == .reveal {
                try ledger.revealAsWinner(seat: seat, secret: secret)
            } else {
                if !ledger.isDeployed(seat) {
                    try ledger.deploy(seat: seat, secret: secret, playerID: "p\(seat)", displayName: nil)
                }
                try ledger.resolveIncoming(seat: seat, secret: secret)
                if ledger.phase == .battle {
                    let volley = ai[seat].chooseVolley(
                        target: ledger.target(for: seat),
                        shotsAllowed: ledger.shotsAllowed(for: seat, secret: secret),
                        arsenal: ledger.seats[seat].arsenal,
                        using: &rng
                    )
                    try ledger.fire(seat: seat, strikes: volley, secret: secret)
                }
            }
            wire = try ledger.encoded()
            turns += 1
            #expect(turns < 400)
            if turns >= 400 { return }
        }

        let final = try MatchLedger.decode(wire)
        #expect(final.phase == .complete)
        let winner = try #require(final.winner)
        #expect(final.target(for: winner).allSunk)
        #expect(final.audit(of: 0) == .verified)
        #expect(final.audit(of: 1) == .verified)
        #expect(wire.count < 60_000)
    }

    @Test func cannotFireOutOfTurnOrWithShotsPending() throws {
        let secret = FleetSecret(fleet: .random(for: .classic))
        var ledger = MatchLedger(rules: .classic)
        #expect(throws: LedgerError.notDeployed) { try ledger.fire(seat: 0, strikes: [.shell(Coordinate(row: 0, column: 0))], secret: secret) }
        try ledger.deploy(seat: 0, secret: secret, playerID: nil, displayName: nil)
        try ledger.fire(seat: 0, strikes: [.shell(Coordinate(row: 0, column: 0))], secret: secret)
        #expect(throws: LedgerError.notYourTurn) { try ledger.fire(seat: 0, strikes: [.shell(Coordinate(row: 0, column: 1))], secret: secret) }

        let other = FleetSecret(fleet: .random(for: .classic))
        try ledger.deploy(seat: 1, secret: other, playerID: nil, displayName: nil)
        #expect(throws: LedgerError.unresolvedIncoming) { try ledger.fire(seat: 1, strikes: [.shell(Coordinate(row: 0, column: 0))], secret: other) }
        #expect(ledger.strikesInFlight(from: 0).count == 1)
        try ledger.resolveIncoming(seat: 1, secret: other)
        #expect(ledger.strikesInFlight(from: 0).isEmpty)
        #expect(ledger.target(for: 0).shotsFired == 1)
    }

    @Test func resolvingWithTheWrongFleetIsRejected() throws {
        let secret = FleetSecret(fleet: .random(for: .classic))
        var ledger = MatchLedger(rules: .classic)
        try ledger.deploy(seat: 0, secret: secret, playerID: nil, displayName: nil)
        #expect(throws: LedgerError.commitmentMismatch) { try ledger.resolveIncoming(seat: 0, secret: FleetSecret(fleet: secret.fleet)) }
    }

    @Test func resigning() throws {
        let secret = FleetSecret(fleet: .random(for: .classic))
        var ledger = MatchLedger(rules: .classic)
        try ledger.deploy(seat: 0, secret: secret, playerID: nil, displayName: nil)
        ledger.resign(seat: 0, secret: secret)
        #expect(ledger.winner == 1)
        #expect(ledger.actingSeat == nil)
        #expect(ledger.audit(of: 0) == .verified)
    }
}
