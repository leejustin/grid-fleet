import Foundation
import Testing
@testable import GridFleetCore

@Suite("Computer opponents")
struct AITests {
    /// Average shots the AI needs to sink a random fleet, playing alone.
    private func averageShots(_ difficulty: AIDifficulty, rules: GameRules = .classic, games: Int, seed: UInt64) throws -> Double {
        var rng = SeededGenerator(seed: seed)
        let ai = AIAdmiral(difficulty: difficulty)
        var total = 0
        for _ in 0..<games {
            let fleet = Fleet.random(for: rules, using: &rng)
            var battle = Battle(rules: rules, homeFleet: fleet, awayFleet: Fleet.random(for: rules, using: &rng))
            var shots = 0
            while battle.winner == nil {
                let volley = ai.chooseVolley(target: battle.target(.home), shotsAllowed: battle.shotsAllowed(.home), arsenal: battle.arsenal(.home), using: &rng)
                try battle.fire(volley, by: .home)
                shots += 1
                // The other side passes by firing at a cell it hasn't tried.
                if battle.winner == nil, let pass = battle.target(.away).untargeted.first {
                    try battle.fire([.shell(pass)], by: .away)
                }
                if shots > rules.board.cellCount * 2 { Issue.record("AI stalled"); return .infinity }
            }
            total += battle.target(.home).shotsFired
        }
        return Double(total) / Double(games)
    }

    @Test func harderOpponentsNeedFewerShots() throws {
        let easy = try averageShots(.easy, games: 30, seed: 1)
        let medium = try averageShots(.medium, games: 30, seed: 1)
        let hard = try averageShots(.hard, games: 30, seed: 1)
        print("Average shots to win — easy \(easy), medium \(medium), hard \(hard)")
        #expect(hard < medium)
        #expect(medium < easy)
        #expect(hard < 60)
    }

    @Test(arguments: AIDifficulty.allCases)
    func everyOpponentFinishesEveryVariant(difficulty: AIDifficulty) throws {
        for preset in BoardPreset.allCases {
            let rules = GameRules(preset: preset, shipsMayTouch: false, firing: .salvo, specialWeapons: true)
            let shots = try averageShots(difficulty, rules: rules, games: 3, seed: 5)
            #expect(shots <= Double(rules.board.cellCount))
        }
    }

    @Test func neverRepeatsAShot() {
        var rng = SeededGenerator(seed: 3)
        for difficulty in AIDifficulty.allCases {
            var target = TargetBoard(rules: .classic)
            var ocean = OceanGrid(rules: .classic, fleet: .random(for: .classic, using: &rng))
            let ai = AIAdmiral(difficulty: difficulty)
            for _ in 0..<20 {
                let volley = ai.chooseVolley(target: target, shotsAllowed: 3, arsenal: Arsenal(stock: [:]), using: &rng)
                #expect((try? target.validate(volley, shotsAllowed: 3, arsenal: Arsenal(stock: [:]))) != nil)
                for strike in volley { if let report = try? ocean.resolve(strike) { target.record(report) } }
            }
        }
    }
}
