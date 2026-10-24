import GridFleetCore
import SwiftUI

/// Draws a board scene into a Canvas.
struct BoardPainter {
    let scene: BoardScene
    let fx: BoardFX
    let metrics: BoardMetrics
    let theme: Theme
    let skin: ShipSkin
    let blast: BlastStyle
    let now: Date
    let time: Double

    var c: CGFloat { metrics.cell }

    /// Everything that only changes when the board does: cell tint, grid and labels.
    func drawStatic(in context: GraphicsContext) {
        drawCellTint(context)
        drawGrid(context)
        drawLabels(context)
        drawShips(context, pending: false)
    }

    /// Everything that moves or reveals over time. Drawn every frame on top of the static layer.
    func draw(in context: GraphicsContext) {
        drawLastVolley(context)
        drawSonarAreas(context)
        if scene.showsSweep { drawSweep(context) }
        drawShips(context, pending: true)
        drawMarks(context)
        drawInFlight(context)
        drawSonarBadges(context)
        drawFootprint(context)
        drawPreview(context)
        drawAims(context)
        if scene.dimmed {
            context.fill(Path(roundedRect: metrics.gridRect, cornerRadius: c * 0.3), with: .color(.black.opacity(theme.scheme == .dark ? 0.22 : 0.08)))
        }
        drawEffects(context)
    }

    // MARK: Grid

    func drawCellTint(_ ctx: GraphicsContext) {
        guard !theme.isPaper else { return }
        var path = Path()
        for row in 0..<metrics.n {
            for column in 0..<metrics.n where (row + column) % 2 == 0 {
                path.addRect(metrics.rect(Coordinate(row: row, column: column)))
            }
        }
        ctx.fill(path, with: .color(theme.scheme == .dark ? .white.opacity(0.025) : .white.opacity(0.08)))
    }

