import GridFleetCore
import SwiftUI

/// Everything a board view draws, as plain data.
struct BoardScene: Equatable {
    struct ShipDrawing: Equatable {
        var ship: PlacedShip
        var look: ShipLook
        var damaged: Set<Int> = []
    }

    enum Footprint: Equatable {
        case cells([Coordinate])
        case lane(TorpedoLane)
    }

    var size: Int
    var ships: [ShipDrawing] = []
    var marks: [Coordinate: TargetMark] = [:]
    /// Shots fired but not yet answered (online play).
    var inFlight: Set<Coordinate> = []
    var sonar: [SonarReading] = []
    /// Cells aimed at this turn.
    var aims: [Coordinate] = []
    /// A special weapon's area, while aiming it.
    var footprint: Footprint?
    /// Cells hit by the most recent volley, outlined.
    var lastVolley: Set<Coordinate> = []
    /// Deployment: where a dragged ship would land.
    var preview: (cells: [Coordinate], valid: Bool)?
    var showsSweep = false
    var dimmed = false

    static func == (lhs: BoardScene, rhs: BoardScene) -> Bool {
        lhs.size == rhs.size && lhs.ships == rhs.ships && lhs.marks == rhs.marks && lhs.inFlight == rhs.inFlight
            && lhs.sonar == rhs.sonar && lhs.aims == rhs.aims && lhs.footprint == rhs.footprint && lhs.lastVolley == rhs.lastVolley
            && lhs.preview?.cells == rhs.preview?.cells && lhs.preview?.valid == rhs.preview?.valid
            && lhs.showsSweep == rhs.showsSweep && lhs.dimmed == rhs.dimmed
    }

    /// Your view of the enemy: marks, sunk ships, and (after the game) the rest of their fleet.
    static func target(_ board: TargetBoard, inFlight: [Strike] = [], revealed: Fleet? = nil) -> BoardScene {
        var scene = BoardScene(size: board.board.size)
        scene.marks = board.marks
        scene.sonar = board.sonarReadings
        scene.ships = board.sunkShips.map { ShipDrawing(ship: $0, look: .enemySunk) }
        if let revealed {
            let sunk = Set(board.sunkShips.map(\.id))
            scene.ships += revealed.ships.filter { !sunk.contains($0.id) }.map { ship in
                ShipDrawing(ship: ship, look: .enemyGhost, damaged: Set(ship.cells.indices.filter { board.marks[ship.cells[$0]] == .hit }))
            }
        }
        scene.inFlight = Set(inFlight.flatMap { strike -> [Coordinate] in
            switch strike {
            case .shell, .barrage: return strike.footprint(on: board.board)
            case .torpedo, .sonar: return []
            }
        }).filter { board.marks[$0] == nil }
        return scene
    }

    /// Your fleet and the shots that have landed on it.
    static func ocean(_ grid: OceanGrid) -> BoardScene {
        var scene = BoardScene(size: grid.board.size)
        for ship in grid.fleet.ships {
            let sunk = grid.isSunk(ship)
            let damaged = Set(ship.cells.indices.filter { grid.incoming[ship.cells[$0]] == true })
            scene.ships.append(ShipDrawing(ship: ship, look: sunk ? .ownSunk : .own, damaged: damaged))
            if sunk { for cell in ship.cells { scene.marks[cell] = .sunk } }
        }
        for (cell, hit) in grid.incoming where scene.marks[cell] == nil {
            scene.marks[cell] = hit ? .hit : .miss
        }
        return scene
    }
}
