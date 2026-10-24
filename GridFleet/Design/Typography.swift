import SwiftUI

/// Spacing scale. Everything lines up on these.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Two radii: controls and small tiles, and cards.
enum Radius {
    static let small: CGFloat = 12
    static let card: CGFloat = 20
}

extension Font {
    /// The Grid Fleet wordmark. Used for the name only.
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    /// Board coordinates and countdowns.
    static func coordinate(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

extension Text {
    /// A small section label above a group.
    func sectionLabel() -> some View {
        self.font(.subheadline.weight(.semibold))
    }
}
