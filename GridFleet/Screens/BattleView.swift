import FoldKit
import GridFleetCore
import SwiftUI

struct BattleActions {
    var onLeave: () -> Void
    var onRematch: (() -> Void)?
    /// Pass and play: cover the fleet.
    var onHide: (() -> Void)?
    var leaveLabel = "Back to harbor"
}

/// The battle screen. Lays itself out for the fold:
/// half-folded or flat, the enemy grid sits above the hinge and your fleet below; in landscape
/// they sit side by side; on a regular phone the enemy grid fills the screen and your fleet is a swipe away.
struct BattleView: View {
    let session: BattleSession
    let actions: BattleActions

    enum Tab: Hashable { case enemy, fleet }
    enum Layout { case folded, sideBySide, compact }

    @Environment(AppSettings.self) private var settings
    @Environment(\.foldState) private var fold
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.boardStyle) private var boardStyle
    @Environment(\.hingeAngle) private var hingeAngle

    @State private var tab: Tab = .enemy
    @State private var showsPeriscope = false
    @State private var showsResult = false
    @State private var confirmsResign = false
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        ZStack {
            OceanBackdrop(strength: 0.04, animated: false)
            GeometryReader { proxy in
                switch layout(for: proxy.size) {
                case .folded: foldedLayout
                case .sideBySide: sideBySideLayout
                case .compact: compactLayout
                }
            }
            if coachTip != nil {
                VStack {
                    Spacer()
                    coachCard
                }
                .zIndex(8)
            }
            if session.showsIntro, let rival = session.rival {
                RivalIntro(rival: rival, captain: session.myName, line: session.introLine) {
                    withAnimation(.easeOut(duration: 0.3)) { session.showsIntro = false }
                    if let line = session.introLine { session.rivalMood = line.mood }
                    if session.status == .yourTurn { raisePeriscope() }
                }
                .transition(.opacity)
                .zIndex(9)
            }
            if showsResult, let outcome = session.outcome {
                ResultView(outcome: outcome, session: session, onRematch: actions.onRematch, onDone: actions.onLeave)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // A hardware keyboard: arrows aim, Space marks a target, Return fires, 1 to 4 pick a weapon.
        .focusable(interactions: .edit)
        .focused($keyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .task { keyboardFocus = true }
        .onChange(of: boardStyle, initial: true) { _, style in session.pegStyle = style == .pegboard }
        .onAppear {
            session.reduceMotion = reduceMotion
            if session.outcome != nil { showsResult = true }
        }
        .onChange(of: fold.posture) { old, new in
            // Opening the phone onto your turn raises the periscope.
            if old == .closed || old == .unfoldable, new.spansFold, session.status == .yourTurn { raisePeriscope() }
        }
        .onChange(of: session.turnStartCount) { _, count in
            if count == 1, !session.showsIntro { raisePeriscope() }
            if settings.followAction {
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    withAnimation(.smooth) { tab = .enemy }
                }
            }
        }
        .onChange(of: session.incomingCount) {
            if settings.followAction { withAnimation(.smooth) { tab = .fleet } }
        }
        .onChange(of: coachSignal, initial: true) {
            guard !session.showsIntro else { return }
            withAnimation(.smooth) { session.coach?.observe(session) }
        }
        .onChange(of: session.outcome) { _, outcome in
            guard outcome != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.3))
                withAnimation(.smooth(duration: 0.4)) { showsResult = true }
            }
        }
        .confirmationDialog("Resign this battle?", isPresented: $confirmsResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { session.onResign?() }
        } message: {
            Text("It counts as a loss.")
        }
    }

    private func layout(for size: CGSize) -> Layout {
        if fold.splitsWindow { return .folded }
        if size.width > size.height * 1.1 { return .sideBySide }
        // A tall iPad has room for the board-game layout: enemy above, fleet below.
        if sizeClass == .regular && size.width >= 700 { return .folded }
        return .compact
    }

    private func raisePeriscope() {
        guard !reduceMotion else { return }
        Haptics.periscope()
        showsPeriscope = true
    }

    // MARK: Layouts

    private var foldedLayout: some View {
        FoldSplit(gutter: Space.l) {
            GeometryReader { proxy in
                if isWide(proxy.size) {
                    targetPanel(wide: true, in: proxy.size, includesHUD: true)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                } else {
                    VStack(spacing: Space.s) {
                        hud
                        GeometryReader { inner in
                            targetPanel(wide: false, in: inner.size)
                                .frame(width: inner.size.width, height: inner.size.height, alignment: .top)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.xxs)
            .environment(\.lidLight, lidLight(.lid))
        } second: {
            GeometryReader { proxy in
                fleetPanel(wide: isWide(proxy.size), in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .padding(.horizontal, Space.m)
            .padding(.bottom, Space.xs)
            .environment(\.lidLight, lidLight(.tray))
        }
    }

    /// Lighting for a half fold held like a laptop, where one half stands over the other.
    private func lidLight(_ role: LidLight.Role) -> LidLight? {
        guard fold.posture == .halfFolded, fold.splitsWindow, fold.hingeIsHorizontal, let hingeAngle else { return nil }
        return LidLight(role: role, hingeAngle: hingeAngle)
    }

    /// A half that's clearly wider than tall puts controls beside the board instead of under it.
    /// That's each half of iPhone Duo held like a laptop.
    private func isWide(_ size: CGSize) -> Bool {
        size.width > size.height * 1.3
    }

    private static let sideColumnWidth: CGFloat = 260

    /// The board's side in a wide half: as tall as the half, leaving room for the side column.
    private func wideBoardSide(_ size: CGSize) -> CGFloat {
        max(0, min(size.height, size.width - Self.sideColumnWidth - Space.l))
    }

    private var sideBySideLayout: some View {
        VStack(spacing: Space.s) {
            hud
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: Space.xxl) {
                targetPanel(wide: false)
                fleetPanel(wide: false)
            }
            .frame(maxWidth: 1400)
            Spacer(minLength: 0)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactLayout: some View {
        VStack(spacing: Space.s) {
            hud
            Picker("Board", selection: $tab) {
                Text("Enemy waters").tag(Tab.enemy)
                Text("Your fleet").tag(Tab.fleet)
            }
            .pickerStyle(.segmented)
            TabView(selection: $tab) {
                VStack(spacing: Space.m) {
                    targetPanel(wide: false)
                    miniFleet
                    Spacer(minLength: 0)
                }
                .tag(Tab.enemy)
                fleetPanel(wide: false)
                    .tag(Tab.fleet)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xxs)
    }

    /// Your fleet in miniature under the enemy grid. Tap to switch over.
    private var miniFleet: some View {
        Button {
            Haptics.tap()
            withAnimation(.smooth) { tab = .fleet }
        } label: {
            HStack(spacing: Space.m) {
                BoardView(scene: session.oceanScene, fx: session.oceanFX, showsLabels: false)
                    .frame(width: 76, height: 76)
                    .modifier(ShakeEffect(animatableData: session.oceanShake))
                    .animation(.easeOut(duration: 0.55), value: session.oceanShake)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your fleet").font(.headline)
                    Text("\(session.ocean.shipsAfloat.count) of \(session.ocean.fleet.ships.count) ships afloat")
                        .font(.subheadline)
                        .foregroundStyle(theme.inkSecondary)
                }
                Spacer()
                DisclosureChevron()
            }
            .foregroundStyle(theme.ink)
            .padding(Space.s)
            .surface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Your fleet, \(session.ocean.shipsAfloat.count) of \(session.ocean.fleet.ships.count) ships afloat")
        .accessibilityHint("Shows your fleet")
    }

    // MARK: HUD

    /// The HUD for a side column: menu and timer on one row, status under it.
    private var sideHUD: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                battleMenu
                Spacer()
                if let deadline = session.turnDeadline, session.status == .yourTurn {
                    TurnTimerRing(deadline: deadline, total: 30).frame(width: 40, height: 40)
                } else if let onHide = actions.onHide, session.status != .finished {
                    CircleIconButton(systemImage: "eye.slash", label: "Hide my fleet", size: 40, action: onHide)
                }
            }
            TurnStatusView(session: session, alignment: .leading)
        }
    }

    private var battleMenu: some View {
        Menu {
            if let onHide = actions.onHide, session.status != .finished {
                Button("Hide my fleet", systemImage: "eye.slash", action: onHide)
            }
            if let coach = session.coach, coach.isActive {
                Button("Skip tips", systemImage: "lightbulb.slash") { withAnimation(.smooth) { coach.skip() } }
            }
            if session.status != .finished {
                Button("Resign", systemImage: "flag", role: .destructive) { confirmsResign = true }
            }
            Button(actions.leaveLabel, systemImage: "chevron.backward", action: actions.onLeave)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Battle menu")
    }

    private var hud: some View {
        HStack(spacing: Space.s) {
            battleMenu
            Spacer(minLength: 0)
            TurnStatusView(session: session)
            Spacer(minLength: 0)
            Group {
                if let deadline = session.turnDeadline, session.status == .yourTurn {
                    TurnTimerRing(deadline: deadline, total: 30)
                } else if let onHide = actions.onHide, session.status != .finished {
                    CircleIconButton(systemImage: "eye.slash", label: "Hide my fleet", size: 40, action: onHide)
                } else {
                    Color.clear
                }
            }
            .frame(width: 40, height: 40)
        }
    }

    // MARK: Panels

    private var targetHeader: some View {
        PanelHeader(
            title: session.opponentName,
            detail: session.opponentDetail,
            fleet: session.rules.fleet,
            sunk: Set(session.target.sunkShips.map(\.id)),
            enemy: true,
            rival: session.rival,
            rivalMood: session.rivalMood,
            line: session.showsIntro ? nil : session.rivalLine
        )
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !session.showsIntro, !showsResult else { return .ignored }
        switch press.key {
        case .upArrow: session.moveCursor(rows: -1, columns: 0)
        case .downArrow: session.moveCursor(rows: 1, columns: 0)
        case .leftArrow: session.moveCursor(rows: 0, columns: -1)
        case .rightArrow: session.moveCursor(rows: 0, columns: 1)
        case .space: session.toggleAimAtCursor()
        case .return: session.fireFromKeyboard()
        default:
            if let digit = Int(press.characters), (1...4).contains(digit) {
                session.selectWeapon(at: digit - 1)
            } else if press.characters.lowercased() == "t", session.weapon == .torpedo {
                session.torpedoAlongColumns.toggle()
            } else {
                return .ignored
            }
        }
        // Aiming happens on the enemy board; firing leaves "follow the action" free to swing away.
        if press.key != .return { withAnimation(.smooth(duration: 0.15)) { tab = .enemy } }
        return .handled
    }

    // MARK: Coaching

    /// What the coach watches for: aiming, firing, being fired at, and the intro ending.
    private var coachSignal: [Int] {
        guard session.coach?.isActive == true else { return [] }
        return [session.aims.count, session.target.shotsFired, session.incomingCount, session.status == .yourTurn ? 1 : 0, session.showsIntro ? 1 : 0]
    }

    private var coachStep: Coach.Step? {
        guard let coach = session.coach, coach.isActive, !session.showsIntro else { return nil }
        return coach.step
    }

    private var coachTip: String? {
        guard let step = coachStep else { return nil }
        // Tips are about aiming, so they wait out the rival's turn, when the screen is busy elsewhere.
        guard session.status == .yourTurn else { return nil }
        let pegs = boardStyle == .pegboard
        let text: String? = switch step {
        case .deploy: nil
        case .aim: "These are my waters. Tap any square to aim at it."
        case .fire: "Now tap Fire, or the same square again, to take your shot."
        case .result: pegs
            ? "See your peg? White means a miss, red means a hit. My shots on your fleet are marked the same way."
            : "See your mark? A white ring means a miss, fire means a hit. My shots on your fleet are marked the same way."
        case .goal: "That's the whole game: sink all five of my ships before I sink yours!"
        case .done: nil
        }
        return text
    }

    private var coachCard: some View {
        CoachCard(
            text: coachTip ?? "",
            number: coachNumber,
            total: 4,
            onSkip: { withAnimation(.smooth) { session.coach?.skip() } }
        )
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.s)
        .transition(.opacity)
    }

    private var coachNumber: Int {
        switch coachStep {
        case .fire: 2
        case .result: 3
        case .goal: 4
        default: 1
        }
    }

    private var targetBoard: some View {
        let scene = session.targetScene
        return BoardView(
            scene: scene,
            fx: session.targetFX,
            onTap: session.canAim ? { cell in
                session.cursor = nil
                session.tapTarget(cell, oneTapFire: settings.oneTapFire)
            } : nil,
            describeCell: { scene.describe($0) },
            highlight: session.canAim ? session.cursor : nil
        )
        .accessibilityIdentifier("enemy-board")
        .overlay {
            if coachStep == .aim, session.canAim {
                CoachPulse(cornerRadius: 12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay {
            if showsPeriscope {
                PeriscopeOverlay { showsPeriscope = false }
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            BannerOverlay(banner: session.banner?.onOcean == false ? session.banner : nil)
        }
    }

    @ViewBuilder
    private var targetControls: some View {
        if session.status != .finished {
            WeaponTray(session: session, highlightsFire: coachStep == .fire && session.canAim)
        }
        if let note = session.waitingNote, session.status != .yourTurn {
            Text(note)
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func targetPanel(wide: Bool, in size: CGSize = .zero, includesHUD: Bool = false) -> some View {
        if wide {
            let side = wideBoardSide(size)
            HStack(alignment: .top, spacing: Space.l) {
                targetBoard
                    .frame(width: side, height: side)
                VStack(alignment: .leading, spacing: Space.s) {
                    if includesHUD { sideHUD }
                    targetHeader
                    Spacer(minLength: 0)
                    targetControls
                }
                .frame(width: Self.sideColumnWidth, height: side)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Space.s) {
                targetHeader
                targetBoard
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                targetControls
            }
        }
    }

    private var fleetHeader: some View {
        PanelHeader(
            title: "Your fleet",
            detail: session.myName,
            fleet: session.rules.fleet,
            sunk: Set(session.ocean.sunkShips.map(\.id)),
            enemy: false
        )
    }

    private var fleetBoard: some View {
        let scene = session.oceanScene
        return BoardView(scene: scene, fx: session.oceanFX, describeCell: { scene.describe($0) })
            .accessibilityIdentifier("fleet-board")
            .modifier(ShakeEffect(animatableData: session.oceanShake))
            .animation(.easeOut(duration: 0.55), value: session.oceanShake)
            .overlay(alignment: .top) {
                BannerOverlay(banner: session.banner?.onOcean == true ? session.banner : nil)
            }
    }

    @ViewBuilder
    private func fleetPanel(wide: Bool, in size: CGSize = .zero) -> some View {
        if wide {
            let side = wideBoardSide(size)
            HStack(alignment: .top, spacing: Space.l) {
                fleetBoard
                    .frame(width: side, height: side)
                VStack(alignment: .leading, spacing: Space.s) {
                    fleetHeader
                    Spacer(minLength: 0)
                    StatsStrip(target: session.target, ocean: session.ocean)
                }
                .frame(width: Self.sideColumnWidth, height: side)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Space.s) {
                fleetHeader
                fleetBoard
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                StatsStrip(target: session.target, ocean: session.ocean)
            }
        }
    }
}

// MARK: - Parts

/// Whose turn it is, in words.
struct TurnStatusView: View {
    let session: BattleSession
    var alignment: HorizontalAlignment = .center
    @Environment(\.theme) private var theme

    var body: some View {
        let (title, color) = content
        VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 6) {
                // No animation: the title changes width, and an animated dot would lag into the text.
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(theme.inkSecondary)
                .monospacedDigit()
        }
        .foregroundStyle(theme.ink)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("turn-status")
    }

    private var subtitle: String {
        let turn = "Turn \(max(1, session.target.shotsFired == 0 ? 1 : session.turnStartCount))"
        if session.status == .yourTurn, session.shotsAllowed > 1 { return "\(turn) · \(session.shotsAllowed) shots" }
        return turn
    }

    private var content: (String, Color) {
        switch session.status {
        case .yourTurn: ("Your turn", theme.accent)
        case .opponentAiming: ("\(session.opponentName) is aiming", theme.hit)
        case .waitingForOpponent: ("Waiting for \(session.opponentName)", theme.inkSecondary)
        case .resolving: ("Firing", theme.hit)
        case .finished: ("Battle over", theme.inkSecondary)
        }
    }
}

struct PanelHeader: View {
    let title: String
    let detail: String
    let fleet: [ShipKind]
    let sunk: Set<String>
    let enemy: Bool
    var rival: Rival?
    var rivalMood: RivalMood = .neutral
    /// What the rival is saying, shown in place of the caption. Space for two lines is kept so the board doesn't move.
    var line: RivalLine?
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: rival == nil ? .center : .top, spacing: Space.s) {
            if let rival {
                RivalFlag(rival: rival, mood: rivalMood, talking: line != nil)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let line, let rival {
                    TypedLine(line: line, rival: rival)
                } else {
                    Text(detail).font(.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
            }
            .frame(minHeight: rival == nil ? nil : 52, alignment: .top)
            .animation(.smooth(duration: 0.2), value: line?.id)
            Spacer(minLength: Space.xs)
            FleetPegs(fleet: fleet, sunk: sunk, enemy: enemy)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(fleet.count - sunk.count) of \(fleet.count) ships afloat")
        }
        .foregroundStyle(theme.ink)
        .frame(minHeight: 36)
    }
}

/// The fleet as rows of pegs, one row per ship, like the pegboard of the folding game.
struct FleetPegs: View {
    let fleet: [ShipKind]
    let sunk: Set<String>
    let enemy: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(fleet.sorted { $0.length > $1.length }) { kind in
                let isSunk = sunk.contains(kind.id)
                HStack(spacing: 2) {
                    ForEach(0..<kind.length, id: \.self) { _ in
                        Capsule()
                            .fill(isSunk ? theme.sunk.opacity(0.8) : (enemy ? theme.ink.opacity(0.4) : theme.accent.opacity(0.85)))
                            .frame(width: 6, height: 3)
                    }
                }
            }
        }
    }
}

/// Shots, hits, accuracy and ships afloat.
struct StatsStrip: View {
    let target: TargetBoard
    let ocean: OceanGrid
    @Environment(\.theme) private var theme

    var body: some View {
        let accuracy = target.shotsFired == 0 ? 0 : Int((Double(target.hitCount) / Double(target.shotsFired) * 100).rounded())
        HStack(spacing: 0) {
            stat("Shots", "\(target.shotsFired)").accessibilityIdentifier("stat-shots")
            stat("Hits", "\(target.hitCount)")
            stat("Accuracy", "\(accuracy)%")
            stat("Afloat", "\(ocean.shipsAfloat.count)/\(ocean.fleet.ships.count)")
        }
        .padding(.vertical, Space.xs)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(theme.ink).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct WeaponTray: View {
    let session: BattleSession
    /// Draws the eye to Fire while a first game's tips are on that step.
    var highlightsFire = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Space.xs) {
            if session.rules.specialWeapons {
                ForEach(Weapon.allCases) { weapon in
                    weaponButton(weapon)
                }
                if session.weapon == .torpedo {
                    Button {
                        Haptics.aim()
                        session.torpedoAlongColumns.toggle()
                    } label: {
                        Image(systemName: session.torpedoAlongColumns ? "arrow.up.and.down" : "arrow.left.and.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(theme.ink.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.torpedoAlongColumns ? "Torpedo runs down a column" : "Torpedo runs along a row")
                }
                Spacer(minLength: 0)
            } else {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(fireTitle) { session.fire() }
                .buttonStyle(.fleet(.primary, compact: true))
                .disabled(!session.isReadyToFire)
                .keyboardShortcut(.return, modifiers: [])
                .background {
                    if highlightsFire { CoachPulse(cornerRadius: 999, spread: 6) }
                }
                .accessibilityIdentifier("fire")
        }
        .frame(minHeight: 40)
        .opacity(session.canAim ? 1 : 0.5)
        .animation(.smooth(duration: 0.2), value: session.weapon)
    }

    private var hint: String {
        guard session.canAim else { return "Stand by" }
        if session.shotsAllowed > 1 { return "Choose \(session.shotsAllowed) targets, then fire" }
        return session.aims.isEmpty ? "Tap a cell to aim" : "Tap again or press Fire"
    }

    private var fireTitle: String {
        if session.weapon == .shell, session.shotsAllowed > 1, session.aims.count < session.shotsAllowed {
            return "Fire \(session.aims.count)/\(session.shotsAllowed)"
        }
        return "Fire"
    }

    private func icon(_ weapon: Weapon) -> String {
        switch weapon {
        case .shell: "circle.fill"
        case .barrage: "plus"
        case .torpedo: "arrow.right.to.line"
        case .sonar: "dot.radiowaves.left.and.right"
        }
    }

    private func weaponButton(_ weapon: Weapon) -> some View {
        let count = session.arsenal.count(of: weapon)
        let available = weapon == .shell || count > 0
        let selected = session.weapon == weapon
        return Button {
            guard available, session.canAim else { return }
            Haptics.aim()
            session.weapon = weapon
        } label: {
            Image(systemName: icon(weapon))
                .font(.system(size: weapon == .shell ? 9 : 14, weight: .bold))
                .foregroundStyle(selected ? theme.onAccent : theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(selected ? theme.accent : theme.ink.opacity(0.08)))
                .overlay(alignment: .topTrailing) {
                    if weapon.isSpecial {
                        Text("\(count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(theme.ink)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(theme.backdropBottom))
                            .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                            .offset(x: 3, y: -3)
                    }
                }
                .opacity(available ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weapon.displayName)\(weapon.isSpecial ? ", \(count) left" : ""). \(weapon.explanation)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A brief label over a board: "Hit", "Miss", "Cruiser sunk".
struct BannerOverlay: View {
    let banner: Banner?
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let banner {
                HStack(spacing: Space.xs) {
                    Text(banner.title).font(.subheadline.weight(.bold))
                    if let subtitle = banner.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(theme.ink.opacity(0.75))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(color(banner.tone))
                .padding(.horizontal, Space.s)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.backdropBottom.opacity(0.92)))
                .overlay(Capsule().strokeBorder(color(banner.tone).opacity(0.5), lineWidth: 1))
                .padding(.top, Space.m)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(banner.id)
                .onAppear {
                    UIAccessibility.post(notification: .announcement, argument: [banner.title, banner.subtitle].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: banner?.id)
        .allowsHitTesting(false)
    }

    private func color(_ tone: Banner.Tone) -> Color {
        switch tone {
        case .hit: theme.hit
        case .miss: theme.ink
        case .sunk: theme.sunk
        case .info: theme.accent
        case .danger: theme.danger
        }
    }
}

struct TurnTimerRing: View {
    let deadline: Date
    let total: TimeInterval
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let left = max(0, deadline.timeIntervalSince(timeline.date))
            let urgent = left < 8
            ZStack {
                Circle().stroke(theme.ink.opacity(0.12), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: left / total)
                    .stroke(urgent ? theme.danger : theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(left.rounded(.up)))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(urgent ? theme.danger : theme.ink)
            }
            .padding(3)
            .accessibilityLabel("\(Int(left)) seconds left")
        }
    }
}
