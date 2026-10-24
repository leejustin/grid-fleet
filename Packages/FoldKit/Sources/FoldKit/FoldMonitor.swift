import Observation
import SwiftUI

/// Tracks the fold posture and publishes it to SwiftUI.
///
/// On iOS 27.1 and later the posture comes from the system hinge (`onHingeChange`). The hinge's position
/// isn't reported, so it's placed across the middle of the window's long side, which is where the inner
/// screen folds. The developer simulator (`simulatedPosture`) overrides the system on any device.
@MainActor
@Observable
public final class FoldMonitor {
    public static let simulationKey = "FoldKit.simulatedPosture"
    /// Degrees, for trying the lighting at a particular angle while simulating a half fold.
    public static let simulatedAngleKey = "FoldKit.simulatedAngle"

    /// The posture the app should lay out for.
    public private(set) var state: FoldState = .unfoldable

    /// The hinge angle in radians, when the device reports one.
    public private(set) var hingeAngle: Double?

    /// The hinge angle to draw with, in radians: the system's, or a typical one for a simulated posture.
    /// Rounded to two degrees so opening the phone doesn't redraw on every tiny change.
    public var effectiveHingeAngle: Double? {
        let raw: Double?
        if let simulatedPosture {
            let degrees = defaults.string(forKey: Self.simulatedAngleKey).flatMap(Double.init)
            switch simulatedPosture {
            case .halfFolded: raw = (degrees ?? 110) * .pi / 180
            case .flat: raw = .pi
            case .closed: raw = 0
            case .unfoldable: raw = nil
            }
        } else {
            raw = hingeAngle
        }
        guard let raw else { return nil }
        let step = 2 * Double.pi / 180
        return (raw / step).rounded() * step
    }

    /// Overrides the system posture. Nil follows the system.
    public var simulatedPosture: FoldPosture? {
        didSet {
            defaults.set(simulatedPosture?.rawValue, forKey: Self.simulationKey)
            recompute()
        }
    }

    private var systemPosture: FoldPosture = .unfoldable
    private var windowFrame: CGRect = .zero
    /// The screen's bounds in window coordinates. Nil until a window is known; the window stands in.
    private var screenFrame: CGRect?
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.simulatedPosture = defaults.string(forKey: Self.simulationKey).flatMap(FoldPosture.init(rawValue:))
        recompute()
    }

    /// Called by `.foldAware()` whenever the window resizes or moves on the screen.
    func update(windowFrame: CGRect, screenFrame: CGRect? = nil) {
        guard windowFrame != self.windowFrame || screenFrame != self.screenFrame else { return }
        self.windowFrame = windowFrame
        self.screenFrame = screenFrame
        recompute()
    }

    /// Called by `.foldAware()` when the system reports a hinge change. Nil means no hinge.
    func update(systemPosture: FoldPosture, angle: Double?) {
        hingeAngle = angle
        guard systemPosture != self.systemPosture else { return }
        self.systemPosture = systemPosture
        recompute()
    }

    private func recompute() {
        let posture = simulatedPosture ?? systemPosture
        let hinge = posture.spansFold ? FoldGeometry.hinge(screen: screenFrame ?? windowFrame, window: windowFrame) : nil
        let next = FoldState(posture: posture, hinge: hinge, isSimulated: simulatedPosture != nil)
        if next != state { state = next }
    }
}

extension EnvironmentValues {
    /// The current fold posture. Set by `.foldAware()`.
    @Entry public var foldState: FoldState = .unfoldable
    /// The hinge angle in radians (0 closed, π flat), when known. Kept apart from `foldState` so views
    /// that only lay out by posture don't update while the phone is being opened.
    @Entry public var hingeAngle: Double? = nil
}

private struct FoldAwareModifier: ViewModifier {
    @State private var monitor = FoldMonitor()
    @State private var screenFrame: CGRect?
    let showsSimulatedCrease: Bool

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            content
                .environment(\.foldState, monitor.state)
                .environment(\.hingeAngle, monitor.effectiveHingeAngle)
                .environment(monitor)
                .overlay {
                    if showsSimulatedCrease, monitor.state.isSimulated, let hinge = monitor.state.hinge {
                        SimulatedCrease(hinge: hinge, origin: frame.origin)
                    }
                }
                .onChange(of: frame, initial: true) { _, newFrame in
                    monitor.update(windowFrame: newFrame, screenFrame: screenFrame)
                }
                #if os(iOS)
                .background {
                    // Finds the window, so the hinge can be placed from the screen rather than the window.
                    WindowProbe { window in
                        screenFrame = window.flatMap { window in
                            guard let screen = window.windowScene?.screen else { return nil }
                            return window.convert(screen.bounds, from: screen.coordinateSpace)
                        }
                        monitor.update(windowFrame: frame, screenFrame: screenFrame)
                    }
                }
                #endif
                .modifier(SystemHingeReader(monitor: monitor))
        }
        .ignoresSafeArea()
    }
}

#if os(iOS)
/// Reports the window a view is in, and again whenever the window's geometry changes.
private struct WindowProbe: UIViewRepresentable {
    let onChange: (UIWindow?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onChange?(window)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onChange?(window)
        }
    }
}
#endif

/// Feeds the system hinge into the monitor on iOS 27.1 and later.
private struct SystemHingeReader: ViewModifier {
    let monitor: FoldMonitor

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                monitor.update(systemPosture: FoldPosture(context.hinge), angle: context.hinge.map { $0.angle.radians })
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
@available(iOS 27.1, *)
extension FoldPosture {
    /// Maps the system hinge. No hinge means a device that doesn't fold.
    init(_ hinge: DeviceHinge?) {
        guard let hinge else {
            self = .unfoldable
            return
        }
        switch hinge.status {
        case .closed: self = .closed
        case .partiallyOpen: self = .halfFolded
        case .fullyOpen: self = .flat
        default: self = .unfoldable
        }
    }
}
#endif

/// A faint line where the fold would be, so simulated layouts read like the real thing.
private struct SimulatedCrease: View {
    let hinge: CGRect
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            let rect = hinge.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -0.5)
            context.fill(Path(rect), with: .color(.white.opacity(0.12)))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

extension View {
    /// Publishes the fold posture to this view hierarchy. Apply once, at the root.
    public func foldAware(showsSimulatedCrease: Bool = true) -> some View {
        modifier(FoldAwareModifier(showsSimulatedCrease: showsSimulatedCrease))
    }
}
