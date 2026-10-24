import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// An ocean theme: every color the boards and screens use.
struct Theme: Identifiable, Equatable {
    enum ID: String, CaseIterable, Codable {
        case nightWatch, daybreak, abyss, lagoon, graphPaper, arctic
    }

    let id: ID
    let name: String
    let tagline: String
    let scheme: ColorScheme

    // Screen
    let backdropTop: Color
    let backdropBottom: Color
    let ink: Color
    let inkSecondary: Color
    let accent: Color
    let panel: Color

    // Board
    let waterDeep: Color
    let waterShallow: Color
    let caustic: Color
    let gridLine: Color
    let label: Color
    let hit: Color
    let hitCore: Color
    let miss: Color
    let sunk: Color
    let danger: Color

    /// Draw marks like pencil on paper rather than glowing.
    let isPaper: Bool
    /// A radar sweep turns over the enemy grid while it's your turn.
    let hasSweep: Bool

    static let nightWatch = Theme(
        id: .nightWatch, name: "Night Watch", tagline: "Phosphor on midnight water", scheme: .dark,
        backdropTop: Color(hex: 0x0B1A30), backdropBottom: Color(hex: 0x03070F),
        ink: Color(hex: 0xEAF6FF), inkSecondary: Color(hex: 0x8FA9C2), accent: Color(hex: 0x5EE6D0), panel: Color(hex: 0x0E2138),
        waterDeep: Color(hex: 0x081B33), waterShallow: Color(hex: 0x0F3557), caustic: Color(hex: 0x5EE6D0),
        gridLine: Color(hex: 0x5EE6D0, opacity: 0.22), label: Color(hex: 0x7FBFC9),
        hit: Color(hex: 0xFF6B3D), hitCore: Color(hex: 0xFFE7C2), miss: Color(hex: 0xCFE8FF), sunk: Color(hex: 0xFF3B5C), danger: Color(hex: 0xFF4D6A),
        isPaper: false, hasSweep: true
    )

    static let daybreak = Theme(
        id: .daybreak, name: "Daybreak", tagline: "Bright harbor morning", scheme: .light,
        backdropTop: Color(hex: 0xF6F1E7), backdropBottom: Color(hex: 0xDCE8EE),
        ink: Color(hex: 0x10263A), inkSecondary: Color(hex: 0x5B7286), accent: Color(hex: 0xE2563B), panel: Color(hex: 0xFFFFFF),
        waterDeep: Color(hex: 0x9CC7DA), waterShallow: Color(hex: 0xCBE6F0), caustic: Color(hex: 0xFFFFFF),
        gridLine: Color(hex: 0x2A5B78, opacity: 0.28), label: Color(hex: 0x4D6F86),
        hit: Color(hex: 0xE2563B), hitCore: Color(hex: 0xFFF3E0), miss: Color(hex: 0xFFFFFF), sunk: Color(hex: 0xB3243A), danger: Color(hex: 0xC8323F),
        isPaper: false, hasSweep: false
    )

    static let abyss = Theme(
        id: .abyss, name: "Abyss", tagline: "Bioluminescent deep", scheme: .dark,
        backdropTop: Color(hex: 0x160B2E), backdropBottom: Color(hex: 0x05020C),
        ink: Color(hex: 0xF1E9FF), inkSecondary: Color(hex: 0xA294C4), accent: Color(hex: 0xB78CFF), panel: Color(hex: 0x1C1036),
        waterDeep: Color(hex: 0x0E0722), waterShallow: Color(hex: 0x24124A), caustic: Color(hex: 0x6CF2FF),
        gridLine: Color(hex: 0xB78CFF, opacity: 0.22), label: Color(hex: 0xA48DE0),
        hit: Color(hex: 0xFF4FD8), hitCore: Color(hex: 0xFFE6FA), miss: Color(hex: 0x6CF2FF), sunk: Color(hex: 0xFF3D8B), danger: Color(hex: 0xFF4F8A),
        isPaper: false, hasSweep: true
    )

    static let lagoon = Theme(
        id: .lagoon, name: "Lagoon", tagline: "Turquoise shallows", scheme: .light,
        backdropTop: Color(hex: 0xFFF4DC), backdropBottom: Color(hex: 0xA8E6DF),
        ink: Color(hex: 0x0B3B3C), inkSecondary: Color(hex: 0x3E7C79), accent: Color(hex: 0xFF7A59), panel: Color(hex: 0xFFFDF6),
        waterDeep: Color(hex: 0x1FB5B0), waterShallow: Color(hex: 0x7FE3D4), caustic: Color(hex: 0xFFFFFF),
        gridLine: Color(hex: 0x05555A, opacity: 0.25), label: Color(hex: 0x146C6C),
        hit: Color(hex: 0xFF5A36), hitCore: Color(hex: 0xFFF2C9), miss: Color(hex: 0xFFFFFF), sunk: Color(hex: 0xC2185B), danger: Color(hex: 0xD84343),
        isPaper: false, hasSweep: false
    )

