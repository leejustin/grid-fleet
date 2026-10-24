import GridFleetCore
import SwiftUI

/// How a ship should look.
enum ShipLook: Equatable {
    /// One of your ships, afloat.
    case own
    /// One of your ships, sunk.
    case ownSunk
    /// An enemy ship you've sunk.
    case enemySunk
    /// An enemy ship revealed at the end of the game.
    case enemyGhost
    /// Being dragged during deployment.
    case floating(valid: Bool)
    /// Selected during deployment.
    case selected
}

/// Draws top-down ship silhouettes.
enum ShipPainter {
    /// Draws `kind` inside `rect`, a run of cells. `damaged` holds the segment indexes (0 = origin end) that have been hit.
    static func draw(
        kind: ShipKind,
        orientation: Orientation,
        in rect: CGRect,
        context: GraphicsContext,
        skin: ShipSkin,
        theme: Theme,
        look: ShipLook,
        damaged: Set<Int> = []
    ) {
        var ctx = context
        let horizontal = orientation == .horizontal
        let long = horizontal ? rect.width : rect.height
        let cell = horizontal ? rect.height : rect.width
        let L = long - cell * 0.14
        let B = cell * beamRatio(kind)
        ctx.translateBy(x: rect.midX, y: rect.midY)
        // Bow points right when horizontal and down when vertical.
        if !horizontal { ctx.rotate(by: .degrees(90)) }

        let hull = hullPath(kind: kind, length: L, beam: B)
        let paper = theme.isPaper

        // Shadow and glow.
        switch look {
        case .own, .selected:
            if !paper {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.45), radius: cell * 0.12, x: 0, y: cell * 0.08))
                    layer.fill(hull, with: .color(skin.hullDark))
                }
            }
        case .floating(let valid):
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: (valid ? theme.accent : theme.danger).opacity(0.9), radius: cell * 0.3))
                layer.fill(hull, with: .color(valid ? theme.accent : theme.danger))
            }
        default:
            break
        }

        // Hull fill.
        let top = CGPoint(x: 0, y: -B / 2)
        let bottom = CGPoint(x: 0, y: B / 2)
        switch look {
        case .own, .floating, .selected:
            if paper {
                ctx.fill(hull, with: .color(theme.ink.opacity(0.07)))
            } else {
                ctx.fill(hull, with: .linearGradient(Gradient(colors: [skin.hullLight, skin.hullDark]), startPoint: top, endPoint: bottom))
                // A highlight along the upper edge.
                ctx.drawLayer { layer in
                    layer.clip(to: hull)
                    layer.fill(Path(CGRect(x: -L / 2, y: -B / 2, width: L, height: B * 0.22)), with: .color(.white.opacity(0.18)))
                }
            }
        case .ownSunk, .enemySunk:
            if paper {
                ctx.fill(hull, with: .color(theme.ink.opacity(0.12)))
            } else {
                ctx.fill(hull, with: .linearGradient(Gradient(colors: [Color(hex: 0x3A3632), Color(hex: 0x141210)]), startPoint: top, endPoint: bottom))
            }
        case .enemyGhost:
            ctx.fill(hull, with: .color(theme.ink.opacity(0.08)))
        }

        // Scorch marks on hit sections.
        if !damaged.isEmpty, look != .enemyGhost {
            ctx.drawLayer { layer in
                layer.clip(to: hull)
                for index in damaged {
                    let x = -long / 2 + cell * (CGFloat(index) + 0.5)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: x - cell * 0.55, y: -cell * 0.55, width: cell * 1.1, height: cell * 1.1)),
                        with: .radialGradient(Gradient(colors: [.black.opacity(paper ? 0.25 : 0.7), .clear]), center: CGPoint(x: x, y: 0), startRadius: 0, endRadius: cell * 0.55)
                    )
                }
            }
        }

        // Deck details.
        let deckColor: Color = switch look {
        case .ownSunk, .enemySunk: Color(hex: 0x0A0908).opacity(0.8)
        case .enemyGhost: theme.ink.opacity(0.25)
        default: paper ? theme.ink.opacity(0.75) : skin.deck
        }
        drawDeck(kind: kind, length: L, beam: B, cell: cell, context: ctx, color: deckColor, accent: paper ? theme.ink.opacity(0.5) : skin.hullLight.opacity(0.9), paper: paper)

        // Outline.
        switch look {
        case .own, .floating:
            if skin.glowsWithAccent && !paper {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: theme.accent.opacity(0.8), radius: cell * 0.1))
                    layer.stroke(hull, with: .color(theme.accent.opacity(0.9)), lineWidth: 1.2)
                }
            } else {
                ctx.stroke(hull, with: .color(paper ? theme.ink.opacity(0.85) : skin.edge.opacity(0.9)), lineWidth: paper ? 1.6 : 1)
            }
        case .selected:
            ctx.stroke(hull, with: .color(theme.accent), lineWidth: 2.5)
        case .ownSunk, .enemySunk:
            ctx.stroke(hull, with: .color(theme.sunk.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, dash: [cell * 0.14, cell * 0.08]))
            if paper {
                // Hatch it out, the way you'd cross off a ship on a pad.
                var hatch = Path()
                var x = -L / 2
                while x < L / 2 {
                    hatch.move(to: CGPoint(x: x, y: B / 2))
                    hatch.addLine(to: CGPoint(x: x + B, y: -B / 2))
                    x += cell * 0.22
                }
                ctx.drawLayer { layer in
                    layer.clip(to: hull)
                    layer.stroke(hatch, with: .color(theme.sunk.opacity(0.6)), lineWidth: 1)
                }
            }
        case .enemyGhost:
            ctx.stroke(hull, with: .color(theme.ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        }
    }

    static func beamRatio(_ kind: ShipKind) -> CGFloat {
        switch kind.id {
        case "carrier": 0.70
        case "submarine": 0.48
        case "patrol": 0.50
        default: 0.56
        }
    }

    /// The hull outline, centered on the origin with the bow pointing to +x.
    static func hullPath(kind: ShipKind, length L: CGFloat, beam B: CGFloat) -> Path {
        var p = Path()
        let half = L / 2
        let b = B / 2
        switch kind.id {
        case "carrier":
            let stern = -half
            p.move(to: CGPoint(x: stern + b * 0.4, y: -b))
            p.addLine(to: CGPoint(x: half - B * 0.7, y: -b))
            p.addLine(to: CGPoint(x: half, y: -b * 0.35))
            p.addLine(to: CGPoint(x: half - B * 0.15, y: b * 0.55))
            p.addLine(to: CGPoint(x: half - B * 0.5, y: b))
            p.addLine(to: CGPoint(x: stern + b * 0.4, y: b))
            p.addQuadCurve(to: CGPoint(x: stern + b * 0.4, y: -b), control: CGPoint(x: stern - b * 0.2, y: 0))
        case "submarine":
            p.addRoundedRect(in: CGRect(x: -half, y: -b, width: L, height: B), cornerSize: CGSize(width: b, height: b), style: .continuous)
            // A blunt, slightly fuller bow.
            p.addEllipse(in: CGRect(x: half - B * 1.1, y: -b, width: B * 1.1, height: B))
        default:
            let bowStart = half - B * (kind.id == "patrol" ? 0.9 : 1.25)
            let sternRadius = b * 0.55
            p.move(to: CGPoint(x: -half + sternRadius, y: -b))
            p.addLine(to: CGPoint(x: bowStart, y: -b))
            p.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: half - B * 0.3, y: -b))
            p.addQuadCurve(to: CGPoint(x: bowStart, y: b), control: CGPoint(x: half - B * 0.3, y: b))
            p.addLine(to: CGPoint(x: -half + sternRadius, y: b))
            p.addQuadCurve(to: CGPoint(x: -half + sternRadius, y: -b), control: CGPoint(x: -half - sternRadius * 0.4, y: 0))
        }
        p.closeSubpath()
        return p
    }

    private static func drawDeck(kind: ShipKind, length L: CGFloat, beam B: CGFloat, cell: CGFloat, context ctx: GraphicsContext, color: Color, accent: Color, paper: Bool) {
        let half = L / 2
        let b = B / 2

        func turret(at x: CGFloat, facing direction: CGFloat) {
            let r = B * 0.22
            var barrel = Path()
            barrel.addRoundedRect(
                in: CGRect(x: direction > 0 ? x : x - B * 0.55, y: -B * 0.05, width: B * 0.55, height: B * 0.1),
                cornerSize: CGSize(width: B * 0.05, height: B * 0.05)
            )
            if paper {
                ctx.stroke(barrel, with: .color(color), lineWidth: 1)
                ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: -r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 1.2)
            } else {
                ctx.fill(barrel, with: .color(color))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: -r, width: r * 2, height: r * 2)), with: .color(color))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: -r * 0.45, width: r * 0.9, height: r * 0.9)), with: .color(accent.opacity(0.35)))
            }
        }

        func block(_ rect: CGRect, radius: CGFloat, window: Bool = true) {
            let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            if paper {
                ctx.stroke(path, with: .color(color), lineWidth: 1.2)
            } else {
                ctx.fill(path, with: .color(color))
                if window {
                    ctx.fill(Path(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.28), cornerRadius: radius * 0.5), with: .color(accent.opacity(0.85)))
                }
            }
        }

        switch kind.id {
        case "carrier":
            // Runway and an angled landing line.
            var runway = Path()
            runway.move(to: CGPoint(x: -half + B * 0.35, y: -b * 0.1))
            runway.addLine(to: CGPoint(x: half - B * 0.8, y: -b * 0.1))
            ctx.stroke(runway, with: .color(accent.opacity(paper ? 0.7 : 0.6)), style: StrokeStyle(lineWidth: max(1, B * 0.05), dash: [cell * 0.16, cell * 0.12]))
            var angled = Path()
            angled.move(to: CGPoint(x: -half + B * 0.4, y: b * 0.55))
            angled.addLine(to: CGPoint(x: -half + L * 0.42, y: -b * 0.65))
            ctx.stroke(angled, with: .color(accent.opacity(0.3)), lineWidth: max(1, B * 0.04))
            block(CGRect(x: L * 0.05, y: b * 0.25, width: L * 0.13, height: b * 0.62), radius: B * 0.08)
        case "cruiser":
            turret(at: half - L * 0.24, facing: 1)
            turret(at: -half + L * 0.2, facing: -1)
            block(CGRect(x: -L * 0.12, y: -b * 0.48, width: L * 0.24, height: B * 0.48), radius: B * 0.1)
        case "frigate":
            turret(at: half - L * 0.22, facing: 1)
            block(CGRect(x: -L * 0.1, y: -b * 0.45, width: L * 0.2, height: B * 0.45), radius: B * 0.1)
            let dome = Path(ellipseIn: CGRect(x: -half + L * 0.16 - B * 0.2, y: -B * 0.2, width: B * 0.4, height: B * 0.4))
            if paper { ctx.stroke(dome, with: .color(color), lineWidth: 1.2) } else {
                ctx.fill(dome, with: .color(accent.opacity(0.8)))
                ctx.stroke(dome, with: .color(color), lineWidth: 1)
            }
        case "destroyer":
            turret(at: half - L * 0.28, facing: 1)
            block(CGRect(x: -L * 0.16, y: -b * 0.45, width: L * 0.26, height: B * 0.45), radius: B * 0.1)
            let funnel = Path(roundedRect: CGRect(x: -half + L * 0.14, y: -B * 0.14, width: L * 0.1, height: B * 0.28), cornerRadius: B * 0.1)
            if paper { ctx.stroke(funnel, with: .color(color), lineWidth: 1.2) } else { ctx.fill(funnel, with: .color(color)) }
        case "submarine":
            var spine = Path()
            spine.move(to: CGPoint(x: -half + b, y: 0))
            spine.addLine(to: CGPoint(x: half - b, y: 0))
            ctx.stroke(spine, with: .color(accent.opacity(0.25)), lineWidth: max(1, B * 0.06))
            block(CGRect(x: L * 0.02, y: -b * 0.38, width: L * 0.2, height: B * 0.38), radius: B * 0.18, window: false)
            var fins = Path()
            fins.move(to: CGPoint(x: -half + b * 0.6, y: -b * 1.15))
            fins.addLine(to: CGPoint(x: -half + b * 0.6, y: b * 1.15))
            ctx.stroke(fins, with: .color(color), lineWidth: max(1.2, B * 0.1))
        case "patrol":
            turret(at: half - L * 0.24, facing: 1)
            block(CGRect(x: -L * 0.28, y: -b * 0.5, width: L * 0.32, height: B * 0.5), radius: B * 0.12)
        default:
            block(CGRect(x: -L * 0.15, y: -b * 0.45, width: L * 0.3, height: B * 0.45), radius: B * 0.1)
        }
    }
}

/// A single ship drawn on its own, for fleet status bars and docks.
struct ShipGlyph: View {
    let kind: ShipKind
    var look: ShipLook = .own
    var orientation: Orientation = .horizontal
    var damaged: Set<Int> = []
    @Environment(\.theme) private var theme
    @Environment(\.shipSkin) private var skin
    @Environment(\.boardStyle) private var style

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            if style == .pegboard {
                PegboardPainter.drawPiece(kind: kind, orientation: orientation, in: rect, context: context, sunk: look == .ownSunk || look == .enemySunk, ghost: look == .enemyGhost)
            } else {
                ShipPainter.draw(kind: kind, orientation: orientation, in: rect, context: context, skin: skin, theme: theme, look: look, damaged: damaged)
            }
        }
        .aspectRatio(orientation == .horizontal ? CGFloat(kind.length) : 1 / CGFloat(kind.length), contentMode: .fit)
    }
}
