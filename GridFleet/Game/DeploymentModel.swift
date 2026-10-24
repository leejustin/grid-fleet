import CoreGraphics
import Foundation
import GridFleetCore
import Observation

/// Ship placement before a battle.
@MainActor
@Observable
final class DeploymentModel {
    struct Drag {
        var kind: ShipKind
        var orientation: Orientation
        /// Finger position in the deployment coordinate space.
        var location: CGPoint
        /// Which section of the ship is under the finger.
        var grabIndex: Int
        /// Where the ship was before the drag, if it came off the board.
        var original: PlacedShip?
    }

    let rules: GameRules
    var fleet = Fleet(ships: [])
    var selectedID: String?
    var drag: Drag?
    /// How ships leave the dock.
    var dockOrientation: Orientation = .horizontal

    // Usability counters, for analytics.
    let openedAt = Date.now
    private(set) var shuffles = 0
    private(set) var drags = 0
    private(set) var rotations = 0
    private(set) var autoPlaces = 0
    private(set) var failedDrops = 0

    var usageProperties: [String: AnalyticsValue] {
        [
            "seconds": .int(Int(Date.now.timeIntervalSince(openedAt))),
            "shuffles": .int(shuffles),
            "drags": .int(drags),
            "rotations": .int(rotations),
            "auto_places": .int(autoPlaces),
            "failed_drops": .int(failedDrops),
        ]
    }

    init(rules: GameRules) {
        self.rules = rules
    }

    var unplaced: [ShipKind] {
        rules.fleet.filter { kind in fleet.ship(id: kind.id) == nil && drag?.kind.id != kind.id }
    }

    var isComplete: Bool { fleet.isValid(for: rules) }

    func randomize() {
        shuffles += 1
        fleet = Fleet.random(for: rules)
        selectedID = nil
        Haptics.hit()
    }

    func clear() {
        fleet = Fleet(ships: [])
        selectedID = nil
        Haptics.tap()
    }

    /// Places a dock ship somewhere legal at random.
    func autoPlace(_ kind: ShipKind) {
        var options: [PlacedShip] = []
        for orientation in Orientation.allCases {
            for cell in rules.board.allCoordinates {
                let ship = PlacedShip(kind: kind, origin: cell, orientation: orientation)
                if fleet.canPlace(ship, rules: rules) { options.append(ship) }
            }
        }
        guard let pick = options.randomElement() else {
            Haptics.warning()
            return
        }
        autoPlaces += 1
        fleet.place(pick)
        selectedID = pick.id
        Haptics.aim()
    }

    /// Turns a ship a quarter turn, nudging it back onto the board if it would hang off.
    func rotate(_ id: String) {
        guard let ship = fleet.ship(id: id) else { return }
        let turned = ship.rotated()
        for shift in 0..<ship.kind.length {
            let candidate = turned.orientation == .horizontal
                ? turned.moved(to: turned.origin.offset(columns: -shift))
                : turned.moved(to: turned.origin.offset(rows: -shift))
            if fleet.canPlace(candidate, rules: rules) {
                rotations += 1
                fleet.place(candidate)
                Haptics.aim()
                return
            }
        }
        Haptics.warning()
    }

    func tap(_ cell: Coordinate) {
        guard let ship = fleet.ship(at: cell) else {
            selectedID = nil
            return
        }
        if selectedID == ship.id {
            rotate(ship.id)
        } else {
            selectedID = ship.id
            Haptics.aim()
        }
    }

    // MARK: Dragging

    func beginDrag(fromBoardAt cell: Coordinate, location: CGPoint) {
        guard let ship = fleet.ship(at: cell) else { return }
        let index = ship.cells.firstIndex(of: cell) ?? 0
        fleet.remove(id: ship.id)
        selectedID = ship.id
        drag = Drag(kind: ship.kind, orientation: ship.orientation, location: location, grabIndex: index, original: ship)
        Haptics.tap()
    }

    func beginDrag(fromDock kind: ShipKind, location: CGPoint) {
        drag = Drag(kind: kind, orientation: dockOrientation, location: location, grabIndex: kind.length / 2, original: nil)
        selectedID = kind.id
        Haptics.tap()
    }

    /// Where the dragged ship would land, given the board's frame in the same coordinate space.
    func candidate(boardFrame: CGRect, lift: CGFloat) -> PlacedShip? {
        guard let drag, boardFrame.width > 0 else { return nil }
        let metrics = BoardMetrics(n: rules.board.size, size: boardFrame.size)
        let local = CGPoint(x: drag.location.x - boardFrame.minX, y: drag.location.y - boardFrame.minY - lift)
        // Allow a little slack around the grid so edge placements are easy.
        guard metrics.gridRect.insetBy(dx: -metrics.cell * 0.8, dy: -metrics.cell * 0.8).contains(local) else { return nil }
        let cell = metrics.nearestCoordinate(to: local)
        let origin = drag.orientation == .horizontal ? cell.offset(columns: -drag.grabIndex) : cell.offset(rows: -drag.grabIndex)
        return PlacedShip(kind: drag.kind, origin: origin, orientation: drag.orientation)
    }

    func endDrag(boardFrame: CGRect, lift: CGFloat) {
        guard let current = drag else { return }
        drags += 1
        if let candidate = candidate(boardFrame: boardFrame, lift: lift), fleet.canPlace(candidate, rules: rules) {
            fleet.place(candidate)
            Haptics.hit()
        } else {
            failedDrops += 1
            if let original = current.original {
                fleet.place(original)
            }
            Haptics.warning()
        }
        drag = nil
    }

}
