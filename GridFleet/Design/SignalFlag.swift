import SwiftUI

/// International Code of Signals flags, drawn flat.
enum SignalFlag: String, CaseIterable {
    /// Blue with a white square.
    case papa
    /// Vertical yellow and blue stripes.
    case golf
    /// Four triangles: yellow, black, red and blue. Admiral Togo's battle flag at Tsushima.
    case zulu

    var letter: String {
        switch self {
        case .papa: "P"
        case .golf: "G"
        case .zulu: "Z"
        }
    }

    var name: String { rawValue.capitalized }

    static let blue = Color(hex: 0x1D4F91)
    static let yellow = Color(hex: 0xF2C230)
    static let red = Color(hex: 0xC62F2F)
    static let white = Color(hex: 0xF5F3EE)
    static let black = Color(hex: 0x1B1B1D)

    /// The flag's strongest color, for tints.
    var color: Color {
        switch self {
        case .papa: Self.blue
        case .golf: Self.yellow
        case .zulu: Self.red
        }
    }

    /// Paints the flag's pattern into `rect`.
    func paint(_ context: GraphicsContext, in rect: CGRect) {
        switch self {
        case .papa:
            context.fill(Path(rect), with: .color(Self.blue))
            let side = rect.width * 0.46
            context.fill(Path(CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)), with: .color(Self.white))
        case .golf:
            let stripe = rect.width / 6
            for i in 0..<6 {
                context.fill(Path(CGRect(x: rect.minX + CGFloat(i) * stripe, y: rect.minY, width: stripe + 0.5, height: rect.height)), with: .color(i.isMultiple(of: 2) ? Self.yellow : Self.blue))
            }
        case .zulu:
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            // Top, fly (right), bottom, hoist (left).
            for (i, color) in [Self.yellow, Self.blue, Self.red, Self.black].enumerated() {
                var triangle = Path()
                triangle.move(to: c)
                triangle.addLine(to: corners[i])
                triangle.addLine(to: corners[(i + 1) % 4])
                triangle.closeSubpath()
                context.fill(triangle, with: .color(color))
                context.stroke(triangle, with: .color(color), lineWidth: 0.5)
            }
        }
    }
}

/// A rival's flag as a tile. It ripples while they speak and fades when they're beaten.
struct RivalFlag: View {
    let rival: Rival
    var mood: RivalMood = .neutral
    var talking = false
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !talking || reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let shape = RoundedRectangle(cornerRadius: size.width * 0.14, style: .continuous).path(in: rect)
                var ctx = context
                ctx.clip(to: shape)
                rival.flag.paint(ctx, in: rect)
                // While the rival talks, a faint ripple runs across the cloth.
                if talking && !reduceMotion {
                    let bandWidth = size.width / 3
                    let offset = CGFloat((t * 1.6).truncatingRemainder(dividingBy: 1)) * bandWidth * 2
                    var x = -bandWidth * 2 + offset
                    while x < size.width {
                        ctx.fill(
                            Path(CGRect(x: x, y: 0, width: bandWidth, height: size.height)),
                            with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.09), .clear]), startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + bandWidth, y: 0))
                        )
                        x += bandWidth * 2
                    }
                }
                context.stroke(shape, with: .color(theme.hairline), lineWidth: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .saturation(mood == .defeated ? 0.35 : 1)
        .opacity(mood == .defeated ? 0.75 : 1)
        .animation(.smooth(duration: 0.4), value: mood == .defeated)
        .accessibilityLabel("\(rival.fullName)'s flag, \(rival.flag.name)")
    }
}