    func drawGrid(_ ctx: GraphicsContext) {
        let rect = metrics.gridRect
        var lines = Path()
        for i in 1..<metrics.n {
            let x = rect.minX + CGFloat(i) * c
            let y = rect.minY + CGFloat(i) * c
            lines.move(to: CGPoint(x: x, y: rect.minY)); lines.addLine(to: CGPoint(x: x, y: rect.maxY))
            lines.move(to: CGPoint(x: rect.minX, y: y)); lines.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.stroke(lines, with: .color(theme.gridLine), lineWidth: theme.isPaper ? 0.8 : 0.75)
        let border = Path(roundedRect: rect, cornerRadius: c * 0.3, style: .continuous)
        ctx.stroke(border, with: .color(theme.gridLine.opacity(1.8)), lineWidth: 1.2)
    }

    func drawLabels(_ ctx: GraphicsContext) {
        guard metrics.showsLabels else { return }
        let font = Font.coordinate(max(7, c * 0.3))
        for i in 0..<metrics.n {
            let letter = ctx.resolve(Text(String(Coordinate.columnLetters[i])).font(font).foregroundStyle(theme.label))
            ctx.draw(letter, at: CGPoint(x: metrics.gridOrigin.x + (CGFloat(i) + 0.5) * c, y: metrics.gridOrigin.y - metrics.labelBand * 0.5), anchor: .center)
            let number = ctx.resolve(Text("\(i + 1)").font(font).foregroundStyle(theme.label))
            ctx.draw(number, at: CGPoint(x: metrics.gridOrigin.x - metrics.labelBand * 0.5, y: metrics.gridOrigin.y + (CGFloat(i) + 0.5) * c), anchor: .center)
        }
    }

    func drawSweep(_ ctx: GraphicsContext) {
        let rect = metrics.gridRect
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.75
        let angle = Angle.degrees((time * 72).truncatingRemainder(dividingBy: 360))
        var layer = ctx
        layer.clip(to: Path(roundedRect: rect, cornerRadius: c * 0.3))
        layer.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: theme.accent.opacity(0), location: 0),
                    .init(color: theme.accent.opacity(0), location: 0.80),
                    .init(color: theme.accent.opacity(0.16), location: 0.995),
                    .init(color: theme.accent.opacity(0), location: 1),
                ]),
                center: center,
                angle: angle
            )
        )
        // Range rings.
        for i in 1...3 {
            let r = rect.width * 0.16 * CGFloat(i)
            layer.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(theme.accent.opacity(0.05)), lineWidth: 1)
        }
    }

    func drawLastVolley(_ ctx: GraphicsContext) {
        for cell in scene.lastVolley where fx.isRevealed(cell, at: now) {
            ctx.fill(Path(metrics.rect(cell)), with: .color(theme.accent.opacity(0.10)))
        }
    }

    // MARK: Ships

    /// Settled ships go in the static layer; ships with a shell still in the air go in the live one.
    func drawShips(_ ctx: GraphicsContext, pending: Bool) {
        for drawing in scene.ships where fx.isPending(drawing.ship) == pending {
            // A ship sunk this turn appears when the last shell lands.
            if drawing.look == .enemySunk, !fx.isShipRevealed(drawing.ship.id, at: now) { continue }
            var look = drawing.look
            if look == .ownSunk, !fx.isShipRevealed(drawing.ship.id, at: now) { look = .own }
            let damaged = drawing.damaged.filter { fx.isRevealed(drawing.ship.cells[$0], at: now) }
            ShipPainter.draw(
                kind: drawing.ship.kind,
                orientation: drawing.ship.orientation,
                in: metrics.rect(for: drawing.ship),
                context: ctx,
                skin: skin,
                theme: theme,
                look: look,
                damaged: damaged
            )
        }
    }

    // MARK: Marks

    func drawMarks(_ ctx: GraphicsContext) {
        let sunkOwner = Dictionary(scene.ships.filter { $0.look == .enemySunk || $0.look == .ownSunk }.flatMap { d in d.ship.cells.map { ($0, d.ship.id) } }, uniquingKeysWith: { a, _ in a })
        for (cell, mark) in scene.marks {
            guard fx.isRevealed(cell, at: now) else { continue }
            var mark = mark
            if mark == .sunk, let owner = sunkOwner[cell], !fx.isShipRevealed(owner, at: now) { mark = .hit }
            let center = metrics.center(cell)
            switch mark {
            case .miss: drawMiss(ctx, at: center)
            case .hit: drawHit(ctx, at: center, seed: Double(cell.row * 31 + cell.column * 7))
            case .sunk: drawSunk(ctx, at: center, seed: Double(cell.row * 13 + cell.column * 3))
            }
        }
    }

    func circle(_ center: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    func drawMiss(_ ctx: GraphicsContext, at p: CGPoint) {
        if theme.isPaper {
            ctx.stroke(circle(p, c * 0.2), with: .color(theme.miss.opacity(0.8)), lineWidth: 1.3)
            ctx.fill(circle(p, c * 0.05), with: .color(theme.miss.opacity(0.8)))
        } else {
            ctx.stroke(circle(p, c * 0.27), with: .color(theme.miss.opacity(0.22)), lineWidth: 1)
            ctx.fill(circle(p, c * 0.1), with: .color(theme.miss.opacity(0.85)))
        }
    }

    func drawHit(_ ctx: GraphicsContext, at p: CGPoint, seed: Double) {
        if theme.isPaper {
            drawPencilX(ctx, at: p, color: theme.hit)
            return
        }
        let flicker = 0.32 + 0.12 * sin(time * 7 + seed) + 0.06 * sin(time * 17 + seed * 2)
        ctx.fill(circle(p, c * 0.62), with: .radialGradient(Gradient(colors: [theme.hit.opacity(flicker + 0.2), theme.hit.opacity(0)]), center: p, startRadius: 0, endRadius: c * 0.62))
        ctx.stroke(circle(p, c * 0.25), with: .color(theme.hit.opacity(0.9)), lineWidth: max(1.5, c * 0.05))
        ctx.fill(circle(p, c * 0.15), with: .color(theme.hitCore))
    }

    func drawSunk(_ ctx: GraphicsContext, at p: CGPoint, seed: Double) {
        if theme.isPaper {
            drawPencilX(ctx, at: p, color: theme.sunk)
            return
        }
        let flicker = 0.25 + 0.15 * sin(time * 5 + seed)
        ctx.fill(circle(p, c * 0.42), with: .radialGradient(Gradient(colors: [theme.sunk.opacity(flicker), .clear]), center: p, startRadius: 0, endRadius: c * 0.42))
        ctx.fill(circle(p, c * 0.08), with: .color(theme.hitCore.opacity(0.6 + flicker)))
    }

    func drawPencilX(_ ctx: GraphicsContext, at p: CGPoint, color: Color) {
        let r = c * 0.28
        var x = Path()
        x.move(to: CGPoint(x: p.x - r, y: p.y - r)); x.addLine(to: CGPoint(x: p.x + r, y: p.y + r * 0.9))
        x.move(to: CGPoint(x: p.x + r * 0.95, y: p.y - r)); x.addLine(to: CGPoint(x: p.x - r, y: p.y + r))
        ctx.stroke(x, with: .color(color), style: StrokeStyle(lineWidth: max(2, c * 0.08), lineCap: .round))
    }

    func drawInFlight(_ ctx: GraphicsContext) {
        for cell in scene.inFlight {
            let p = metrics.center(cell)
            ctx.stroke(circle(p, c * 0.3), with: .color(theme.accent.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [c * 0.12, c * 0.08], dashPhase: CGFloat(time * 12)))
            let pulse = 0.5 + 0.5 * sin(time * 4)
            ctx.fill(circle(p, c * (0.06 + 0.03 * pulse)), with: .color(theme.accent))
        }
    }

    // MARK: Sonar

    func sonarArea(_ center: Coordinate) -> CGRect {
        let cells = Strike.sonar(center).footprint(on: Board(size: metrics.n))
        return cells.map(metrics.rect).reduce(metrics.rect(center)) { $0.union($1) }
    }

    func drawSonarAreas(_ ctx: GraphicsContext) {
        for reading in scene.sonar where fx.isSonarRevealed(reading.center, at: now) {
            let rect = sonarArea(reading.center).insetBy(dx: 1, dy: 1)
            let tint = reading.contacts > 0 ? theme.hit : theme.accent
            ctx.fill(Path(roundedRect: rect, cornerRadius: c * 0.2), with: .color(tint.opacity(0.08)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: c * 0.2), with: .color(tint.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    func drawSonarBadges(_ ctx: GraphicsContext) {
        for reading in scene.sonar where fx.isSonarRevealed(reading.center, at: now) {
            let p = metrics.center(reading.center)
            let tint = reading.contacts > 0 ? theme.hit : theme.accent
            ctx.fill(circle(p, c * 0.3), with: .color(theme.panel.opacity(0.92)))
            ctx.stroke(circle(p, c * 0.3), with: .color(tint), lineWidth: 1.5)
            let text = ctx.resolve(Text("\(reading.contacts)").font(.coordinate(c * 0.36).weight(.bold)).foregroundStyle(tint))
            ctx.draw(text, at: p, anchor: .center)
        }
    }

    // MARK: Aiming

    func drawFootprint(_ ctx: GraphicsContext) {
        guard let footprint = scene.footprint else { return }
        switch footprint {
        case .cells(let cells):
            for cell in cells {
                let rect = metrics.rect(cell).insetBy(dx: 1.5, dy: 1.5)
                ctx.fill(Path(roundedRect: rect, cornerRadius: c * 0.15), with: .color(theme.accent.opacity(0.22)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: c * 0.15), with: .color(theme.accent.opacity(0.8)), lineWidth: 1.2)
            }
        case .lane(let lane):
            let path = lane.path(on: Board(size: metrics.n))
            guard let first = path.first, let last = path.last else { return }
            let lineRect = path.map(metrics.rect).reduce(metrics.rect(first)) { $0.union($1) }.insetBy(dx: 2, dy: 2)
            ctx.fill(Path(roundedRect: lineRect, cornerRadius: c * 0.3), with: .color(theme.accent.opacity(0.14)))
            // Chevrons showing the direction of travel.
            let start = metrics.center(first)
            let end = metrics.center(last)
            let dx = (end.x - start.x), dy = (end.y - start.y)
            let length = max(1, hypot(dx, dy))
            let ux = dx / length, uy = dy / length
            let phase = CGFloat((time * 1.6).truncatingRemainder(dividingBy: 1))
            var chevrons = Path()
            var d = phase * c
            while d < length {
                let p = CGPoint(x: start.x + ux * d, y: start.y + uy * d)
                let s = c * 0.16
                chevrons.move(to: CGPoint(x: p.x - ux * s - uy * s, y: p.y - uy * s + ux * s))
                chevrons.addLine(to: p)
                chevrons.addLine(to: CGPoint(x: p.x - ux * s + uy * s, y: p.y - uy * s - ux * s))
                d += c
            }
            ctx.stroke(chevrons, with: .color(theme.accent.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    func drawPreview(_ ctx: GraphicsContext) {
        guard let preview = scene.preview else { return }
        let color = preview.valid ? theme.accent : theme.danger
        for cell in preview.cells where cell.row >= 0 && cell.row < metrics.n && cell.column >= 0 && cell.column < metrics.n {
            let rect = metrics.rect(cell).insetBy(dx: 1.5, dy: 1.5)
            ctx.fill(Path(roundedRect: rect, cornerRadius: c * 0.15), with: .color(color.opacity(0.25)))
        }
    }

    func drawAims(_ ctx: GraphicsContext) {
        let breathe = 1 + 0.06 * sin(time * 6)
        for (index, cell) in scene.aims.enumerated() {
            let rect = metrics.rect(cell)
            let p = CGPoint(x: rect.midX, y: rect.midY)
            // Crosshair along the row and column.
            var cross = Path()
            cross.move(to: CGPoint(x: metrics.gridRect.minX, y: p.y)); cross.addLine(to: CGPoint(x: rect.minX, y: p.y))
            cross.move(to: CGPoint(x: rect.maxX, y: p.y)); cross.addLine(to: CGPoint(x: metrics.gridRect.maxX, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: metrics.gridRect.minY)); cross.addLine(to: CGPoint(x: p.x, y: rect.minY))
            cross.move(to: CGPoint(x: p.x, y: rect.maxY)); cross.addLine(to: CGPoint(x: p.x, y: metrics.gridRect.maxY))
            ctx.stroke(cross, with: .color(theme.accent.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // Corner brackets.
            let half = c * 0.5 * breathe + 2
            let arm = c * 0.22
            var brackets = Path()
            for (sx, sy) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] {
                let corner = CGPoint(x: p.x + sx * half, y: p.y + sy * half)
                brackets.move(to: CGPoint(x: corner.x, y: corner.y - sy * arm))
                brackets.addLine(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x - sx * arm, y: corner.y))
            }
            var glow = ctx
            if !theme.isPaper { glow.addFilter(.shadow(color: theme.accent.opacity(0.9), radius: 4)) }
            glow.stroke(brackets, with: .color(theme.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            ctx.fill(circle(p, c * 0.06), with: .color(theme.accent))
            if scene.aims.count > 1 {
                let badge = CGPoint(x: rect.maxX - c * 0.12, y: rect.minY + c * 0.12)
                ctx.fill(circle(badge, c * 0.18), with: .color(theme.accent))
                let label = ctx.resolve(Text("\(index + 1)").font(.coordinate(c * 0.22).weight(.heavy)).foregroundStyle(theme.scheme == .dark ? Color.black : .white))
                ctx.draw(label, at: badge, anchor: .center)
            }
        }
    }

    // MARK: Effects

    func drawEffects(_ ctx: GraphicsContext) {
        for effect in fx.effects {
            let p = effect.progress(at: now)
            guard p >= 0, p <= 1 else { continue }
            var rng = SeededGenerator(seed: effect.seed)
            let center = metrics.center(effect.cell)
            switch effect.kind {
            case .incoming: drawIncoming(ctx, at: center, p: p)
            case .splash: drawSplash(ctx, at: center, p: p, rng: &rng)
            case .blast(let big): drawBlast(ctx, at: center, p: p, big: big, rng: &rng)
            case .torpedo(let path, let stop, let hit): drawTorpedo(ctx, effect: effect, path: path, stopIndex: stop, hit: hit)
            case .sonar: drawSonarPing(ctx, effect: effect, p: p)
            }
        }
    }

    func drawIncoming(_ ctx: GraphicsContext, at target: CGPoint, p: Double) {
        let q = CGFloat(p)
        // Shadow grows as the shell falls.
        ctx.fill(circle(target, c * (0.1 + 0.2 * q)), with: .color(.black.opacity(0.35 * q)))
        let height = c * 2.2 * (1 - q) * (1 - q)
        let shell = CGPoint(x: target.x + c * 0.4 * (1 - q), y: target.y - height)
        let scale = 2.0 - q
        if theme.isPaper {
            var arc = Path()
            arc.move(to: CGPoint(x: target.x + c * 0.9, y: target.y - c * 2.2))
            arc.addQuadCurve(to: shell, control: CGPoint(x: target.x + c * 0.2, y: target.y - c * 2.6))
            ctx.stroke(arc, with: .color(theme.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(circle(shell, c * 0.07 * scale), with: .color(theme.ink))
            return
        }
        var tail = Path()
        tail.move(to: shell)
        tail.addLine(to: CGPoint(x: shell.x + c * 0.3 * (1 - q), y: shell.y - c * 0.7 * (1 - q)))
        ctx.stroke(tail, with: .linearGradient(Gradient(colors: [theme.hitCore.opacity(0.9), .clear]), startPoint: shell, endPoint: CGPoint(x: shell.x + c * 0.3, y: shell.y - c * 0.7)), style: StrokeStyle(lineWidth: c * 0.08 * scale, lineCap: .round))
        var glow = ctx
        glow.addFilter(.shadow(color: theme.hitCore, radius: 6))
        glow.fill(circle(shell, c * 0.08 * scale), with: .color(.white))
    }

    func drawSplash(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, rng: inout SeededGenerator) {
        let color = theme.isPaper ? theme.miss : theme.miss
        for i in 0..<3 {
            let q = CGFloat(min(1, max(0, (p - Double(i) * 0.12) / 0.75)))
            guard q > 0 else { continue }
            let r = c * (0.15 + 0.65 * q)
            ctx.stroke(circle(p0, r), with: .color(color.opacity(Double(1 - q) * 0.75)), lineWidth: max(0.5, c * 0.05 * (1 - q)))
        }
        guard !theme.isPaper else { return }
        let q = CGFloat(min(1, p / 0.7))
        for _ in 0..<9 {
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let speed = CGFloat.random(in: 0.35...0.8, using: &rng)
            let pos = CGPoint(
                x: p0.x + CGFloat(cos(angle)) * c * speed * q,
                y: p0.y - c * 0.9 * speed * q + c * 1.3 * q * q + CGFloat(sin(angle)) * c * 0.15 * q
            )
            ctx.fill(circle(pos, c * 0.045 * (1 - q * 0.6)), with: .color(color.opacity(Double(1 - q))))
        }
    }

    func drawBlast(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, big: Bool, rng: inout SeededGenerator) {
        let scale: CGFloat = big ? 1.35 : 1
        switch theme.isPaper ? .ink : blast {
        case .fireball: drawFireball(ctx, at: p0, p: p, scale: scale, rng: &rng)
        case .ink: drawInk(ctx, at: p0, p: p, scale: scale, rng: &rng)
        case .fireworks: drawFireworks(ctx, at: p0, p: p, scale: scale, rng: &rng)
        case .pixel: drawPixels(ctx, at: p0, p: p, scale: scale, rng: &rng)
        }
    }

    private func easeOut(_ x: CGFloat) -> CGFloat { 1 - pow(1 - x, 3) }

    func drawFireball(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, scale: CGFloat, rng: inout SeededGenerator) {
        let q = CGFloat(p)
        // Flash.
        if q < 0.3 {
            let f = q / 0.3
            let r = c * (0.3 + 1.1 * f) * scale
            ctx.fill(circle(p0, r), with: .radialGradient(
                Gradient(colors: [.white.opacity(Double(1 - f)), theme.hitCore.opacity(Double(1 - f)), theme.hit.opacity(Double(1 - f) * 0.6), .clear]),
                center: p0, startRadius: 0, endRadius: r))
        }
        // Shockwave.
        let ring = c * (0.2 + 1.4 * easeOut(q)) * scale
        ctx.stroke(circle(p0, ring), with: .color(theme.hitCore.opacity(Double(1 - q) * 0.55)), lineWidth: max(0.5, c * 0.07 * (1 - q)))
        // Smoke.
        for _ in 0..<4 {
            let ox = CGFloat.random(in: -0.3...0.3, using: &rng) * c
            let pos = CGPoint(x: p0.x + ox, y: p0.y - c * 0.7 * q)
            let r = c * (0.15 + 0.4 * q) * scale
            ctx.fill(circle(pos, r), with: .color(Color(white: 0.25).opacity(Double(0.35 * (1 - q)))))
        }
        // Embers.
        for _ in 0..<(scale > 1 ? 22 : 14) {
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let speed = CGFloat.random(in: 0.6...1.9, using: &rng) * scale
            let e = easeOut(q)
            let pos = CGPoint(
                x: p0.x + CGFloat(cos(angle)) * c * speed * e,
                y: p0.y + CGFloat(sin(angle)) * c * speed * e + c * 0.8 * q * q
            )
            let color = q < 0.4 ? theme.hitCore : theme.hit
            ctx.fill(circle(pos, c * 0.06 * (1 - q) + 0.5), with: .color(color.opacity(Double(1 - q))))
        }
    }

    func drawInk(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, scale: CGFloat, rng: inout SeededGenerator) {
        let q = CGFloat(p)
        let color = theme.isPaper ? theme.hit : theme.ink
        for i in 0..<7 {
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let distance = CGFloat.random(in: 0...0.45, using: &rng) * c * scale
            let pos = CGPoint(x: p0.x + CGFloat(cos(angle)) * distance * easeOut(q), y: p0.y + CGFloat(sin(angle)) * distance * easeOut(q))
            let r = c * CGFloat.random(in: 0.12...0.32, using: &rng) * easeOut(min(1, q * 2)) * scale
            ctx.fill(circle(pos, r), with: .color(color.opacity(Double(0.75 * (1 - q * q)) * (i == 0 ? 1 : 0.8))))
        }
        // Drips.
        for _ in 0..<3 {
            let x = p0.x + CGFloat.random(in: -0.3...0.3, using: &rng) * c
            var drip = Path()
            drip.move(to: CGPoint(x: x, y: p0.y))
            drip.addLine(to: CGPoint(x: x, y: p0.y + c * 0.6 * easeOut(q)))
            ctx.stroke(drip, with: .color(color.opacity(Double(0.6 * (1 - q)))), style: StrokeStyle(lineWidth: c * 0.06, lineCap: .round))
        }
    }

    func drawFireworks(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, scale: CGFloat, rng: inout SeededGenerator) {
        let q = CGFloat(p)
        if q < 0.15 {
            ctx.fill(circle(p0, c * 0.5 * (q / 0.15)), with: .color(.white.opacity(Double(1 - q / 0.15))))
        }
        for _ in 0..<26 {
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let speed = CGFloat.random(in: 0.9...1.7, using: &rng) * scale
            let hue = Double.random(in: 0...1, using: &rng)
            func position(_ t: CGFloat) -> CGPoint {
                let e = easeOut(t)
                return CGPoint(x: p0.x + CGFloat(cos(angle)) * c * speed * e, y: p0.y + CGFloat(sin(angle)) * c * speed * e + c * 0.6 * t * t)
            }
            var trail = Path()
            trail.move(to: position(max(0, q - 0.12)))
            trail.addLine(to: position(q))
            ctx.stroke(trail, with: .color(Color(hue: hue, saturation: 0.8, brightness: 1).opacity(Double(1 - q))), style: StrokeStyle(lineWidth: max(0.8, c * 0.05), lineCap: .round))
        }
    }

    func drawPixels(_ ctx: GraphicsContext, at p0: CGPoint, p: Double, scale: CGFloat, rng: inout SeededGenerator) {
        // Six frames, like a sprite sheet.
        let frame = CGFloat((p * 6).rounded(.down)) / 6
        let unit = c * 0.14
        let colors = [theme.hitCore, theme.hit, Color(hex: 0xFFD23F), .white]
        for i in 0..<18 {
            let angle = Double.random(in: 0 ..< 2 * .pi, using: &rng)
            let speed = CGFloat.random(in: 0.5...1.6, using: &rng) * scale
            let x = p0.x + CGFloat(cos(angle)) * c * speed * frame
            let y = p0.y + CGFloat(sin(angle)) * c * speed * frame + c * 0.5 * frame * frame
            let snapped = CGPoint(x: (x / unit).rounded() * unit, y: (y / unit).rounded() * unit)
            let size = unit * (1.4 - frame)
            ctx.fill(Path(CGRect(x: snapped.x - size / 2, y: snapped.y - size / 2, width: size, height: size)), with: .color(colors[i % colors.count].opacity(Double(1 - frame))))
        }
    }

    func drawTorpedo(_ ctx: GraphicsContext, effect: BoardEffect, path: [Coordinate], stopIndex: Int, hit: Bool) {
        let elapsed = now.timeIntervalSince(effect.start)
        let perCell = (effect.duration - 0.8) / Double(stopIndex + 1)
        let travelled = min(Double(stopIndex) + 0.5, max(0, (elapsed - 0.2) / perCell - 0.5))
        let fade = max(0, min(1, (effect.duration - elapsed) / 0.6))
        guard let first = path.first, path.count > 1 else { return }
        let startCenter = metrics.center(first)
        let next = metrics.center(path[1])
        let dir = CGPoint(x: (next.x - startCenter.x) / c, y: (next.y - startCenter.y) / c)
        let entry = CGPoint(x: startCenter.x - dir.x * c * 0.5, y: startCenter.y - dir.y * c * 0.5)
        let head = CGPoint(x: startCenter.x + dir.x * c * CGFloat(travelled), y: startCenter.y + dir.y * c * CGFloat(travelled))
        var wake = Path()
        wake.move(to: entry)
        wake.addLine(to: head)
        ctx.stroke(wake, with: .linearGradient(Gradient(colors: [theme.miss.opacity(0), theme.miss.opacity(0.7 * fade)]), startPoint: entry, endPoint: head), style: StrokeStyle(lineWidth: c * 0.16, lineCap: .round))
        if elapsed < effect.duration - 0.6 || !hit {
            var glow = ctx
            if !theme.isPaper { glow.addFilter(.shadow(color: theme.accent, radius: 5)) }
            let angle = atan2(dir.y, dir.x)
            var torpedo = glow
            torpedo.translateBy(x: head.x, y: head.y)
            torpedo.rotate(by: .radians(Double(angle)))
            torpedo.fill(Path(roundedRect: CGRect(x: -c * 0.22, y: -c * 0.07, width: c * 0.44, height: c * 0.14), cornerRadius: c * 0.07), with: .color((theme.isPaper ? theme.ink : theme.hitCore).opacity(fade)))
        }
    }

    func drawSonarPing(_ ctx: GraphicsContext, effect: BoardEffect, p: Double) {
        let center = metrics.center(effect.cell)
        let area = sonarArea(effect.cell)
        let pulse = 0.5 + 0.5 * sin(p * .pi * 6)
        ctx.fill(Path(roundedRect: area, cornerRadius: c * 0.2), with: .color(theme.accent.opacity(0.10 * pulse * (1 - p))))
        for i in 0..<3 {
            let q = CGFloat(min(1, max(0, (p - Double(i) * 0.18) / 0.6)))
            guard q > 0, q < 1 else { continue }
            let r = c * 1.8 * q
            ctx.stroke(circle(center, r), with: .color(theme.accent.opacity(Double(1 - q) * 0.9)), lineWidth: 2)
        }
    }
}
