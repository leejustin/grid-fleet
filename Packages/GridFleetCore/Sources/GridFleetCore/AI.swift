import Foundation

public enum AIDifficulty: String, Codable, Sendable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .easy: "Ensign"
        case .medium: "Commander"
        case .hard: "Admiral"
        }
    }

    public var level: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }

    public var blurb: String {
        switch self {
        case .easy: "Fires by instinct. Forgets where it hit."
        case .medium: "Hunts in a pattern, then closes in."
        case .hard: "Maps every place your ships could be."
        }
    }

    /// Seconds the computer "thinks" before firing, so turns feel like turns.
    public var thinkingTime: Double {
        switch self {
        case .easy: 0.7
        case .medium: 0.9
        case .hard: 1.1
        }
    }
}

/// A computer opponent. It only sees what any player would: its own target board.
public struct AIAdmiral: Sendable {
    public var difficulty: AIDifficulty

    public init(difficulty: AIDifficulty) {
        self.difficulty = difficulty
    }

    public func deployFleet(rules: GameRules, using rng: inout some RandomNumberGenerator) -> Fleet {
        Fleet.random(for: rules, style: difficulty == .hard ? .scattered : .random, using: &rng)
    }

    public func chooseVolley(target: TargetBoard, shotsAllowed: Int, arsenal: Arsenal, using rng: inout some RandomNumberGenerator) -> [Strike] {
        let open = target.untargeted
        guard !open.isEmpty else { return [] }

        if let special = chooseSpecial(target: target, arsenal: arsenal, using: &rng) {
            return [special]
        }

        let count = min(shotsAllowed, open.count)
        switch difficulty {
        case .easy:
            return easyShots(target: target, count: count, using: &rng)
        case .medium:
            return mediumShots(target: target, count: count, using: &rng)
        case .hard:
            return hardShots(target: target, count: count, using: &rng)
        }
    }

    // MARK: Easy

    private func easyShots(target: TargetBoard, count: Int, using rng: inout some RandomNumberGenerator) -> [Strike] {
        var picks: [Coordinate] = []
        var available = Set(target.untargeted)
        for _ in 0..<count {
            let followUps = target.openHits.flatMap(\.orthogonalNeighbors).filter(available.contains)
            let pick: Coordinate?
            if !followUps.isEmpty, Double.random(in: 0..<1, using: &rng) < 0.3 {
                pick = followUps.randomElement(using: &rng)
            } else {
                pick = available.randomElement(using: &rng)
            }
            guard let c = pick else { break }
            picks.append(c)
            available.remove(c)
        }
        return picks.map(Strike.shell)
    }

    // MARK: Medium: hunt on a checkerboard, then target around hits.

    private func mediumShots(target: TargetBoard, count: Int, using rng: inout some RandomNumberGenerator) -> [Strike] {
        var picks: [Coordinate] = []
        var available = Set(target.untargeted).subtracting(target.knownEmpty)
        if available.isEmpty { available = Set(target.untargeted) }
        let hits = target.openHits
        let smallest = target.remainingKinds.map(\.length).min() ?? 2

        for _ in 0..<count {
            var candidates = targetCandidates(hits: hits, available: available)
            if candidates.isEmpty {
                candidates = available.filter { ($0.row + $0.column) % smallest == 0 }
            }
            if candidates.isEmpty { candidates = Array(available) }
            guard let c = candidates.randomElement(using: &rng) else { break }
            picks.append(c)
            available.remove(c)
        }
        return picks.map(Strike.shell)
    }

    /// Next cells to try around unsunk hits: extend lines first, else any neighbour.
    private func targetCandidates(hits: [Coordinate], available: Set<Coordinate>) -> [Coordinate] {
        guard !hits.isEmpty else { return [] }
        let hitSet = Set(hits)
        var lineEnds: [Coordinate] = []
        for hit in hits {
            for (dr, dc) in [(0, 1), (1, 0)] {
                let next = hit.offset(rows: dr, columns: dc)
                guard hitSet.contains(next) else { continue }
                // Walk to both ends of this run of hits.
                var forward = next
                while hitSet.contains(forward) { forward = forward.offset(rows: dr, columns: dc) }
                var backward = hit
                while hitSet.contains(backward) { backward = backward.offset(rows: -dr, columns: -dc) }
                lineEnds += [forward, backward].filter(available.contains)
            }
        }
        if !lineEnds.isEmpty { return lineEnds }
        return hits.flatMap(\.orthogonalNeighbors).filter(available.contains)
    }

    // MARK: Hard: probability density over every legal placement.

    private func hardShots(target: TargetBoard, count: Int, using rng: inout some RandomNumberGenerator) -> [Strike] {
        var picks: [Coordinate] = []
        var assumedMisses = Set<Coordinate>()
        for _ in 0..<count {
            let density = Self.density(for: target, excluding: assumedMisses)
            guard let best = Self.best(of: density, using: &rng) else {
                guard let fallback = target.untargeted.first(where: { !assumedMisses.contains($0) }) else { break }
                picks.append(fallback)
                assumedMisses.insert(fallback)
                continue
            }
            picks.append(best)
            // Treat earlier salvo shots as misses so the next shot spreads out.
            assumedMisses.insert(best)
        }
        return picks.map(Strike.shell)
    }

