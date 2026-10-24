import Foundation
import Testing
@testable import GridFleetCore

@Suite("Medals")
struct MedalTests {
    private let patrol = PlacedShip(kind: .patrol, origin: Coordinate(row: 0, column: 0), orientation: .horizontal)

    private func report(_ results: [ShotResult], weapon: Weapon = .shell) -> StrikeReport {
        let strike: Strike = weapon == .torpedo ? .torpedo(TorpedoLane(direction: .east, index: 0)) : .shell(Coordinate(row: 0, column: 0))
        return StrikeReport(strike: strike, outcomes: results.enumerated().map { ShotOutcome(coordinate: Coordinate(row: 0, column: $0.offset), result: $0.element) })
    }

    @Test func streaksResetOnAMiss() {
        var tracker = MedalTracker()
        #expect(tracker.recordOutgoing([report([.hit])]) == 1)
        #expect(tracker.recordOutgoing([report([.hit, .hit])]) == 3)
        #expect(tracker.recordOutgoing([report([.miss])]) == 0)
        #expect(tracker.bestStreak == 3)
        #expect(MedalTracker.streakName(3) == "Hat trick")
        #expect(MedalTracker.streakName(1) == nil)
    }

    @Test func firstBloodOnlyIfYouSinkFirst() {
        var mine = MedalTracker()
        mine.recordOutgoing([report([.hit, .sunk(patrol)])])
        #expect(mine.medals(won: false, rules: .classic, beatAdmiral: false).contains(.firstBlood))

        var late = MedalTracker()
        late.recordIncoming([report([.sunk(patrol)])])
        late.recordOutgoing([report([.sunk(patrol)])])
        #expect(!late.medals(won: false, rules: .classic, beatAdmiral: false).contains(.firstBlood))
    }

    @Test func winningMedals() {
        var tracker = MedalTracker()
        // 17 hits, 3 misses: 85% accuracy, 20 shots on a 100-cell board.
        tracker.recordOutgoing([report(Array(repeating: .hit, count: 5))])
        tracker.recordOutgoing([report([.miss, .miss, .miss])])
        tracker.recordOutgoing([report(Array(repeating: .hit, count: 12))])
        let medals = tracker.medals(won: true, rules: .classic, beatAdmiral: true)
        #expect(Set(medals) == [.broadside, .sharpshooter, .untouched, .swiftVictory, .admiralSlayer])
        #expect(tracker.medals(won: false, rules: .classic, beatAdmiral: false) == [.broadside])
    }

    @Test func comebackAndTorpedo() {
        var tracker = MedalTracker()
        tracker.recordIncoming([report([.sunk(patrol), .sunk(patrol), .sunk(patrol), .sunk(patrol)])])
        tracker.recordOutgoing([report([.miss, .sunk(patrol)], weapon: .torpedo)])
        let medals = tracker.medals(won: true, rules: .classic, beatAdmiral: false)
        #expect(medals.contains(.comeback))
        #expect(medals.contains(.torpedoAce))
        #expect(!medals.contains(.untouched))
    }
}
