import GridFleetCore
import SwiftUI

/// A square game board: water, grid, ships, marks and effects.
struct BoardView: View {
    let scene: BoardScene
    var fx = BoardFX()
    var showsLabels = true
    var onTap: ((Coordinate) -> Void)?
    /// Read aloud for each cell by VoiceOver.
    var describeCell: ((Coordinate) -> String)?
    /// A cell picked with the keyboard, outlined like a hovered one.
    var highlight: Coordinate?

    @Environment(\.theme) private var theme
    @Environment(\.shipSkin) private var skin
    @Environment(\.blastStyle) private var blast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardStyle) private var style
    @Environment(\.lidLight) private var lidLight
    @State private var hover: Coordinate?

    var body: some View {
        GeometryReader { proxy in
            let metrics = BoardMetrics(n: scene.size, size: proxy.size, showsLabels: showsLabels)
            let budget = MotionBudget.shared
            let aiming = !scene.aims.isEmpty || !scene.inFlight.isEmpty || scene.footprint != nil
            let ambient = budget.allowsAmbient(reduceMotion: reduceMotion)
            // Pegs don't move once they're in, so a pegboard only needs frames while something is happening.
            let idleMotion = ambient && style == .water
            ZStack(alignment: .topLeading) {
                if style == .water { water(metrics: metrics) }
                Canvas { context, _ in
                    let painter = BoardPainter(scene: scene, fx: fx, metrics: metrics, theme: theme, skin: skin, blast: blast, now: .now, time: 0)
                    if style == .pegboard { PegboardPainter(base: painter).drawStatic(in: context) } else { painter.drawStatic(in: context) }
                }
                TimelineView(BoardSchedule(liveUntil: fx.liveUntil, aiming: aiming, idleInterval: idleMotion ? (budget.lowPower ? 1 / 4 : 1 / 12) : nil)) { timeline in
                    let now = timeline.date
                    let time = ambient || aiming ? now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) : 0
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            var calm = scene
                            if !ambient { calm.showsSweep = false }
                            let painter = BoardPainter(scene: calm, fx: fx, metrics: metrics, theme: theme, skin: skin, blast: blast, now: now, time: time)
                            if style == .pegboard {
                                PegboardPainter(base: painter).draw(in: context)
                            } else {
                                Caustics.draw(in: context, rect: metrics.gridRect, time: time, color: theme.caustic, strength: theme.isPaper || !ambient ? 0 : 0.10, scale: metrics.cell / 32)
                                painter.draw(in: context)
                            }
                        }
                    }
                    .modifier(ImpactPunch(impact: fx.lastImpact, now: now, enabled: !reduceMotion))
                }
                if onTap != nil, let cell = highlight ?? hover {
                    let rect = metrics.rect(cell).insetBy(dx: 1.5, dy: 1.5)
                    RoundedRectangle(cornerRadius: metrics.cell * 0.18, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.85), lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: metrics.cell * 0.18, style: .continuous).fill(theme.accent.opacity(0.1)))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.12), value: cell)
                }
                if let lidLight {
                    Canvas { context, _ in
                        let c = metrics.cell
                        lidLight.draw(in: context, rect: metrics.gridRect.insetBy(dx: -c * 0.12, dy: -c * 0.12), cornerRadius: c * 0.35)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard onTap != nil else { return }
                switch phase {
                case .active(let location): hover = metrics.coordinate(at: location)
                case .ended: hover = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let cell = metrics.coordinate(at: value.location) { onTap?(cell) }
                },
                isEnabled: onTap != nil
            )
            // One accessibility element per cell, laid exactly over it, so VoiceOver can point at it.
            // It doesn't take touches; those still reach the board underneath.
            .overlay(alignment: .topLeading) {
                accessibilityGrid(metrics: metrics)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .contain)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func water(metrics: BoardMetrics) -> some View {
        let rect = metrics.gridRect
        let shape = RoundedRectangle(cornerRadius: metrics.cell * 0.3, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [theme.waterShallow, theme.waterDeep], startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(theme.accent.opacity(theme.isPaper ? 0 : 0.18), lineWidth: 1)
                    .blur(radius: 3)
            }
            .shadow(color: .black.opacity(theme.scheme == .dark ? 0.5 : 0.15), radius: 18, y: 10)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    private func accessibilityGrid(metrics: BoardMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Board(size: scene.size).allCoordinates, id: \.self) { cell in
                let rect = metrics.rect(cell)
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(describeCell?(cell) ?? cell.label)
                    .accessibilityAddTraits(onTap != nil ? .isButton : [])
                    .accessibilityAction { onTap?(cell) }
                    .accessibilityIdentifier("cell-\(cell.label)")
            }
        }
    }
}

/// A small jolt when a shell lands, bigger when a ship goes down.
private struct ImpactPunch: ViewModifier {
    let impact: (cell: Coordinate, at: Date)?
    let now: Date
    let enabled: Bool

    func body(content: Content) -> some View {
        let elapsed = impact.map { now.timeIntervalSince($0.at) } ?? -1
        let active = enabled && elapsed >= 0 && elapsed < 0.35
        let k = active ? CGFloat(1 - elapsed / 0.35) : 0
        content
            .scaleEffect(1 - 0.012 * k)
            .offset(y: 2 * k * CGFloat(sin(elapsed * 60)))
    }
}

extension BoardScene {
    /// VoiceOver text for a cell on this board.
    func describe(_ cell: Coordinate) -> String {
        var parts = [cell.label]
        switch marks[cell] {
        case .miss?: parts.append("miss")
        case .hit?: parts.append("hit")
        case .sunk?: parts.append("sunk")
        case nil: if inFlight.contains(cell) { parts.append("shot in flight") }
        }
        if let ship = ships.first(where: { $0.ship.occupies(cell) }), marks[cell] == nil {
            parts.append(ship.ship.kind.name)
        }
        if aims.contains(cell) { parts.append("aimed") }
        return parts.joined(separator: ", ")
    }
}