    /// Relative chance that each untargeted cell holds a ship.
    public static func density(for target: TargetBoard, excluding extraBlocked: Set<Coordinate> = []) -> [Coordinate: Double] {
        let board = target.board
        let size = board.size
        let marks = target.marks
        let blocked = target.knownEmpty.union(extraBlocked)
        let openHits = Set(target.openHits)
        let sunkHalo: Set<Coordinate> = target.rules.shipsMayTouch ? [] : Set(target.sunkShips.flatMap(\.halo))
        var density: [Coordinate: Double] = [:]

        for kind in target.remainingKinds {
            for orientation in Orientation.allCases {
                let maxRow = orientation == .vertical ? size - kind.length : size - 1
                let maxColumn = orientation == .horizontal ? size - kind.length : size - 1
                guard maxRow >= 0, maxColumn >= 0 else { continue }
                for row in 0...maxRow {
                    for column in 0...maxColumn {
                        let ship = PlacedShip(kind: kind, origin: Coordinate(row: row, column: column), orientation: orientation)
                        let cells = ship.cells
                        var coveredHits = 0
                        var legal = true
                        for cell in cells {
                            switch marks[cell] {
                            case .miss?, .sunk?:
                                legal = false
                            case .hit?:
                                coveredHits += 1
                            case nil:
                                if blocked.contains(cell) || sunkHalo.contains(cell) { legal = false }
                            }
                            if !legal { break }
                        }
                        guard legal else { continue }
                        if !openHits.isEmpty && coveredHits == 0 {
                            // While chasing a wounded ship, placements through the hits matter far more.
                            accumulate(cells, weight: 1, marks: marks, blocked: blocked, into: &density)
                        } else {
                            accumulate(cells, weight: coveredHits == 0 ? 1 : pow(30, Double(coveredHits)), marks: marks, blocked: blocked, into: &density)
                        }
                    }
                }
            }
        }

        // Sonar contacts make the cells they heard more likely.
        for reading in target.sonarReadings where reading.contacts > 0 {
            let area = Strike.sonar(reading.center).footprint(on: board).filter { marks[$0] == nil && !blocked.contains($0) }
            guard !area.isEmpty else { continue }
            let boost = 1 + Double(reading.contacts) / Double(area.count) * 3
            for cell in area { density[cell, default: 0] *= boost }
        }
        return density
    }

    private static func accumulate(_ cells: [Coordinate], weight: Double, marks: [Coordinate: TargetMark], blocked: Set<Coordinate>, into density: inout [Coordinate: Double]) {
        for cell in cells where marks[cell] == nil && !blocked.contains(cell) {
            density[cell, default: 0] += weight
        }
    }

    private static func best(of density: [Coordinate: Double], using rng: inout some RandomNumberGenerator) -> Coordinate? {
        guard let top = density.values.max(), top > 0 else { return nil }
        let leaders = density.filter { $0.value >= top * 0.999 }.map(\.key).sorted()
        return leaders.randomElement(using: &rng)
    }

    // MARK: Special weapons

    private func chooseSpecial(target: TargetBoard, arsenal: Arsenal, using rng: inout some RandomNumberGenerator) -> Strike? {
        let specials = arsenal.specials
        guard !specials.isEmpty else { return nil }
        let hunting = target.openHits.isEmpty
        let roll = Double.random(in: 0..<1, using: &rng)

        switch difficulty {
        case .easy, .medium:
            let chance = difficulty == .easy ? 0.08 : 0.15
            guard hunting, roll < chance, let weapon = specials.randomElement(using: &rng) else { return nil }
            let open = target.untargeted
            switch weapon {
            case .barrage: return open.randomElement(using: &rng).map(Strike.barrage)
            case .sonar: return open.randomElement(using: &rng).map(Strike.sonar)
            case .torpedo:
                let direction = TorpedoLane.Direction.allCases.randomElement(using: &rng) ?? .east
                return .torpedo(TorpedoLane(direction: direction, index: Int.random(in: 0..<target.board.size, using: &rng)))
            case .shell: return nil
            }

        case .hard:
            guard hunting else { return nil }
            let density = Self.density(for: target)
            let total = density.values.reduce(0, +)
            guard total > 0 else { return nil }
            let board = target.board
            func areaScore(_ strike: Strike) -> Double {
                strike.footprint(on: board).reduce(0) { $0 + density[$1, default: 0] } / total
            }
            // Sonar early, while the ocean is still a mystery.
            if arsenal.has(.sonar), target.shotsFired < board.cellCount / 4, roll < 0.5 {
                let options = board.allCoordinates.filter { $0.row > 0 && $0.column > 0 && $0.row < board.size - 1 && $0.column < board.size - 1 }
                if let pick = options.max(by: { areaScore(.sonar($0)) < areaScore(.sonar($1)) }) { return .sonar(pick) }
            }
            if arsenal.has(.barrage), roll < 0.35 {
                let options = target.untargeted
                if let pick = options.max(by: { areaScore(.barrage($0)) < areaScore(.barrage($1)) }) { return .barrage(pick) }
            }
            if arsenal.has(.torpedo), roll < 0.25 {
                let lanes = TorpedoLane.Direction.allCases.flatMap { d in (0..<board.size).map { TorpedoLane(direction: d, index: $0) } }
                // Score the first few cells the torpedo will cross, since it stops on a hit.
                func laneScore(_ lane: TorpedoLane) -> Double {
                    lane.path(on: board).filter { !target.isTargeted($0) }.prefix(4).reduce(0) { $0 + density[$1, default: 0] }
                }
                if let pick = lanes.max(by: { laneScore($0) < laneScore($1) }) { return .torpedo(pick) }
            }
            return nil
        }
    }
}
