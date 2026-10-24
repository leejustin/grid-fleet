import SwiftUI

/// Moving light filaments, like sun through waves. Drawn into a Canvas.
enum Caustics {
    static func draw(in context: GraphicsContext, rect: CGRect, time: Double, color: Color, strength: Double, scale: CGFloat = 1) {
        guard strength > 0, rect.width > 0 else { return }
        var layer = context
        layer.clip(to: Path(rect))
        layer.addFilter(.blur(radius: 1.6 * scale))
        let step = max(6, rect.width / 36)
        let spacing = 34 * scale
        let rows = Int(rect.height / spacing) + 2
        for i in 0..<rows {
            let base = rect.minY + CGFloat(i) * spacing - spacing / 2
            let phase = Double(i) * 1.7
            var path = Path()
            var x = rect.minX
            path.move(to: CGPoint(x: x, y: base + wave(x: x, t: time, phase: phase, scale: scale)))
            while x <= rect.maxX + step {
                x += step
                path.addLine(to: CGPoint(x: x, y: base + wave(x: x, t: time, phase: phase, scale: scale)))
            }
            let shimmer = 0.6 + 0.4 * sin(time * 0.9 + phase)
            layer.stroke(path, with: .color(color.opacity(strength * shimmer)), lineWidth: 1.4 * scale)
        }
    }

    private static func wave(x: CGFloat, t: Double, phase: Double, scale: CGFloat) -> CGFloat {
        let u = Double(x / scale)
        return CGFloat(6 * sin(u * 0.045 + t * 0.7 + phase) + 4 * sin(u * 0.11 - t * 1.1 + phase * 2) + 2 * sin(u * 0.23 + t * 1.7)) * scale
    }
}
