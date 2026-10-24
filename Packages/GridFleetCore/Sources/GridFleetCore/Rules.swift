import Foundation

public enum FiringMode: String, Codable, Sendable, CaseIterable {
    /// One shot per turn.
    case single
    /// One shot per ship still afloat.
    case salvo
}

public enum BoardPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 10 × 10, five ships. The standard game.
    case classic
    /// 8 × 8, four ships. A quick game.
    case skirmish
    /// 12 × 12, six ships. A long game.
    case openOcean

    public var id: String { rawValue }

    public var boardSize: Int {
        switch self {
        case .classic: 10
        case .skirmish: 8
        case .openOcean: 12
        }
    }

    public var fleet: [ShipKind] {
        switch self {
        case .classic: [.carrier, .cruiser, .destroyer, .submarine, .patrol]
        case .skirmish: [.cruiser, .destroyer, .submarine, .patrol]
        case .openOcean: [.carrier, .cruiser, .frigate, .destroyer, .submarine, .patrol]
        }
    }

    public var displayName: String {
        switch self {
        case .classic: "Classic"
        case .skirmish: "Skirmish"
        case .openOcean: "Open Ocean"
        }
    }

    public var blurb: String {
        switch self {
        case .classic: "10 × 10 · 5 ships"
        case .skirmish: "8 × 8 · 4 ships · quick"
        case .openOcean: "12 × 12 · 6 ships · epic"
        }
    }
}

public struct GameRules: Hashable, Codable, Sendable {
    public var preset: BoardPreset
    public var shipsMayTouch: Bool
    public var firing: FiringMode
    public var specialWeapons: Bool

    public init(preset: BoardPreset = .classic, shipsMayTouch: Bool = true, firing: FiringMode = .single, specialWeapons: Bool = false) {
        self.preset = preset
        self.shipsMayTouch = shipsMayTouch
        self.firing = firing
        self.specialWeapons = specialWeapons
    }

    public static let classic = GameRules()

    public var board: Board { Board(size: preset.boardSize) }
    public var fleet: [ShipKind] { preset.fleet }
    public var totalShipCells: Int { fleet.reduce(0) { $0 + $1.length } }

    /// Special weapons each side starts with.
    public var startingArsenal: Arsenal {
        specialWeapons ? Arsenal(stock: [.torpedo: 1, .barrage: 1, .sonar: 2]) : Arsenal(stock: [:])
    }

    /// A one-line description, e.g. "Classic · Salvo · No touching".
    public var summary: String {
        var parts = [preset.displayName]
        if firing == .salvo { parts.append("Salvo") }
        if specialWeapons { parts.append("Specials") }
        if !shipsMayTouch { parts.append("No touching") }
        return parts.joined(separator: " · ")
    }
}
