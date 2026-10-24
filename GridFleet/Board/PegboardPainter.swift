import GridFleetCore
import SwiftUI

/// How boards are drawn.
enum BoardStyle: String, CaseIterable, Codable {
    /// Night water, glowing hits.
    case water
    /// The folding board game: a plastic grid with peg holes, white pegs for misses, red for hits.
    case pegboard
}

extension EnvironmentValues {
    @Entry var boardStyle: BoardStyle = .water
}

/// Draws a board as a molded plastic pegboard.
struct PegboardPainter {
    let base: BoardPainter

    private var scene: BoardScene { base.scene }
    private var fx: BoardFX { base.fx }
    private var metrics: BoardMetrics { base.metrics }
    private var c: CGFloat { metrics.cell }

    // Plastic colors. Original palette; deliberately not any real product's.
    static let plateLight = Color(hex: 0x3F6690)
    static let plateDark = Color(hex: 0x2A4767)
    static let hole = Color(hex: 0x0F1E31)
    static let whitePeg = (light: Color(hex: 0xFFFFFF), dark: Color(hex: 0xBFC6D0))
    static let redPeg = (light: Color(hex: 0xFF6B6B), dark: Color(hex: 0xA3101C))
    static let shipLight = Color(hex: 0xD3D8DE)
    static let shipDark = Color(hex: 0x87919C)
    static let sunkLight = Color(hex: 0x5A5F66)
    static let sunkDark = Color(hex: 0x2D3036)

    /// The plate, ridges and labels: drawn once per board change.
    func drawStatic(in ctx: GraphicsContext) {
        drawPlate(ctx)
        base.drawLabels(ctx)
        drawShips(ctx, pending: false)
        drawHoles(ctx)
    }

    func draw(in ctx: GraphicsContext) {
        base.drawLastVolley(ctx)
        base.drawSonarAreas(ctx)
        drawShips(ctx, pending: true)
        drawPegs(ctx)
        base.drawInFlight(ctx)
        base.drawSonarBadges(ctx)
        base.drawFootprint(ctx)
        base.drawPreview(ctx)
        base.drawAims(ctx)
        if scene.dimmed {
            ctx.fill(plateShape, with: .color(.black.opacity(0.18)))
        }
        drawEffects(ctx)
    }

    // MARK: Plate

    private var plateRect: CGRect { metrics.gridRect.insetBy(dx: -c * 0.12, dy: -c * 0.12) }
    private var plateShape: Path { Path(roundedRect: plateRect, cornerRadius: c * 0.35, style: .continuous) }

