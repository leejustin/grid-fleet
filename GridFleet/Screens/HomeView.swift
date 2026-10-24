import FoldKit
import GridFleetCore
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(AppRouter.self) private var router
    @Environment(\.foldState) private var fold
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var newGameMode: GameMode?
    @State private var showsRoom = false
    @State private var showsHowToPlay = false
    @State private var saved: LocalGame.Snapshot?
    @State private var savedNearby: SavedNearbyGame?
    @Query private var records: [GameRecord]

    var body: some View {
        ZStack {
            OceanBackdrop()
            if fold.splitsWindow {
                FoldSplit(gutter: Space.xl) {
                    hero
                } second: {
                    ScrollView { menu.padding(.horizontal, Space.l).padding(.vertical, Space.m) }
                        .scrollIndicators(.hidden)
                }
            } else {
                GeometryReader { proxy in
                    let wide = proxy.size.width >= 820
                    ScrollView {
                        VStack(spacing: Space.xxl) {
                            hero.fixedSize(horizontal: false, vertical: true).padding(.top, wide ? Space.xxl : Space.l)
                            if wide { wideMenu } else { menu }
                        }
                        .padding(.horizontal, wide ? Space.xxl : Space.l)
                        .padding(.bottom, Space.xxl)
                        .frame(maxWidth: wide ? 1040 : 560)
                        .frame(maxWidth: .infinity)
                        // On a big screen, sit in the middle rather than leaving the bottom half empty.
                        .frame(minHeight: wide ? proxy.size.height * 0.9 : 0)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { gameCenterButton }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showsRoom) { RoomCodeView() }
        #if DEBUG
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "logbook")) { LogbookView() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "online")) { OnlineLobbyView() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "room")) { RoomCodeView() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "rivals")) { RivalGallery() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "nearbyLobby")) { NearbyLobbyView() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "settings")) { SettingsView() }
        .navigationDestination(isPresented: .constant(DemoDirector.scene == "soundlab")) { SoundLabView() }
        .onChange(of: router.demoNewGame) { _, show in if show { newGameMode = .computer } }
        #endif
        .sheet(item: $newGameMode) { mode in NewGameView(mode: mode) }
        .sheet(isPresented: $showsHowToPlay) { NavigationStack { HowToPlayView() } }
        .onChange(of: router.pendingRoomCode) { _, code in
            if code != nil { showsRoom = true }
        }
        .onChange(of: router.activeGame == nil, initial: true) { _, idle in
            if idle {
                withAnimation {
                    saved = SavedBattle.load()
                    savedNearby = SavedNearbyGame.load().flatMap { nearby in
                        // Only offer a rejoin if this phone still has its sealed fleet for that game.
                        SecretStore(context: modelContext).secret(for: nearby.matchID) == nil ? nil : nearby
                    }
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Space.m) {
            RadarEmblem()
                .frame(width: 112, height: 112)
            VStack(spacing: Space.xs) {
                Text("Grid Fleet")
                    .font(.wordmark(38))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("Sea battle, made for the fold")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Menu

    private var nextRival: Rival { Rival.for(settings.lastDifficulty) }

    private var menu: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            playSections
            practiceSections
        }
    }

    /// Two columns of menu under the hero, when the screen is wide enough (iPad).
    private var wideMenu: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.xl) { playSections }
                .frame(maxWidth: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: Space.xl) { practiceSections }
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var playSections: some View {
        if Analytics.shared.isConfigured, !Analytics.shared.hasAnswered, !records.isEmpty {
            AnalyticsPrompt()
        }

        if !settings.hasSeenTutorial {
            ContentSection("New captain") {
                Button(action: startGuidedGame) {
                    FeatureCard(rival: .pip, systemImage: "chevron.right", title: "Your first battle", detail: "Learn with Ensign Pip")
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("first-battle")
                .contextMenu {
                    Button("I know how to play", systemImage: "checkmark") {
                        Analytics.shared.capture("coach_skipped", ["step": "home"])
                        withAnimation { settings.hasSeenTutorial = true }
                    }
                }
            }
        }

        ContentSection("Play a friend") {
            VStack(spacing: Space.s) {
                if let savedNearby {
                    Button { rejoin(savedNearby) } label: {
                        FeatureCard(rival: nil, systemImage: "arrow.clockwise", title: "Rejoin \(savedNearby.partnerName)", detail: "Your game across the table", leadingSymbol: "person.2.fill")
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button("Forget this game", systemImage: "trash", role: .destructive) {
                            SavedNearbyGame.clear()
                            self.savedNearby = nil
                        }
                    }
                }
                NavigationLink { NearbyLobbyView() } label: {
                    FeatureCard(rival: nil, systemImage: "arrow.right", title: "Across the table", detail: "Two phones, face to face", leadingSymbol: "person.2.fill")
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("across-the-table")
                VStack(spacing: 0) {
                    NavigationLink { OnlineLobbyView() } label: {
                        ListRow(systemImage: "globe", title: "Online", detail: "Friends anywhere, through Game Center") {
                            HStack(spacing: Space.xs) {
                                if gameCenter.matchesAwaitingMe > 0 { CountBadge(count: gameCenter.matchesAwaitingMe) }
                                DisclosureChevron()
                            }
                        }
                    }
                    RowDivider()
                    Button {
                        Haptics.tap()
                        showsRoom = true
                    } label: {
                        ListRow(systemImage: "number", title: "Room code", detail: "Play anyone with a six-letter code")
                    }
                    RowDivider()
                    Button {
                        Haptics.tap()
                        newGameMode = .passAndPlay
                    } label: {
                        ListRow(systemImage: "arrow.left.arrow.right", title: "Pass and play", detail: "One phone, handed back and forth")
                    }
                    .accessibilityIdentifier("pass-and-play")
                }
                .buttonStyle(PressableStyle())
                .surface()
            }
        }

    }

    @ViewBuilder
    private var practiceSections: some View {
        ContentSection("Practice") {
            VStack(spacing: Space.s) {
                if let saved {
                    Button { resume(saved) } label: {
                        FeatureCard(
                            rival: saved.difficulty.map(Rival.for),
                            systemImage: "play.fill",
                            title: "Resume battle",
                            detail: "Turn \(saved.battle.log.count / 2 + 1) vs \(saved.difficulty.map { Rival.for($0).name } ?? saved.names[1])",
                            prominent: false
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button("Abandon battle", systemImage: "trash", role: .destructive) {
                            SavedBattle.clear()
                            self.saved = nil
                        }
                    }
                }
                Button {
                    Haptics.tap()
                    newGameMode = .computer
                } label: {
                    FeatureCard(rival: nextRival, systemImage: "chevron.right", title: "Play the computer", detail: "vs \(nextRival.fullName)", prominent: false)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("play-computer")
            }
        }

        ContentSection("Harbor") {
            VStack(spacing: 0) {
                NavigationLink { LogbookView() } label: {
                    ListRow(systemImage: "book.closed", title: "Logbook", detail: "Record, medals and history")
                }
                RowDivider()
                Button { router.openShipyard() } label: {
                    ListRow(systemImage: "paintpalette", title: "Shipyard", detail: "Opponents, modes and looks")
                }
                RowDivider()
                Button { showsHowToPlay = true } label: {
                    ListRow(systemImage: "questionmark.circle", title: "How to play")
                }
            }
            .buttonStyle(PressableStyle())
            .surface()
        }
    }

    private var gameCenterButton: some View {
        Button {
            if gameCenter.isAuthenticated { gameCenter.showDashboard() } else { gameCenter.authenticate() }
        } label: {
            Label(gameCenter.playerName ?? "Sign in", systemImage: gameCenter.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
        }
        .accessibilityLabel(gameCenter.isAuthenticated ? "Game Center, signed in as \(gameCenter.playerName ?? "")" : "Sign in to Game Center")
    }

    private func startGuidedGame() {
        Haptics.tap()
        router.activeGame = .local(Self.guidedGame(settings: settings, context: modelContext))
    }

    /// A first game against Ensign Pip, with tips along the way.
    static func guidedGame(settings: AppSettings, context: ModelContext) -> LocalGame {
        let game = LocalGame(rules: .classic, opponent: .computer(.easy), names: [settings.playerName, Rival.pip.fullName])
        let coach = Coach()
        coach.onFinish = { settings.hasSeenTutorial = true }
        game.coach = coach
        game.onComplete = { summary in
            settings.hasSeenTutorial = true
            Persistence.record(summary, in: context)
        }
        return game
    }

    private func rejoin(_ saved: SavedNearbyGame) {
        Haptics.tap()
        Analytics.shared.capture("nearby_rejoin", ["age_minutes": .int(Int(Date.now.timeIntervalSince(saved.savedAt) / 60))])
        router.activeGame = .online(NearbyLobbyView.rejoin(saved, myName: settings.playerName, captainID: settings.captainID, context: modelContext))
    }

    private func resume(_ saved: LocalGame.Snapshot) {
        Haptics.tap()
        Analytics.shared.capture("game_resumed", ["age_minutes": .int(Int(Date.now.timeIntervalSince(saved.savedAt) / 60))])
        let game = LocalGame(resuming: saved)
        let context = modelContext
        game.onComplete = { summary in Persistence.record(summary, in: context) }
        router.activeGame = .local(game)
    }
}

extension GameMode: Identifiable {
    var id: String { rawValue }
}

/// The main call to action: a face, a title, and a play button.
struct FeatureCard: View {
    let rival: Rival?
    let systemImage: String
    let title: String
    let detail: String
    var prominent = true
    var leadingSymbol = "person.2.fill"
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: Space.m) {
            if let rival {
                RivalFlag(rival: rival, mood: .smug)
                    .frame(width: 52, height: 52)
            } else {
                Image(systemName: leadingSymbol)
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(theme.accent.opacity(0.14)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(theme.inkSecondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            Spacer(minLength: Space.xs)
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(prominent ? theme.onAccent : theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(prominent ? theme.accent : theme.ink.opacity(0.1)))
        }
        .foregroundStyle(theme.ink)
        .padding(Space.m)
        .surface()
        .contentShape(Rectangle())
    }
}

struct CountBadge: View {
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(theme.hit))
            .accessibilityLabel("\(count) waiting on you")
    }
}

/// An animated radar scope for the title screen.
struct RadarEmblem: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let blips: [(angle: Double, radius: Double)] = [(0.6, 0.55), (2.4, 0.78), (4.1, 0.35), (5.3, 0.66)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !MotionBudget.shared.allowsAmbient(reduceMotion: reduceMotion))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let r = min(size.width, size.height) / 2 - 1
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.fill(disc, with: .radialGradient(Gradient(colors: [theme.waterShallow, theme.waterDeep]), center: center, startRadius: 0, endRadius: r))
                for i in 1...3 {
                    let rr = r * Double(i) / 3
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)), with: .color(theme.accent.opacity(0.14)), lineWidth: 1)
                }
                var cross = Path()
                cross.move(to: CGPoint(x: center.x - r, y: center.y)); cross.addLine(to: CGPoint(x: center.x + r, y: center.y))
                cross.move(to: CGPoint(x: center.x, y: center.y - r)); cross.addLine(to: CGPoint(x: center.x, y: center.y + r))
                context.stroke(cross, with: .color(theme.accent.opacity(0.14)), lineWidth: 1)
                let sweep = (t * 1.1).truncatingRemainder(dividingBy: .pi * 2)
                var clipped = context
                clipped.clip(to: disc)
                clipped.fill(disc, with: .conicGradient(
                    Gradient(stops: [
                        .init(color: theme.accent.opacity(0), location: 0),
                        .init(color: theme.accent.opacity(0), location: 0.75),
                        .init(color: theme.accent.opacity(0.35), location: 0.998),
                        .init(color: theme.accent.opacity(0), location: 1),
                    ]),
                    center: center,
                    angle: .radians(sweep)
                ))
                for blip in blips {
                    var since = sweep - blip.angle
                    if since < 0 { since += .pi * 2 }
                    let glow = max(0, 1 - since / 2.4)
                    let p = CGPoint(x: center.x + cos(blip.angle) * r * blip.radius, y: center.y + sin(blip.angle) * r * blip.radius)
                    let size = 2.5 + 1.5 * glow
                    context.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)), with: .color(theme.hit.opacity(0.2 + 0.8 * glow)))
                }
                context.stroke(disc, with: .color(theme.accent.opacity(0.45)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}
