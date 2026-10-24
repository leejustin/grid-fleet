import GridFleetCore
import SwiftData
import SwiftUI

/// Set up a game against the computer or a friend on this phone.
struct NewGameView: View {
    let mode: GameMode

    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var rules = GameRules.classic
    @State private var difficulty = AIDifficulty.medium
    @State private var homeName = ""
    @State private var awayName = "Player 2"

    var body: some View {
        NavigationStack {
            ScreenScroll {
                if mode == .computer {
                    ContentSection("Opponent") { opponents }
                } else {
                    ContentSection("Captains") { names }
                }
                RulesPicker(rules: $rules)
            }
            .safeAreaInset(edge: .bottom) {
                Button(mode == .computer ? "Deploy fleet" : "Start", action: start)
                    .buttonStyle(.fleet)
                    .accessibilityIdentifier("start-game")
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.xs)
                    .background {
                        LinearGradient(stops: [.init(color: theme.backdropBottom.opacity(0), location: 0), .init(color: theme.backdropBottom, location: 0.3)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                    }
            }
            .oceanNavigation(mode == .computer ? "New game" : "Pass and play")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationBackground(theme.backdropBottom)
        .onAppear {
            rules = store.allows(settings.lastRules) ? settings.lastRules : .classic
            difficulty = store.allows(settings.lastDifficulty) ? settings.lastDifficulty : .medium
            homeName = settings.playerName
        }
    }

    private var opponents: some View {
        VStack(spacing: 0) {
            ForEach(Array(AIDifficulty.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { RowDivider(inset: Space.m + 48 + Space.s) }
                opponentRow(level)
            }
        }
        .surface()
    }

    private func opponentRow(_ level: AIDifficulty) -> some View {
        let rival = Rival.for(level)
        let locked = !store.allows(level)
        let selected = difficulty == level
        return Button {
            if locked {
                router.openShipyard(focus: .admiral)
            } else {
                Haptics.aim()
                difficulty = level
            }
        } label: {
            HStack(spacing: Space.s) {
                if !typeSize.isAccessibilitySize {
                    RivalFlag(rival: rival, mood: selected ? .smug : .neutral)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    // At accessibility sizes the level goes under the name so names don't break mid-word.
                    let nameLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: Space.xs))
                    nameLayout {
                        Text(rival.fullName).font(.headline)
                        Chip(text: level.level)
                    }
                    Text(rival.tagline).font(.subheadline).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: Space.xs)
                if locked {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(theme.inkSecondary)
                } else {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? theme.accent : theme.inkSecondary.opacity(0.5))
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(rival.fullName), \(level.level). \(rival.tagline)\(locked ? ". Locked" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var names: some View {
        VStack(spacing: 0) {
            nameField("First captain", text: $homeName)
            RowDivider(inset: Space.m)
            nameField("Second captain", text: $awayName)
        }
        .surface()
    }

    private func nameField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.body)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, Space.m)
            .frame(minHeight: 52)
    }

    private func start() {
        settings.lastRules = rules
        let game: LocalGame
        if mode == .computer {
            settings.lastDifficulty = difficulty
            game = LocalGame(rules: rules, opponent: .computer(difficulty), names: [settings.playerName, Rival.for(difficulty).fullName])
        } else {
            let home = homeName.trimmingCharacters(in: .whitespaces).isEmpty ? "Player 1" : homeName
            let away = awayName.trimmingCharacters(in: .whitespaces).isEmpty ? "Player 2" : awayName
            game = LocalGame(rules: rules, opponent: .human, names: [home, away])
        }
        let context = modelContext
        game.onComplete = { summary in Persistence.record(summary, in: context) }
        dismiss()
        router.activeGame = .local(game)
    }
}

/// Board size and optional rules. Locked options open the Shipyard.
struct RulesPicker: View {
    @Binding var rules: GameRules
    @Environment(StoreService.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ContentSection("Board") {
                HStack(spacing: Space.xs) {
                    ForEach(BoardPreset.allCases) { preset in
                        presetTile(preset)
                    }
                }
            }
            ContentSection("Rules") {
                VStack(spacing: 0) {
                    ruleRow("Salvo", detail: "One shot per ship still afloat", isOn: Binding(
                        get: { rules.firing == .salvo },
                        set: { rules.firing = $0 ? .salvo : .single }
                    ), locked: !store.allowsSalvo)
                    RowDivider(inset: Space.m)
                    ruleRow("Special weapons", detail: "Torpedo, barrage and sonar ping", isOn: $rules.specialWeapons, locked: !store.allowsSpecials)
                    RowDivider(inset: Space.m)
                    ruleRow("Ships may touch", detail: "Turn off to require a gap, even diagonally", isOn: $rules.shipsMayTouch, locked: false)
                }
                .surface()
            }
        }
    }

    private func presetTile(_ preset: BoardPreset) -> some View {
        let locked = !store.allows(preset)
        let selected = rules.preset == preset
        return Button {
            if locked {
                router.openShipyard(focus: .admiral)
            } else {
                Haptics.aim()
                rules.preset = preset
            }
        } label: {
            VStack(spacing: Space.xs) {
                MiniGrid(size: preset.boardSize)
                    .frame(width: 44, height: 44)
                VStack(spacing: 1) {
                    Text(preset.displayName).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(locked ? "Locked" : "\(preset.boardSize) × \(preset.boardSize)").font(.caption).foregroundStyle(theme.inkSecondary)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity)
            .surface(Radius.small)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(theme.accent, lineWidth: selected ? 2 : 0)
            }
            .opacity(locked ? 0.55 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(preset.displayName), \(preset.blurb)\(locked ? ", locked" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func ruleRow(_ title: String, detail: String, isOn: Binding<Bool>, locked: Bool) -> some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.footnote).foregroundStyle(theme.inkSecondary)
            }
            Spacer(minLength: Space.xs)
            if locked {
                Button {
                    router.openShipyard(focus: .admiral)
                } label: {
                    Label("Unlock", systemImage: "lock.fill")
                }
                .buttonStyle(.fleet(.secondary, compact: true))
            } else {
                Toggle(title, isOn: isOn).labelsHidden().tint(theme.accent)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }
}

/// A tiny board preview.
struct MiniGrid: View {
    let size: Int
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let rect = CGRect(x: (canvasSize.width - side) / 2, y: (canvasSize.height - side) / 2, width: side, height: side)
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(theme.waterShallow))
            let cell = side / CGFloat(size)
            var lines = Path()
            for i in 1..<size {
                lines.move(to: CGPoint(x: rect.minX + CGFloat(i) * cell, y: rect.minY)); lines.addLine(to: CGPoint(x: rect.minX + CGFloat(i) * cell, y: rect.maxY))
                lines.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(i) * cell)); lines.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(i) * cell))
            }
            context.stroke(lines, with: .color(theme.gridLine.opacity(1.6)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
