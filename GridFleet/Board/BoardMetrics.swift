import CoreGraphics
import GridFleetCore

/// Where each cell sits inside a board view.
struct BoardMetrics: Equatable {
    let n: Int
    let size: CGSize
    let showsLabels: Bool
    let cell: CGFloat
    let labelBand: CGFloat
    let gridOrigin: CGPoint

    init(n: Int, size: CGSize, showsLabels: Bool = true) {
        self.n = n
        self.size = size
        self.showsLabels = showsLabels
        let bandRatio: CGFloat = showsLabels ? 0.62 : 0
        let side = max(1, min(size.width, size.height))
        let cell = max(1, (side / (CGFloat(n) + bandRatio) * 2).rounded(.down) / 2)
        self.cell = cell
        self.labelBand = cell * bandRatio
        let total = cell * CGFloat(n) + labelBand
        self.gridOrigin = CGPoint(
            x: ((size.width - total) / 2).rounded() + labelBand,
            y: ((size.height - total) / 2).rounded() + labelBand
        )
    }

    var gridRect: CGRect {
        CGRect(origin: gridOrigin, size: CGSize(width: cell * CGFloat(n), height: cell * CGFloat(n)))
    }

    func rect(_ c: Coordinate) -> CGRect {
        CGRect(x: gridOrigin.x + CGFloat(c.column) * cell, y: gridOrigin.y + CGFloat(c.row) * cell, width: cell, height: cell)
    }

    func center(_ c: Coordinate) -> CGPoint {
        let r = rect(c)
        return CGPoint(x: r.midX, y: r.midY)
    }

    func rect(for ship: PlacedShip) -> CGRect {
        let length = CGFloat(ship.kind.length) * cell
        return ship.orientation == .horizontal
            ? CGRect(origin: rect(ship.origin).origin, size: CGSize(width: length, height: cell))
            : CGRect(origin: rect(ship.origin).origin, size: CGSize(width: cell, height: length))
    }

    /// The cell under a point, or nil if the point is off the grid.
    func coordinate(at point: CGPoint) -> Coordinate? {
        let column = Int(((point.x - gridOrigin.x) / cell).rounded(.down))
        let row = Int(((point.y - gridOrigin.y) / cell).rounded(.down))
        guard row >= 0, row < n, column >= 0, column < n else { return nil }
        return Coordinate(row: row, column: column)
    }

    /// The nearest cell, even if the point is a little off the grid.
    func nearestCoordinate(to point: CGPoint) -> Coordinate {
        let column = Int(((point.x - gridOrigin.x) / cell).rounded(.down))
        let row = Int(((point.y - gridOrigin.y) / cell).rounded(.down))
        return Coordinate(row: min(max(row, 0), n - 1), column: min(max(column, 0), n - 1))
    }
}
