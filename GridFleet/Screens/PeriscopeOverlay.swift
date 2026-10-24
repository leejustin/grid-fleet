import SwiftUI

/// "Periscope up": a scope rises, its lens opens onto the enemy grid, and the reticle settles.
struct PeriscopeOverlay: View {
    var duration: TimeInterval = 1.7
    let onDone: () -> Void

    @Environment(\.theme) private var theme
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            let p = min(1, timeline.date.timeIntervalSince(start) / duration)
            Canvas { context, size in
                draw(context, size: size, p: p)
            }
        }
        .task {
            start = .now
            try? await Task.sleep(for: .seconds(duration))
            onDone()
        }
        .accessibilityHidden(true)
    }

    private func ease(_ x: Double) -> Double { x < 0 ? 0 : (x > 1 ? 1 : 1 - pow(1 - x, 3)) }

    private func draw(_ ctx: GraphicsContext, size: CGSize, p: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = hypot(size.width, size.height) / 2 + 4
        let rise = ease(p / 0.3)
        let open = ease((p - 0.25) / 0.45)
        let fade = 1 - ease((p - 0.78) / 0.22)

        // Darkness with a lens-shaped hole that widens.
        let lensRadius = 18 + (maxRadius - 18) * open
        var mask = Path(CGRect(origin: .zero, size: size))
        mask.addEllipse(in: CGRect(x: center.x - lensRadius, y: center.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
        ctx.fill(mask, with: .color(.black.opacity(0.92 * fade)), style: FillStyle(eoFill: true))

        // The periscope head rising from below before the lens opens.
        if open < 0.2 {
            let headY = size.height + 40 - (size.height / 2 + 40) * rise
            var tube = Path()
            tube.addRoundedRect(in: CGRect(x: center.x - 10, y: headY + 10, width: 20, height: size.height), cornerSize: CGSize(width: 5, height: 5))
            tube.addRoundedRect(in: CGRect(x: center.x - 22, y: headY - 14, width: 44, height: 28), cornerSize: CGSize(width: 8, height: 8))
            ctx.fill(tube, with: .color(theme.inkSecondary.opacity(0.9 * (1 - open * 5))))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: headY - 9, width: 18, height: 18)), with: .color(theme.accent.opacity(0.9)))
        }

        // Reticle.
        let r = min(size.width, size.height) * 0.36
        let spin = Angle.degrees(40 * (1 - open))
        var reticle = ctx
        reticle.opacity = open * fade
        reticle.translateBy(x: center.x, y: center.y)
        reticle.rotate(by: spin)
        reticle.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(theme.accent.opacity(0.8)), lineWidth: 1.5)
        var ticks = Path()
        for i in 0..<36 {
            let a = Double(i) / 36 * .pi * 2
            let inner = r * (i % 9 == 0 ? 0.86 : 0.94)
            ticks.move(to: CGPoint(x: cos(a) * inner, y: sin(a) * inner))
            ticks.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r))
        }
        reticle.stroke(ticks, with: .color(theme.accent.opacity(0.7)), lineWidth: 1)
        var cross = Path()
        cross.move(to: CGPoint(x: -r * 1.3, y: 0)); cross.addLine(to: CGPoint(x: -r * 0.15, y: 0))
        cross.move(to: CGPoint(x: r * 0.15, y: 0)); cross.addLine(to: CGPoint(x: r * 1.3, y: 0))
        cross.move(to: CGPoint(x: 0, y: -r * 1.3)); cross.addLine(to: CGPoint(x: 0, y: -r * 0.15))
        cross.move(to: CGPoint(x: 0, y: r * 0.15)); cross.addLine(to: CGPoint(x: 0, y: r * 1.3))
        reticle.stroke(cross, with: .color(theme.accent.opacity(0.85)), lineWidth: 1.2)

        // Caption.
        let caption = ctx.resolve(Text("Periscope up").font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent))
        var text = ctx
        text.opacity = ease((p - 0.15) / 0.2) * fade
        text.draw(caption, at: CGPoint(x: center.x, y: center.y + r + 28), anchor: .center)
    }
}
