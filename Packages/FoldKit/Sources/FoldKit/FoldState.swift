import CoreGraphics
import Foundation

/// How a device is folded right now.
public enum FoldPosture: String, Sendable, CaseIterable, Codable, Identifiable {
    /// A device with no fold: a regular iPhone or an iPad.
    case unfoldable
    /// A foldable device that's closed, running on its outer screen.
    case closed
    /// A foldable device bent part-way open, like a laptop.
    case halfFolded
    /// A foldable device opened flat.
    case flat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unfoldable: "No fold"
        case .closed: "Closed"
        case .halfFolded: "Half-folded"
        case .flat: "Open flat"
        }
    }

    /// Whether the app is drawing on the inner screen, across the fold.
    public var spansFold: Bool { self == .halfFolded || self == .flat }
}

/// The posture plus where the fold runs.
public struct FoldState: Equatable, Sendable {
    public var posture: FoldPosture
    /// The fold in global (window) coordinates. Nil when nothing spans a fold.
    public var hinge: CGRect?
    /// True when the posture comes from the developer simulator rather than the system.
    public var isSimulated: Bool

    public init(posture: FoldPosture, hinge: CGRect? = nil, isSimulated: Bool = false) {
        self.posture = posture
        self.hinge = hinge
        self.isSimulated = isSimulated
    }

    public static let unfoldable = FoldState(posture: .unfoldable)

    /// Whether the fold runs through this window, so content should split around it. False when the
    /// device is folded but the app's window sits on one side of the hinge (split view, a resized window).
    public var splitsWindow: Bool { posture.spansFold && hinge != nil }

    /// A hinge across the screen (top and bottom halves), as opposed to down it (left and right).
    public var hingeIsHorizontal: Bool {
        guard let hinge else { return true }
        return hinge.width >= hinge.height
    }
}

public enum FoldGeometry {
    /// Splits `container` (in global coordinates) into the two panels on either side of `hinge`.
    ///
    /// The hinge band itself is excluded, widened to at least `minimumGutter` so content never sits on the crease.
    /// With no hinge, or one that doesn't cross the container, the container is split in half.
    public static func panels(container: CGRect, hinge: CGRect?, minimumGutter: CGFloat = 0) -> (first: CGRect, second: CGRect) {
        let horizontal = hinge.map { $0.width >= $0.height } ?? true
        if horizontal {
            let center = hinge.map(\.midY) ?? container.midY
            let half = max((hinge?.height ?? 0), minimumGutter) / 2
            let topEnd = min(max(center - half, container.minY), container.maxY)
            let bottomY = min(max(center + half, container.minY), container.maxY)
            let top = CGRect(x: container.minX, y: container.minY, width: container.width, height: topEnd - container.minY)
            let bottom = CGRect(x: container.minX, y: bottomY, width: container.width, height: max(0, container.maxY - bottomY))
            return (top, bottom)
        } else {
            let center = hinge.map(\.midX) ?? container.midX
            let half = max((hinge?.width ?? 0), minimumGutter) / 2
            let leftEnd = min(max(center - half, container.minX), container.maxX)
            let rightX = min(max(center + half, container.minX), container.maxX)
            let left = CGRect(x: container.minX, y: container.minY, width: leftEnd - container.minX, height: container.height)
            let right = CGRect(x: rightX, y: container.minY, width: max(0, container.maxX - rightX), height: container.height)
            return (left, right)
        }
    }

    /// The fold, as a hairline across the middle of the screen's long side.
    ///
    /// iPhone Duo's inner screen is portrait-shaped and folds across its long side. Held like a laptop, the
    /// hinge runs across (top and bottom halves, each landscape-shaped); held like a book, it runs down
    /// (left and right halves). Pass the screen's bounds in the same coordinates as the window.
    public static func centerHinge(in screen: CGRect) -> CGRect {
        if screen.height >= screen.width {
            return CGRect(x: screen.minX, y: screen.midY - 0.5, width: screen.width, height: 1)
        }
        return CGRect(x: screen.midX - 0.5, y: screen.minY, width: 1, height: screen.height)
    }

    /// The hinge, if it actually crosses the window. A window on one side of the fold isn't split.
    public static func hinge(screen: CGRect, window: CGRect) -> CGRect? {
        let hinge = centerHinge(in: screen)
        let crosses = hinge.width >= hinge.height
            ? hinge.midY > window.minY + 1 && hinge.midY < window.maxY - 1
            : hinge.midX > window.minX + 1 && hinge.midX < window.maxX - 1
        guard crosses else { return nil }
        // Clip the hairline to the window.
        return hinge.intersection(window)
    }
}
