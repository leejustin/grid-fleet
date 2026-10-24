import SwiftUI

/// Lays out two views on either side of the fold: top and bottom for a hinge across the screen,
/// left and right for one down it. Without a fold it splits the space in half.
public struct FoldSplit<First: View, Second: View>: View {
    @Environment(\.foldState) private var fold
    private let gutter: CGFloat
    private let first: First
    private let second: Second

    /// - Parameter gutter: Space kept clear around the fold.
    public init(gutter: CGFloat = 16, @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.gutter = gutter
        self.first = first()
        self.second = second()
    }

    public var body: some View {
        GeometryReader { proxy in
            let global = proxy.frame(in: .global)
            let panels = FoldGeometry.panels(container: global, hinge: fold.splitsWindow ? fold.hinge : nil, minimumGutter: gutter)
            ZStack(alignment: .topLeading) {
                first
                    .frame(width: panels.first.width, height: panels.first.height)
                    .offset(x: panels.first.minX - global.minX, y: panels.first.minY - global.minY)
                second
                    .frame(width: panels.second.width, height: panels.second.height)
                    .offset(x: panels.second.minX - global.minX, y: panels.second.minY - global.minY)
            }
            .frame(width: global.width, height: global.height, alignment: .topLeading)
        }
    }
}

/// A picker for the developer posture simulator. Put it in a debug settings screen.
public struct FoldSimulatorPicker: View {
    @Environment(FoldMonitor.self) private var monitor

    public init() {}

    public var body: some View {
        @Bindable var monitor = monitor
        Picker("Fold posture", selection: $monitor.simulatedPosture) {
            Text("Follow device").tag(FoldPosture?.none)
            ForEach(FoldPosture.allCases) { posture in
                Text(posture.displayName).tag(Optional(posture))
            }
        }
    }
}
