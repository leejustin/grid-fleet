import GridFleetCore
import SwiftUI

/// The store, and where you equip themes, hulls and explosions.
struct ShipyardView: View {
    var focus: Unlock?

    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var buying: Unlock?

    var body: some View {
        ScrollViewReader { proxy in
            ScreenScroll {
                admiralCard.id(Unlock.admiral)
                pack(.oceans) { themes }.id(Unlock.oceans)
                pack(.hulls) { hulls }.id(Unlock.hulls)
                pack(.blasts) { blasts }.id(Unlock.blasts)
                footer
            }
            .onAppear {
                if let focus { proxy.scrollTo(focus, anchor: .top) }
            }
        }
        .oceanNavigation("Shipyard")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Admiral

    private var admiralCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                RivalFlag(rival: .thorn, mood: .smug)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Unlock.admiral.title).font(.headline)
                    Text("One purchase, yours to keep").font(.subheadline).foregroundStyle(theme.inkSecondary)
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                feature("Admiral Thorn", "The hardest opponent. Maps every place your ships could hide.")
                feature("Salvo", "One shot for every ship still afloat.")
                feature("Skirmish and Open Ocean", "Quick 8 × 8 games and long 12 × 12 ones.")
                feature("Special weapons", "Torpedo, barrage and sonar ping.")
            }
            buyButton(.admiral)
        }
        .padding(Space.m)
        .surface()
    }

    private func feature(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Packs

    private func pack<Content: View>(_ unlock: Unlock, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unlock.title).font(.headline)
                    Text(unlock.pitch).font(.footnote).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: Space.xs)
                buyButton(unlock, compact: true)
            }
            .padding(.horizontal, Space.xxs)
            content()
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Space.s)]

    private var themes: some View {
        LazyVGrid(columns: columns, spacing: Space.s) {
            ForEach(Theme.all) { option in
                let allowed = store.allows(option.id)
                tile(selected: settings.themeID == option.id, locked: !allowed, title: option.name, detail: option.tagline) {
                    guard allowed else { return }
                    Haptics.aim()
                    settings.themeID = option.id
                } preview: {
                    ThemeSwatch()
                        .environment(\.theme, option)
                        .frame(height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var hulls: some View {
        LazyVGrid(columns: columns, spacing: Space.s) {
            ForEach(ShipSkin.all) { skin in
                let allowed = store.allows(skin.id)
                tile(selected: settings.skinID == skin.id, locked: !allowed, title: skin.name, detail: nil) {
                    guard allowed else { return }
                    Haptics.aim()
                    settings.skinID = skin.id
                } preview: {
                    VStack(spacing: Space.xs) {
                        ShipGlyph(kind: .carrier).frame(height: 18)
                        ShipGlyph(kind: .cruiser).frame(height: 16)
                        ShipGlyph(kind: .submarine).frame(height: 14)
                    }
                    .environment(\.shipSkin, skin)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.waterShallow.opacity(0.5)))
                }
            }
        }
    }

    private var blasts: some View {
        LazyVGrid(columns: columns, spacing: Space.s) {
            ForEach(BlastStyle.allCases) { style in
                let allowed = store.allows(style)
                tile(selected: settings.blastStyle == style, locked: !allowed, title: style.name, detail: nil) {
                    guard allowed else { return }
                    Haptics.hit()
                    settings.blastStyle = style
                } preview: {
                    BlastPreview()
                        .environment(\.blastStyle, style)
                        .frame(height: 92)
                }
            }
        }
    }

    private func tile<Preview: View>(selected: Bool, locked: Bool, title: String, detail: String?, action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xs) {
                preview()
                HStack(spacing: Space.xxs) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if locked {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(theme.inkSecondary)
                    } else if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                    }
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(Space.xs)
            .surface(Radius.small)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: selected ? 2 : 0)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(title)\(locked ? ", locked" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func buyButton(_ unlock: Unlock, compact: Bool = false) -> some View {
        if store.owned.contains(unlock) {
            Label("Owned", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
        } else {
            Button {
                buying = unlock
                Task {
                    await store.purchase(unlock)
                    buying = nil
                }
            } label: {
                if buying == unlock {
                    ProgressView()
                } else {
                    Text(compact ? store.price(of: unlock) : "Unlock for \(store.price(of: unlock))")
                }
            }
            .buttonStyle(.fleet(compact ? .secondary : .primary, compact: compact))
            .disabled(buying != nil)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let error = store.lastError {
                Text(error).font(.footnote).foregroundStyle(theme.danger)
            }
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            .font(.subheadline)
            Text("No ads during battles, and nothing here helps you win. The Admiral's Commission adds opponents and modes; everything else changes how the game looks.")
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
        }
    }
}

/// A miniature board in the surrounding theme.
private struct ThemeSwatch: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.backdrop
            BoardView(scene: Self.scene, showsLabels: false)
                .padding(8)
        }
    }

    static let scene: BoardScene = {
        var scene = BoardScene(size: 6)
        scene.ships = [BoardScene.ShipDrawing(ship: PlacedShip(kind: .cruiser, origin: Coordinate(row: 1, column: 1), orientation: .horizontal), look: .own, damaged: [1])]
        scene.marks = [Coordinate(row: 1, column: 2): .hit, Coordinate(row: 3, column: 4): .miss, Coordinate(row: 4, column: 1): .miss]
        scene.ships.append(BoardScene.ShipDrawing(ship: PlacedShip(kind: .patrol, origin: Coordinate(row: 3, column: 0), orientation: .vertical), look: .own))
        return scene
    }()
}

/// Loops one explosion in the surrounding blast style.
private struct BlastPreview: View {
    @State private var fx = BoardFX()

    var body: some View {
        BoardView(scene: BoardScene(size: 3), fx: fx, showsLabels: false)
            .task {
                while !Task.isCancelled {
                    var next = BoardFX()
                    let now = Date.now
                    next.effects = [BoardEffect(cell: Coordinate(row: 1, column: 1), kind: .blast(big: true), start: now, duration: 1.5)]
                    next.lastImpact = (Coordinate(row: 1, column: 1), now)
                    fx = next
                    try? await Task.sleep(for: .seconds(2.2))
                }
            }
    }
}
