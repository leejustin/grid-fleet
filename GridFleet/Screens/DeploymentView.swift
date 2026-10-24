import FoldKit
import GridFleetCore
import SwiftUI

/// Place your fleet: drag ships onto the grid, tap to select, tap again to rotate.
struct DeploymentView: View {
    let rules: GameRules
    var subtitle = "Drag to move. Tap a ship twice to rotate it."
    var title = "Deploy your fleet"
    var onReady: (Fleet) -> Void
    var onCancel: () -> Void

    @State private var model: DeploymentModel
    @State private var boardFrame: CGRect = .zero
    @Environment(\.foldState) private var fold
    @Environment(\.theme) private var theme
    @Environment(\.shipSkin) private var skin
    @Environment(\.boardStyle) private var boardStyle

    private let space = "deploy"

    init(rules: GameRules, subtitle: String = "Drag to move. Tap a ship twice to rotate it.", title: String = "Deploy your fleet", onReady: @escaping (Fleet) -> Void, onCancel: @escaping () -> Void) {
        self.rules = rules
        self.subtitle = subtitle
        self.title = title
        self.onReady = onReady
        self.onCancel = onCancel
        _model = State(initialValue: DeploymentModel(rules: rules))
    }

    private var lift: CGFloat {
        let cell = BoardMetrics(n: rules.board.size, size: boardFrame.size).cell
        return cell * 0.9
    }

