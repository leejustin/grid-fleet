import GridFleetCore
import SwiftUI

/// A medal on a ribbon. Bronze, silver or gold by rarity.
struct MedalBadge: View {
    let medal: Medal
    var earned = true
    var size: CGFloat = 56

    private var metal: [Color] {
        switch medal.tier {
        case 0: [Color(hex: 0xF0B27A), Color(hex: 0x9C5B26)]
        case 1: [Color(hex: 0xF4F6F8), Color(hex: 0x8D98A5)]
        default: [Color(hex: 0xFFE38A), Color(hex: 0xC48A12)]
        }
    }

    private var ribbon: [Color] {
        switch medal.tier {
        case 0: [Color(hex: 0x2A6F97), Color(hex: 0xF1FAEE)]
        case 1: [Color(hex: 0x6A4C93), Color(hex: 0xF1FAEE)]
        default: [Color(hex: 0xC1121F), Color(hex: 0xFDF0D5)]
        }
    }

    private var symbol: String {
        switch medal {
        case .firstBlood: "drop.fill"
        case .hatTrick: "3.circle.fill"
        case .broadside: "flame.fill"
        case .sharpshooter: "scope"
        case .untouched: "shield.fill"
        case .comeback: "heart.fill"
        case .swiftVictory: "bolt.fill"
        case .torpedoAce: "arrow.right.to.line.compact"
        case .admiralSlayer: "crown.fill"
        }
    }

    var body: some View {
        VStack(spacing: -size * 0.08) {
            // Ribbon with a V cut.
            Canvas { context, canvas in
                let w = canvas.width, h = canvas.height
                var band = Path()
                band.move(to: CGPoint(x: w * 0.22, y: 0))
                band.addLine(to: CGPoint(x: w * 0.78, y: 0))
                band.addLine(to: CGPoint(x: w * 0.7, y: h))
                band.addLine(to: CGPoint(x: w * 0.5, y: h * 0.82))
                band.addLine(to: CGPoint(x: w * 0.3, y: h))
                band.closeSubpath()
                context.fill(band, with: .color(ribbon[0]))
                context.clip(to: band)
                for x in stride(from: w * 0.4, to: w * 0.62, by: w * 0.09) {
                    context.fill(Path(CGRect(x: x, y: 0, width: w * 0.04, height: h)), with: .color(ribbon[1]))
                }
            }
            .frame(width: size, height: size * 0.5)
            ZStack {
                Circle().fill(LinearGradient(colors: metal, startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(metal[1].mix(with: .black, by: 0.2), lineWidth: size * 0.04)
                Circle().inset(by: size * 0.1).strokeBorder(.white.opacity(0.35), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.32, weight: .black))
                    .foregroundStyle(metal[1].mix(with: .black, by: 0.35))
                    .shadow(color: .white.opacity(0.5), radius: 0, y: 1)
            }
            .frame(width: size * 0.78, height: size * 0.78)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        }
        .saturation(earned ? 1 : 0)
        .opacity(earned ? 1 : 0.3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(medal.title)\(earned ? "" : ", not yet earned"). \(medal.criterion)")
    }
}
