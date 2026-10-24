#if DEBUG
import Foundation
import GridFleetCore
import SwiftData

/// Debug-only: jumps straight to a screen for screenshots and visual checks.
///
/// Launch with `-GFDemo <scene>`, where scene is one of `deploy`, `battle`, `salvo`, `specials`, `result`,
/// `handoff` or `logbook`. Combine with `-FoldKit.simulatedPosture halfFolded` and `-theme abyss` (any
/// UserDefaults key) to set the stage. `-GFDemoTurns 14` sets how far a battle is played in.
@MainActor
enum DemoDirector {
    static var scene: String? { UserDefaults.standard.string(forKey: "GFDemo") }

    /// Progress notes for automated runs, written to Library/Caches/demo.log in the app's container.
    static func note(_ message: String) {
        let url = URL.cachesDirectory.appending(path: "demo.log")
        let line = Data("\(Date.now.formatted(.iso8601)) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    static func run(router: AppRouter, settings: AppSettings, store: StoreService, context: ModelContext) async {
        guard let scene else { return }
        store.unlockAllForTesting = true
        settings.hasSeenTutorial = true
        let turns = UserDefaults.standard.object(forKey: "GFDemoTurns") as? Int ?? 14
        switch scene {
        case "deploy":
            router.activeGame = .local(LocalGame(rules: .classic, opponent: .computer(.hard), names: [settings.playerName, "Admiral"]))
        case "intro":
            let game = LocalGame(rules: .classic, opponent: .computer(.hard), names: [settings.playerName, Rival.thorn.fullName])
            game.deploy(Fleet.random(for: .classic))
            router.activeGame = .local(game)
        case "battle":
            await battle(GameRules.classic, turns: turns, router: router, settings: settings)
        case "salvo":
            await battle(GameRules(preset: .classic, firing: .salvo), turns: turns, router: router, settings: settings)
        case "specials":
            await battle(GameRules(preset: .classic, specialWeapons: true), turns: turns, router: router, settings: settings)
        case "result":
            let game = LocalGame(rules: .classic, opponent: .computer(.hard), names: [settings.playerName, Rival.thorn.fullName])
            game.deploy(Fleet.random(for: .classic, style: .scattered))
            router.activeGame = .local(game)
            try? await Task.sleep(for: .seconds(1))
            game.session?.showsIntro = false
            if let last = game.debugFastForward(enemyCellsLeft: 1) {
                game.session?.status = .yourTurn
                game.session?.onFire?([.shell(last)])
            }
        case "handoff":
            let game = LocalGame(rules: .classic, opponent: .human, names: ["Ava", "Theo"])
            game.deploy(Fleet.random(for: .classic))
            router.activeGame = .local(game)
        case "nearbyRejoin":
            guard let saved = SavedNearbyGame.load() else {
                note("[nearby] nothing to rejoin")
                return
            }
            note("[nearby] rejoining \(saved.partnerName)")
            let game = NearbyLobbyView.rejoin(saved, myName: settings.playerName, captainID: settings.captainID, context: context)
            router.activeGame = .online(game)
            await autoplay(game)
        case "nearbyHost", "nearbyGuest":
            await nearby(host: scene == "nearbyHost", router: router, settings: settings, context: context)
        case "logbook":
            seedLogbook(context)
        case "coachDeploy":
            router.activeGame = .local(HomeView.guidedGame(settings: settings, context: context))
        case "coach":
            let game = HomeView.guidedGame(settings: settings, context: context)
            game.deploy(Fleet.random(for: .classic))
            router.activeGame = .local(game)
            try? await Task.sleep(for: .seconds(UserDefaults.standard.object(forKey: "GFDemoTurns") == nil ? 0.5 : 4))
            game.session?.showsIntro = false
            // -GFDemoTurns 1 plays the first shot, to see the later tips.
            if UserDefaults.standard.integer(forKey: "GFDemoTurns") > 0, let session = game.session {
                session.tapTarget(Coordinate(row: 4, column: 4), oneTapFire: true)
            }
        case "home":
            settings.hasSeenTutorial = UserDefaults.standard.flag("GFDemoSeen", default: true)
        case "newgame":
            router.demoNewGame = true
        case "shipyard":
            router.openShipyard(focus: nil)
        default:
            break
        }
    }

    private static func battle(_ rules: GameRules, turns: Int, router: AppRouter, settings: AppSettings) async {
        let difficulty = AIDifficulty(rawValue: UserDefaults.standard.string(forKey: "GFDemoRival") ?? "") ?? .hard
        let game = LocalGame(rules: rules, opponent: .computer(difficulty), names: [settings.playerName, Rival.for(difficulty).fullName])
        game.deploy(Fleet.random(for: rules, style: .scattered))
        router.activeGame = .local(game)
        game.session?.showsIntro = false
        var rng = SystemRandomNumberGenerator()
        let gunner = AIAdmiral(difficulty: .hard)
        for _ in 0..<turns {
            guard let session = game.session, session.outcome == nil else { return }
            // Wait for our turn.
            while session.status != .yourTurn {
                if session.outcome != nil { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
            let volley = gunner.chooseVolley(target: session.target, shotsAllowed: session.shotsAllowed, arsenal: Arsenal(stock: [:]), using: &rng)
            session.onFire?(volley)
            try? await Task.sleep(for: .milliseconds(200))
        }
        // Leave an aim on the board, like a player mid-decision.
        if !UserDefaults.standard.bool(forKey: "GFDemoNoAim"), let session = game.session, session.status == .yourTurn || session.status == .opponentAiming {
            while session.status != .yourTurn, session.outcome == nil { try? await Task.sleep(for: .milliseconds(150)) }
            let aim = gunner.chooseVolley(target: session.target, shotsAllowed: session.shotsAllowed, arsenal: Arsenal(stock: [:]), using: &rng)
            for case .shell(let cell) in aim { session.tapTarget(cell, oneTapFire: false) }
        }
    }

    /// Two simulators play each other across the "table": find, invite, accept, deploy, and fire until someone wins.
    private static func nearby(host: Bool, router: AppRouter, settings: AppSettings, context: ModelContext) async {
        try? FileManager.default.removeItem(at: URL.cachesDirectory.appending(path: "demo.log"))
        let link = NearbyLink(name: settings.playerName, captainID: settings.captainID)
        link.start()
        note("[nearby] \(settings.playerName) looking as \(host ? "host" : "guest")")
        if host {
            while link.nearby.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            note("[nearby] found \(link.nearby.map(\.name)); inviting")
            let preset = UserDefaults.standard.string(forKey: "GFDemoPreset").flatMap(BoardPreset.init(rawValue:)) ?? settings.lastRules.preset
            link.invite(link.nearby[0], rules: GameRules(preset: preset))
        } else {
            while true {
                if case .invited = link.state { break }
                try? await Task.sleep(for: .milliseconds(300))
            }
            note("[nearby] invited; accepting")
            link.accept()
        }
        while true {
            if case .connected = link.state { break }
            if case .failed(let message) = link.state { note("[nearby] failed: \(message)"); return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        note("[nearby] connected to \(link.partner?.name ?? "?")")
        let game = NearbyLobbyView.makeGame(link: link, myName: settings.playerName, context: context)
        router.activeGame = .online(game)
        await autoplay(game)

        // Optionally play again over the same connection.
        guard UserDefaults.standard.bool(forKey: "GFDemoRematch") else { return }
        try? await Task.sleep(for: .seconds(2))
        if host {
            note("[nearby] asking for a rematch")
            link.requestRematch()
        } else {
            while true {
                if case .offered? = link.rematch { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            note("[nearby] accepting the rematch")
            link.acceptRematch()
        }
        while true {
            if case .online(let next)? = router.activeGame, next !== game {
                note("[nearby] rematch started")
                await autoplay(next)
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private static func autoplay(_ game: OnlineGame) async {
        var rng = SystemRandomNumberGenerator()
        let gunner = AIAdmiral(difficulty: .medium)
        let started = Date.now
        while Date.now.timeIntervalSince(started) < 900 {
            switch game.stage {
            case .loading:
                break
            case .deploying:
                try? await Task.sleep(for: .seconds(1))
                note("[nearby] deploying")
                game.deploy(Fleet.random(for: game.rules))
            case .failed(let message):
                note("[nearby] game failed: \(message)")
                return
            case .battle:
                guard let session = game.session else { break }
                if let outcome = session.outcome {
                    note("[nearby] finished: \(outcome.headline) in \(outcome.turns) turns, audit \(String(describing: outcome.audit))")
                    return
                }
                if session.status == .yourTurn {
                    note("[nearby] turn \(session.target.shotsFired + 1), \(session.ocean.shipsAfloat.count) ships afloat")
                    let volley = gunner.chooseVolley(target: session.target, shotsAllowed: session.shotsAllowed, arsenal: Arsenal(stock: [:]), using: &rng)
                    session.onFire?(volley)
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        note("[nearby] timed out")
    }

    private static func seedLogbook(_ context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<GameRecord>())) ?? 0) == 0 else { return }
        var rng = SeededGenerator(seed: 4)
        let opponents: [(GameMode, AIDifficulty?, String)] = [
            (.computer, .easy, "Ensign AI"), (.computer, .medium, "Commander AI"), (.computer, .hard, "Admiral AI"),
            (.online, nil, "Maya"), (.passAndPlay, nil, "Theo"), (.room, nil, "Sam"),
        ]
        for i in 0..<18 {
            let pick = opponents[Int.random(in: 0..<opponents.count, using: &rng)]
            let shots = Int.random(in: 38...80, using: &rng)
            let record = GameRecord()
            record.playedAt = Date.now.addingTimeInterval(-Double(i) * 86_400 * 0.7)
            record.modeRaw = pick.0.rawValue
            record.difficultyRaw = pick.1?.rawValue
            record.opponentName = pick.2
            record.won = Double.random(in: 0...1, using: &rng) < 0.62
            record.shotsFired = shots
            record.hits = record.won ? 17 : Int.random(in: 9...16, using: &rng)
            record.turns = shots
            record.shipsLost = record.won ? Int.random(in: 0...4, using: &rng) : 5
            record.durationSeconds = Double.random(in: 240...900, using: &rng)
            record.verified = pick.0 == .online ? true : nil
            context.insert(record)
            if record.won, let medal = Medal.allCases.randomElement(using: &rng) {
                context.insert(MedalAward(medal: medal, opponentName: pick.2))
            }
        }
        try? context.save()
    }
}
#endif