    private func drawPlate(_ ctx: GraphicsContext) {
        let rect = plateRect
        // Drop shadow under the plate.
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: c * 0.35, y: c * 0.15))
        shadow.fill(plateShape, with: .color(Self.plateDark))
        ctx.fill(plateShape, with: .linearGradient(Gradient(colors: [Self.plateLight, Self.plateDark]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // Molded edge: light on top, dark below.
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: c * 0.33, style: .continuous), with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .black.opacity(0.25)]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)), lineWidth: 1.5)
        // Raised ridges between cells.
        let grid = metrics.gridRect
        var ridges = Path()
        for i in 1..<metrics.n {
            let x = grid.minX + CGFloat(i) * c
            let y = grid.minY + CGFloat(i) * c
            ridges.move(to: CGPoint(x: x, y: grid.minY)); ridges.addLine(to: CGPoint(x: x, y: grid.maxY))
            ridges.move(to: CGPoint(x: grid.minX, y: y)); ridges.addLine(to: CGPoint(x: grid.maxX, y: y))
        }
        ctx.stroke(ridges, with: .color(.black.opacity(0.18)), lineWidth: 1)
        ctx.stroke(ridges.offsetBy(dx: 0.75, dy: 0.75), with: .color(.white.opacity(0.06)), lineWidth: 0.75)
    }

    private func drawHoles(_ ctx: GraphicsContext) {
        let occupied = Set(scene.ships.filter { $0.look != .enemyGhost }.flatMap(\.ship.cells))
        let r = c * 0.12
        var holes = Path()
        var rims = Path()
        for cell in Board(size: metrics.n).allCoordinates where !occupied.contains(cell) {
            let p = metrics.center(cell)
            holes.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            rims.addEllipse(in: CGRect(x: p.x - r, y: p.y - r + 0.8, width: r * 2, height: r * 2))
        }
        ctx.fill(rims, with: .color(.white.opacity(0.12)))
        ctx.fill(holes, with: .color(Self.hole))
    }

    // MARK: Ships

    private func drawShips(_ ctx: GraphicsContext, pending: Bool) {
        for drawing in scene.ships where base.fx.isPending(drawing.ship) == pending {
            if drawing.look == .enemySunk, !fx.isShipRevealed(drawing.ship.id, at: base.now) { continue }
            let sunk = (drawing.look == .ownSunk && fx.isShipRevealed(drawing.ship.id, at: base.now)) || drawing.look == .enemySunk
            Self.drawPiece(kind: drawing.ship.kind, orientation: drawing.ship.orientation, in: metrics.rect(for: drawing.ship), context: ctx, sunk: sunk, ghost: drawing.look == .enemyGhost, highlight: drawing.look == .selected ? base.theme.accent : nil)
        }
    }

    /// A plastic ship piece with a peg hole per section.
    static func drawPiece(kind: ShipKind, orientation: Orientation, in rect: CGRect, context ctx: GraphicsContext, sunk: Bool = false, ghost: Bool = false, highlight: Color? = nil, lifted: Bool = false) {
        var piece = ctx
        let horizontal = orientation == .horizontal
        let long = horizontal ? rect.width : rect.height
        let c = horizontal ? rect.height : rect.width
        let L = long - c * 0.12
        let B = c * 0.66
        piece.translateBy(x: rect.midX, y: rect.midY)
        if !horizontal { piece.rotate(by: .degrees(90)) }
        let hull = ShipPainter.hullPath(kind: kind, length: L, beam: B)

        if ghost {
            piece.stroke(hull, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            return
        }
        var shadow = piece
        shadow.addFilter(.shadow(color: .black.opacity(lifted ? 0.55 : 0.5), radius: c * (lifted ? 0.3 : 0.12), x: c * (lifted ? 0.12 : 0.04), y: c * (lifted ? 0.25 : 0.08)))
        shadow.fill(hull, with: .color(sunk ? sunkDark : shipDark))
        piece.fill(hull, with: .linearGradient(
            Gradient(colors: sunk ? [sunkLight, sunkDark] : [shipLight, shipDark]),
            startPoint: CGPoint(x: 0, y: -B / 2), endPoint: CGPoint(x: 0, y: B / 2)
        ))
        piece.stroke(hull, with: .color(highlight ?? .black.opacity(0.35)), lineWidth: highlight == nil ? 1 : 2)
        piece.fill(Path(roundedRect: CGRect(x: -L / 2 + B * 0.4, y: -B * 0.08, width: L - B * 0.9, height: B * 0.16), cornerRadius: B * 0.08), with: .color(.white.opacity(sunk ? 0.05 : 0.25)))
        let r = c * 0.1
        for i in 0..<kind.length {
            let x = -long / 2 + c * (CGFloat(i) + 0.5)
            piece.fill(Path(ellipseIn: CGRect(x: x - r, y: -r, width: r * 2, height: r * 2)), with: .color(Color(hex: 0x3A4048)))
            piece.fill(Path(ellipseIn: CGRect(x: x - r * 0.7, y: -r * 0.7 + r * 0.25, width: r * 1.4, height: r * 1.4)), with: .color(Color(hex: 0x1C1F24)))
        }
    }

    // MARK: Pegs

    private func drawPegs(_ ctx: GraphicsContext) {
        for (cell, mark) in scene.marks {
            guard fx.isRevealed(cell, at: base.now) else { continue }
            drawPeg(ctx, at: metrics.center(cell), red: mark != .miss, scale: 1, lift: 0)
        }
    }

    /// A peg seen from just above: a shadow, a body and a highlight. `lift` raises it off the board while it drops.
    func drawPeg(_ ctx: GraphicsContext, at p: CGPoint, red: Bool, scale: CGFloat, lift: CGFloat, opacity: Double = 1) {
        let colors = red ? Self.redPeg : Self.whitePeg
        let r = c * 0.2 * scale
        var layer = ctx
        layer.opacity = opacity
        // Shadow falls further away as the peg lifts.
        let shadowOffset = c * (0.05 + lift * 0.25)
        layer.fill(Path(ellipseIn: CGRect(x: p.x - r + shadowOffset, y: p.y - r + shadowOffset * 1.3, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.4 * (1 - lift * 0.5))))
        let body = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        layer.fill(body, with: .radialGradient(Gradient(colors: [colors.light, colors.dark]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        layer.stroke(body, with: .color(colors.dark.mix(with: .black, by: 0.35)), lineWidth: 0.8)
        // Top of the peg: a slightly lighter disc and a glint.
        layer.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.7, width: r * 1.24, height: r * 1.1)), with: .color(colors.light.opacity(0.55)))
        layer.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.6, width: r * 0.42, height: r * 0.3)), with: .color(.white.opacity(0.8)))
    }

    // MARK: Effects

    private func drawEffects(_ ctx: GraphicsContext) {
        for effect in fx.effects {
            let p = effect.progress(at: base.now)
            guard p >= 0, p <= 1 else { continue }
            let center = metrics.center(effect.cell)
            switch effect.kind {
            case .incoming:
                // The peg drops in: big and high, then down into the hole.
                let red = scene.marks[effect.cell].map { $0 != .miss } ?? false
                let q = CGFloat(p)
                let ease = q * q
                drawPeg(ctx, at: CGPoint(x: center.x, y: center.y - c * 0.6 * (1 - ease)), red: red, scale: 1.7 - 0.7 * ease, lift: 1 - ease, opacity: Double(min(1, q * 3)))
            case .splash:
                ring(ctx, at: center, p: min(1, p / 0.45), color: .white, size: 0.7)
            case .blast(let big):
                ring(ctx, at: center, p: min(1, p / 0.5), color: Self.redPeg.light, size: big ? 1.4 : 0.8)
            case .torpedo(let path, let stop, let hit):
                base.drawTorpedo(ctx, effect: effect, path: path, stopIndex: stop, hit: hit)
            case .sonar:
                base.drawSonarPing(ctx, effect: effect, p: p)
            }
        }
    }

    private func ring(_ ctx: GraphicsContext, at p: CGPoint, p progress: Double, color: Color, size: CGFloat) {
        guard progress < 1 else { return }
        let q = CGFloat(progress)
        let r = c * (0.22 + size * q)
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(Double(1 - q) * 0.7)), lineWidth: 1.5)
    }
}
