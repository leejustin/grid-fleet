import SwiftUI

/// Room light on a half-folded phone, like the folding board game on a table. The standing lid shades the
/// tray below it, and the crease between them falls into shadow. Both deepen as the phone closes.
struct LidLight: Equatable {
    enum Role { case lid, tray }

    var role: Role
    /// 0 when barely open (about 60°), 1 when flat.
    var openness: Double

    init(role: Role, hingeAngle: Double) {
        self.role = role
        openness = min(1, max(0, (hingeAngle - .pi / 3) / (2 * .pi / 3)))
    }

    func draw(in context: GraphicsContext, rect: CGRect, cornerRadius: CGFloat) {
        let closedness = 1 - openness
        guard closedness > 0.02 else { return }
        var ctx = context
        ctx.clip(to: Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous))
        switch role {
        case .tray:
            // The lid's shadow, cast from the hinge edge across the top of the tray.
            let depth = rect.height * (0.1 + 0.4 * closedness)
            let shade = Gradient(stops: [
                .init(color: .black.opacity(0.08 + 0.55 * closedness), location: 0),
                .init(color: .black.opacity(0.04 + 0.2 * closedness), location: 0.4),
                .init(color: .clear, location: 1),
            ])
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: depth)),
                     with: .linearGradient(shade, startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.minY + depth)))
        case .lid:
            // Light from above catches the top of the lid; the crease at the bottom is shaded.
            let sheen = rect.height * 0.4
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: sheen)),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0.08 * closedness), .clear]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.minY + sheen)))
            let crease = rect.height * (0.06 + 0.16 * closedness)
            ctx.fill(Path(CGRect(x: rect.minX, y: rect.maxY - crease, width: rect.width, height: crease)),
                     with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.05 + 0.35 * closedness)]), startPoint: CGPoint(x: rect.midX, y: rect.maxY - crease), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }
}

extension EnvironmentValues {
    /// Set on each half of a half-folded layout.
    @Entry var lidLight: LidLight? = nil
}
