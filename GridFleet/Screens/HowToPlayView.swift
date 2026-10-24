import GridFleetCore
import SwiftUI

/// A short illustrated guide.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var page = 0

    private struct Page {
        let eyebrow: String
        let title: String
        let body: String
        let scene: BoardScene
    }

    private var pages: [Page] {
        [
            Page(eyebrow: "Goal", title: "Sink their fleet first", body: "Each captain hides five ships on a 10 × 10 grid. Take turns firing one shot. Sink every enemy ship before they sink yours.", scene: Self.fleetScene),
            Page(eyebrow: "Deploy", title: "Hide your ships", body: "Drag ships onto the grid. Tap a ship to select it, tap again to rotate. Shuffle for a random layout.", scene: Self.fleetScene),
            Page(eyebrow: "Fire", title: "Aim, then fire", body: "Tap a cell to aim and tap again to fire. A white ring is a miss. A burning mark is a hit. Hit every section of a ship and it sinks.", scene: Self.shotsScene),
            Page(eyebrow: "The fold", title: "Open it like the board game", body: "Half-fold your iPhone Duo: the enemy grid stands up on top and your fleet lies flat below. Opening the phone on your turn raises the periscope. In pass and play, closing it hides your fleet.", scene: Self.shotsScene),
            Page(eyebrow: "Variants", title: "Salvo & specials", body: "Salvo gives one shot per ship still afloat. Special weapons add a torpedo that runs a whole row, a five-cell barrage, and a sonar ping that counts ship sections nearby.", scene: Self.sonarScene),
            Page(eyebrow: "Fair play", title: "Sealed fleets", body: "Online, your fleet never leaves your phone. Only a sealed fingerprint is shared. At the end both fleets are revealed and checked against their seals and every reported hit.", scene: Self.fleetScene),
        ]
    }

    var body: some View {
        ZStack {
            OceanBackdrop()
            VStack(spacing: Space.l) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: Space.xl) {
                            BoardView(scene: page.scene)
                                .frame(maxWidth: 300, maxHeight: 300)
                            VStack(spacing: Space.xs) {
                                Text("\(index + 1) of \(pages.count) · \(page.eyebrow)").font(.subheadline).foregroundStyle(theme.inkSecondary)
                                Text(page.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                                Text(page.body).font(.body).foregroundStyle(theme.inkSecondary).multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, Space.xl)
                        }
                        .frame(maxHeight: .infinity)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button(page == pages.count - 1 ? "Start playing" : "Next") {
                    if page == pages.count - 1 {
                        Analytics.shared.capture("tutorial_closed", ["page": .int(page + 1), "pages": .int(pages.count), "finished": true])
                        dismiss()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.fleet)
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.s)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    Analytics.shared.capture("tutorial_closed", ["page": .int(page + 1), "pages": .int(pages.count), "finished": false])
                    dismiss()
                }
            }
        }
    }

    private static func ship(_ kind: ShipKind, _ row: Int, _ column: Int, _ orientation: Orientation, damaged: Set<Int> = [], look: ShipLook = .own) -> BoardScene.ShipDrawing {
        BoardScene.ShipDrawing(ship: PlacedShip(kind: kind, origin: Coordinate(row: row, column: column), orientation: orientation), look: look, damaged: damaged)
    }

    static let fleetScene: BoardScene = {
        var scene = BoardScene(size: 10)
        scene.ships = [
            ship(.carrier, 1, 1, .horizontal),
            ship(.cruiser, 3, 7, .vertical),
            ship(.destroyer, 6, 2, .horizontal),
            ship(.submarine, 4, 0, .vertical),
            ship(.patrol, 8, 6, .horizontal),
        ]
        return scene
    }()

    static let shotsScene: BoardScene = {
        var scene = BoardScene(size: 10)
        scene.ships = [ship(.destroyer, 6, 2, .horizontal, look: .enemySunk)]
        scene.marks = [
            Coordinate(row: 6, column: 2): .sunk, Coordinate(row: 6, column: 3): .sunk, Coordinate(row: 6, column: 4): .sunk,
            Coordinate(row: 2, column: 5): .hit, Coordinate(row: 2, column: 6): .hit,
            Coordinate(row: 1, column: 1): .miss, Coordinate(row: 4, column: 8): .miss, Coordinate(row: 8, column: 3): .miss, Coordinate(row: 2, column: 2): .miss,
        ]
        scene.aims = [Coordinate(row: 2, column: 7)]
        return scene
    }()

    static let sonarScene: BoardScene = {
        var scene = BoardScene(size: 10)
        scene.sonar = [SonarReading(center: Coordinate(row: 3, column: 3), contacts: 2), SonarReading(center: Coordinate(row: 7, column: 7), contacts: 0)]
        scene.marks = [Coordinate(row: 5, column: 1): .miss, Coordinate(row: 1, column: 8): .hit]
        scene.footprint = .lane(TorpedoLane(direction: .east, index: 9))
        return scene
    }()
}
