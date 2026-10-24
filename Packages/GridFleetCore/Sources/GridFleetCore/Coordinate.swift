import Foundation

/// A cell on a square board. Rows run top to bottom, columns left to right.
/// Columns are lettered (A, B, C…) and rows numbered from 1, so `Coordinate(row: 1, column: 2)` reads "C2".
public struct Coordinate: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static let columnLetters = Array("ABCDEFGHIJKLMNOP")

    public var label: String {
        let letter = column >= 0 && column < Self.columnLetters.count ? String(Self.columnLetters[column]) : "?"
        return "\(letter)\(row + 1)"
    }

    public var description: String { label }

    public func offset(rows dr: Int = 0, columns dc: Int = 0) -> Coordinate {
        Coordinate(row: row + dr, column: column + dc)
    }

    /// The four orthogonal neighbours (some may be off the board).
    public var orthogonalNeighbors: [Coordinate] {
        [offset(rows: -1), offset(columns: 1), offset(rows: 1), offset(columns: -1)]
    }

    /// All eight surrounding cells (some may be off the board).
    public var surroundingCells: [Coordinate] {
        var cells: [Coordinate] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                cells.append(offset(rows: dr, columns: dc))
            }
        }
        return cells
    }

    public static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

// Encoded as a single integer to keep online match data small.
extension Coordinate: Codable {
    public init(from decoder: Decoder) throws {
        let packed = try decoder.singleValueContainer().decode(Int.self)
        self.init(row: packed / 32, column: packed % 32)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(row * 32 + column)
    }
}

/// A square play area.
public struct Board: Hashable, Codable, Sendable {
    public var size: Int

    public init(size: Int) {
        self.size = size
    }

    public func contains(_ c: Coordinate) -> Bool {
        c.row >= 0 && c.row < size && c.column >= 0 && c.column < size
    }

    public var cellCount: Int { size * size }

    public var allCoordinates: [Coordinate] {
        var cells: [Coordinate] = []
        cells.reserveCapacity(cellCount)
        for row in 0..<size {
            for column in 0..<size {
                cells.append(Coordinate(row: row, column: column))
            }
        }
        return cells
    }
}