    var body: some View {
        ZStack {
            OceanBackdrop(animated: false)
            if fold.splitsWindow {
                FoldSplit(gutter: Space.l) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        header
                        Spacer(minLength: 0)
                        dock
                        controls
                    }
                    .padding(Space.l)
                } second: {
                    board.padding(Space.m)
                }
            } else {
                GeometryReader { proxy in
                    if proxy.size.width > proxy.size.height * 1.15 {
                        HStack(spacing: Space.xl) {
                            board
                            VStack(alignment: .leading, spacing: Space.m) {
                                header
                                Spacer(minLength: 0)
                                dock
                                controls
                            }
                            .frame(maxWidth: 380)
                        }
                        .padding(Space.l)
                    } else {
                        VStack(alignment: .leading, spacing: Space.m) {
                            header
                            board
                            dock
                            controls
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Space.m)
                        .padding(.top, Space.xs)
                    }
                }
            }
            dragLayer
        }
        .coordinateSpace(.named(space))
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.subheadline).foregroundStyle(theme.inkSecondary)
            }
            Spacer()
            CircleIconButton(systemImage: "xmark", label: "Leave", size: 36, action: onCancel)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.xxs)
    }

    private var scene: BoardScene {
        var scene = BoardScene(size: rules.board.size)
        scene.ships = model.fleet.ships.map { ship in
            BoardScene.ShipDrawing(ship: ship, look: model.selectedID == ship.id && model.drag == nil ? .selected : .own)
        }
        if let candidate = model.candidate(boardFrame: boardFrame, lift: lift) {
            scene.preview = (candidate.cells, model.fleet.canPlace(candidate, rules: rules))
        }
        return scene
    }

    private var board: some View {
        BoardView(scene: scene, describeCell: { scene.describe($0) })
            .accessibilityIdentifier("deploy-board")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { boardFrame = $0 }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                    .onChanged { value in
                        if model.drag == nil {
                            let metrics = BoardMetrics(n: rules.board.size, size: boardFrame.size)
                            let start = CGPoint(x: value.startLocation.x - boardFrame.minX, y: value.startLocation.y - boardFrame.minY)
                            if let cell = metrics.coordinate(at: start) {
                                model.beginDrag(fromBoardAt: cell, location: value.location)
                            }
                        }
                        model.drag?.location = value.location
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            model.endDrag(boardFrame: boardFrame, lift: lift)
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    let metrics = BoardMetrics(n: rules.board.size, size: boardFrame.size)
                    if let cell = metrics.coordinate(at: value.location) { model.tap(cell) }
                }
            )
            .accessibilityHint("Drag ships to move them. Tap a ship twice to rotate it.")
    }

    private var dock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.unplaced.isEmpty ? "All ships deployed" : "Drag a ship onto the grid, or tap it to drop it in")
                    .font(.footnote)
                    .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: Space.xs)
                if let selected = model.selectedID, model.fleet.ship(id: selected) != nil {
                    Button {
                        model.rotate(selected)
                    } label: {
                        Label("Rotate", systemImage: "arrow.trianglehead.clockwise")
                    }
                    .buttonStyle(.fleet(.secondary, compact: true))
                }
            }
            if !model.unplaced.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.l) {
                        ForEach(model.unplaced) { kind in
                            dockShip(kind)
                        }
                    }
                    .padding(.vertical, Space.xxs)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .animation(.smooth(duration: 0.3), value: model.unplaced.map(\.id))
    }

    private func dockShip(_ kind: ShipKind) -> some View {
        VStack(spacing: Space.xxs) {
            ShipGlyph(kind: kind)
                .frame(height: 22)
            Text(kind.name).font(.caption).foregroundStyle(theme.inkSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.autoPlace(kind) }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(space))
                .onChanged { value in
                    if model.drag == nil { model.beginDrag(fromDock: kind, location: value.location) }
                    model.drag?.location = value.location
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.endDrag(boardFrame: boardFrame, lift: lift)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.name), \(kind.length) cells")
        .accessibilityHint("Places the ship on the grid")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.autoPlace(kind) }
        .accessibilityIdentifier("dock-\(kind.id)")
    }

    private var controls: some View {
        HStack(spacing: Space.xs) {
            Button {
                withAnimation(.smooth(duration: 0.35)) { model.randomize() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.fleet(.secondary, compact: true))
            .accessibilityIdentifier("shuffle")
            Button("Clear") {
                withAnimation(.smooth) { model.clear() }
            }
            .buttonStyle(.fleet(.secondary, compact: true))
            .disabled(model.fleet.ships.isEmpty)
            .accessibilityIdentifier("clear")
            Spacer(minLength: Space.xs)
            Button("Ready") {
                Haptics.fire()
                Analytics.shared.capture("deploy_finished", rules.analyticsProperties.merging(model.usageProperties))
                onReady(model.fleet)
            }
            .buttonStyle(.fleet(.primary, compact: true))
            .frame(minWidth: 110)
            .disabled(!model.isComplete)
            .accessibilityIdentifier("ready")
        }
    }

    @ViewBuilder
    private var dragLayer: some View {
        if let drag = model.drag {
            let cell = BoardMetrics(n: rules.board.size, size: boardFrame.size).cell
            let length = CGFloat(drag.kind.length) * cell
            let size = drag.orientation == .horizontal ? CGSize(width: length, height: cell) : CGSize(width: cell, height: length)
            let grabOffset = (CGFloat(drag.grabIndex) + 0.5) * cell
            let valid = model.candidate(boardFrame: boardFrame, lift: lift).map { model.fleet.canPlace($0, rules: rules) } ?? false
            Canvas { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize)
                if boardStyle == .pegboard {
                    PegboardPainter.drawPiece(kind: drag.kind, orientation: drag.orientation, in: rect, context: context, highlight: valid ? theme.accent : theme.danger, lifted: true)
                } else {
                    ShipPainter.draw(kind: drag.kind, orientation: drag.orientation, in: rect, context: context, skin: skin, theme: theme, look: .floating(valid: valid))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.06)
            .position(
                x: drag.location.x + (drag.orientation == .horizontal ? size.width / 2 - grabOffset : 0),
                y: drag.location.y - lift + (drag.orientation == .vertical ? size.height / 2 - grabOffset : 0)
            )
            .allowsHitTesting(false)
        }
    }
}
