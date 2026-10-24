import Foundation

public enum Orientation: String, Codable, Sendable, CaseIterable {
    case horizontal
    case vertical

    public var toggled: Orientation { self == .horizontal ? .vertical : .horizontal }
}

/// A class of ship. `id` is unique within a fleet.
public struct ShipKind: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var length: Int

    public init(id: String, name: String, length: Int) {
        self.id = id
        self.name = name
        self.length = length
    }

    public static let carrier = ShipKind(id: "carrier", name: "Carrier", length: 5)
    public static let cruiser = ShipKind(id: "cruiser", name: "Cruiser", length: 4)
    public static let frigate = ShipKind(id: "frigate", name: "Frigate", length: 4)
    public static let destroyer = ShipKind(id: "destroyer", name: "Destroyer", length: 3)
    public static let submarine = ShipKind(id: "submarine", name: "Submarine", length: 3)
    public static let patrol = ShipKind(id: "patrol", name: "Patrol Boat", length: 2)
}

/// A ship sitting on a board.
public struct PlacedShip: Hashable, Codable, Sendable, Identifiable {
    public var kind: ShipKind
    public var origin: Coordinate
    public var orientation: Orientation

    public init(kind: ShipKind, origin: Coordinate, orientation: Orientation) {
        self.kind = kind
        self.origin = origin
        self.orientation = orientation
    }

    public var id: String { kind.id }

    public var cells: [Coordinate] {
        (0..<kind.length).map { i in
            orientation == .horizontal ? origin.offset(columns: i) : origin.offset(rows: i)
        }
    }

    public func occupies(_ c: Coordinate) -> Bool {
        switch orientation {
        case .horizontal:
            c.row == origin.row && c.column >= origin.column && c.column < origin.column + kind.length
        case .vertical:
            c.column == origin.column && c.row >= origin.row && c.row < origin.row + kind.length
        }
    }

    /// Cells touching the ship, including diagonals, that are not part of it.
    public var halo: Set<Coordinate> {
        let own = Set(cells)
        return Set(cells.flatMap(\.surroundingCells)).subtracting(own)
    }

    public func moved(to origin: Coordinate) -> PlacedShip {
        PlacedShip(kind: kind, origin: origin, orientation: orientation)
    }

    public func rotated() -> PlacedShip {
        PlacedShip(kind: kind, origin: origin, orientation: orientation.toggled)
    }
}
