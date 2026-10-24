import FoldKit
import GameKit
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.foldState) private var fold
    @Environment(\.scenePhase) private var scenePhase

    private var theme: Theme {
        store.allows(settings.themeID) ? .with(id: settings.themeID) : .nightWatch
    }

    private var skin: ShipSkin {
        store.allows(settings.skinID) ? .with(id: settings.skinID) : .steel
    }

    private var boardStyle: BoardStyle {
        settings.boardStylePreference.resolve(spansFold: fold.posture.spansFold)
    }

    private var blast: BlastStyle {
        store.allows(settings.blastStyle) ? settings.blastStyle : .fireball
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            HomeView()
        }
        .fullScreenCover(item: $router.activeGame) { game in
            GameContainer(game: game)
                .environment(\.boardStyle, boardStyle)
                .environment(\.theme, theme)
                .environment(\.shipSkin, skin)
                .environment(\.blastStyle, blast)
                .themed(theme)
        }
        .sheet(isPresented: $router.showsShipyard) {
            NavigationStack { ShipyardView(focus: router.shipyardFocus) }
                .environment(\.theme, theme)
                .themed(theme)
        }
        .environment(\.theme, theme)
        .environment(\.shipSkin, skin)
        .environment(\.blastStyle, blast)
        .environment(\.boardStyle, boardStyle)
        .themed(theme)
        .sheet(isPresented: Binding(get: { gameCenter.pendingInvite != nil }, set: { if !$0 { gameCenter.pendingInvite = nil } })) {
            if let invite = gameCenter.pendingInvite {
                LiveMatchmakerSheet(source: .invite(invite)) { match in
                    gameCenter.pendingInvite = nil
                    gameCenter.liveMatchToOpen = match
                } onCancel: {
                    gameCenter.pendingInvite = nil
                }
                .ignoresSafeArea()
            }
        }
        .task {
            Analytics.shared.posture = fold.posture.rawValue
            Analytics.shared.capture("app_opened", ["theme": .string(settings.themeID.rawValue)])
        }
        .onChange(of: fold.posture) { old, new in
            Analytics.shared.posture = new.rawValue
            Analytics.shared.capture("posture_changed", ["from": .string(old.rawValue), "to": .string(new.rawValue), "in_game": .bool(router.activeGame != nil)])
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Analytics.shared.flush() }
        }
        #if DEBUG
        .task { await DemoDirector.run(router: router, settings: settings, store: store, context: modelContext) }
        #endif
        .onChange(of: gameCenter.matchToOpen) { _, match in
            guard let match else { return }
            gameCenter.matchToOpen = nil
            openOnline(match)
        }
        .onChange(of: gameCenter.liveMatchToOpen) { _, match in
            guard let match else { return }
            gameCenter.liveMatchToOpen = nil
            openLive(match)
        }
    }

    private func openOnline(_ match: GKTurnBasedMatch) {
        if case .online(let current)? = router.activeGame, current.matchID == match.matchID { return }
        let transport = TurnBasedTransport(match: match, gameCenter: gameCenter)
        launch(OnlineGame(transport: transport, rules: settings.lastRules, myName: gameCenter.playerName ?? settings.playerName, store: SecretStore(context: modelContext)))
    }

    private func openLive(_ match: GKMatch) {
        let transport = LiveTransport(match: match, rules: settings.lastRules)
        launch(OnlineGame(transport: transport, rules: settings.lastRules, myName: gameCenter.playerName ?? settings.playerName, store: SecretStore(context: modelContext)))
    }

    private func launch(_ game: OnlineGame) {
        game.onComplete = { summary in Persistence.record(summary, in: modelContext) }
        router.activeGame = .online(game)
    }
}

/// Presents whichever game is active.
struct GameContainer: View {
    let game: ActiveGame

    var body: some View {
        switch game {
        case .local(let game): LocalGameView(game: game)
        case .online(let game): OnlineGameView(game: game)
        }
    }
}