    static let graphPaper = Theme(
        id: .graphPaper, name: "Graph Paper", tagline: "Pencil, pad and a steady hand", scheme: .light,
        backdropTop: Color(hex: 0xF4EEDC), backdropBottom: Color(hex: 0xE9E1C8),
        ink: Color(hex: 0x2B2A28), inkSecondary: Color(hex: 0x6D685C), accent: Color(hex: 0xD2382F), panel: Color(hex: 0xFBF8EE),
        waterDeep: Color(hex: 0xFBF8EE), waterShallow: Color(hex: 0xFBF8EE), caustic: Color(hex: 0xFBF8EE),
        gridLine: Color(hex: 0x4A7FB5, opacity: 0.45), label: Color(hex: 0x4A7FB5),
        hit: Color(hex: 0xD2382F), hitCore: Color(hex: 0xD2382F), miss: Color(hex: 0x37506E), sunk: Color(hex: 0x8E1E18), danger: Color(hex: 0xD2382F),
        isPaper: true, hasSweep: false
    )

    static let arctic = Theme(
        id: .arctic, name: "Arctic", tagline: "Ice floes and steel sky", scheme: .dark,
        backdropTop: Color(hex: 0x24313E), backdropBottom: Color(hex: 0x0E151C),
        ink: Color(hex: 0xF4FAFF), inkSecondary: Color(hex: 0xA9BBCB), accent: Color(hex: 0x9BD8FF), panel: Color(hex: 0x2A3846),
        waterDeep: Color(hex: 0x1B2A38), waterShallow: Color(hex: 0x3A5368), caustic: Color(hex: 0xE6F6FF),
        gridLine: Color(hex: 0xDDF1FF, opacity: 0.2), label: Color(hex: 0xB5CCDD),
        hit: Color(hex: 0xFF8A3D), hitCore: Color(hex: 0xFFF0D9), miss: Color(hex: 0xFFFFFF), sunk: Color(hex: 0xFF5964), danger: Color(hex: 0xFF5964),
        isPaper: false, hasSweep: true
    )

    static let all: [Theme] = [.nightWatch, .daybreak, .abyss, .lagoon, .graphPaper, .arctic]

    static func with(id: ID) -> Theme { all.first { $0.id == id } ?? .nightWatch }

    var backdrop: LinearGradient {
        LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// How ships are painted.
struct ShipSkin: Identifiable, Equatable {
    enum ID: String, CaseIterable, Codable {
        case steel, brass, stealth, coral
    }

    let id: ID
    let name: String
    let hullLight: Color
    let hullDark: Color
    let deck: Color
    let edge: Color
    /// Stealth hulls glow at the edges in the theme's accent color.
    let glowsWithAccent: Bool

    static let steel = ShipSkin(id: .steel, name: "Steel", hullLight: Color(hex: 0xC5D3E0), hullDark: Color(hex: 0x56687C), deck: Color(hex: 0x2B3A4C), edge: Color(hex: 0x15202D), glowsWithAccent: false)
    static let brass = ShipSkin(id: .brass, name: "Brass", hullLight: Color(hex: 0xF3D58A), hullDark: Color(hex: 0x9C6B1E), deck: Color(hex: 0x5A3A0A), edge: Color(hex: 0x3C2606), glowsWithAccent: false)
    static let stealth = ShipSkin(id: .stealth, name: "Stealth", hullLight: Color(hex: 0x3A4048), hullDark: Color(hex: 0x111418), deck: Color(hex: 0x050607), edge: Color(hex: 0x000000), glowsWithAccent: true)
    static let coral = ShipSkin(id: .coral, name: "Coral", hullLight: Color(hex: 0xFF9EC4), hullDark: Color(hex: 0x7A5CFF), deck: Color(hex: 0x3B1E78), edge: Color(hex: 0x2A0F5C), glowsWithAccent: false)

    static let all: [ShipSkin] = [.steel, .brass, .stealth, .coral]
    static func with(id: ID) -> ShipSkin { all.first { $0.id == id } ?? .steel }
}

/// How hits explode.
enum BlastStyle: String, CaseIterable, Codable, Identifiable {
    case fireball, ink, fireworks, pixel

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fireball: "Fireball"
        case .ink: "Ink Cloud"
        case .fireworks: "Fireworks"
        case .pixel: "8-Bit"
        }
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .nightWatch
    @Entry var shipSkin: ShipSkin = .steel
    @Entry var blastStyle: BlastStyle = .fireball
}
