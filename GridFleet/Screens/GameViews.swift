import FoldKit
import GridFleetCore
import SwiftData
import SwiftUI

/// Runs a game on this device through deployment, handoffs and battle.
struct LocalGameView: View {
    let game: LocalGame

    @Environment(AppRouter.self) private var router
    @Environment(\.foldState) private var fold
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch game.stage {
            case .deploying(let side):
                DeploymentView(
                    rules: game.rules,
                    subtitle: deploymentSubtitle(side),
                    title: game.isPassAndPlay ? "\(game.name(of: side))'s fleet" : "Deploy your fleet",
                    onReady: { game.deploy($0) },
                    onCancel: leave
                )
                .id(side)
                .transition(.opacity)
            case .handoff(let side, _):
                HandoffView(name: game.name(of: side), reason: .passTo, onReady: game.handoffAccepted)
                    .transition(.opacity)
            case .battle:
                if let session = game.session {
                    BattleView(session: session, actions: BattleActions(
                        onLeave: leave,
                        onRematch: { router.activeGame = .local(game.rematch()) },
                        onHide: game.isPassAndPlay ? {
                            Analytics.shared.capture("fleet_hidden", ["how": "button"])
                            game.isHidden = true
                        } : nil
                    ))
                    .id(ObjectIdentifier(session))
                    .transition(.opacity)
                }
            }
            if game.isHidden, game.stage == .battle {
                HandoffView(name: game.name(of: game.viewer), reason: .hidden) { game.isHidden = false }
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game.stage)
        .animation(.easeInOut(duration: 0.2), value: game.isHidden)
        .onChange(of: fold.posture) { _, posture in
            // Closing the phone hides the fleet at once.
            if game.isPassAndPlay, posture == .closed, !game.isHidden {
                Analytics.shared.capture("fleet_hidden", ["how": "fold_closed"])
                game.isHidden = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if game.isPassAndPlay, phase != .active { game.isHidden = true }
        }
    }

    private func deploymentSubtitle(_ side: Side) -> String {
        if game.isPassAndPlay { return "Only \(game.name(of: side)) should look." }
        if game.coach?.step == .deploy {
            return "Hide your five ships from \(game.name(of: .away)). Drag one to move it, tap it twice to turn it, or shuffle. Tap Ready when you're happy."
        }
        return "vs \(game.name(of: .away)). Drag to move, tap twice to rotate."
    }

    private func leave() {
        game.abandon()
        router.activeGame = nil
    }
}

/// Runs an online match.
struct OnlineGameView: View {
    let game: OnlineGame

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme

    @State private var showsArrival = false

    /// The nearby link, for games across the table.
    private var link: NearbyLink? { (game.transport as? NearbyTransport)?.link }

    var body: some View {
        ZStack {
            switch game.stage {
            case .loading:
                ZStack {
                    OceanBackdrop()
                    VStack(spacing: Space.l) {
                        RadarEmblem().frame(width: 96, height: 96)
                        Text(loadingText).font(.subheadline).foregroundStyle(theme.inkSecondary).multilineTextAlignment(.center)
                        Button("Cancel") { leave() }.buttonStyle(.fleet(.secondary, compact: true))
                    }
                    .padding(Space.xxl)
                }
            case .deploying:
                DeploymentView(rules: game.rules, subtitle: "vs \(game.opponentName). Drag to move, tap twice to rotate.", title: "Deploy your fleet", onReady: { game.deploy($0) }, onCancel: leave)
            case .battle:
                if let session = game.session {
                    BattleView(session: session, actions: BattleActions(
                        onLeave: leave,
                        onRematch: link.map { link in { link.requestRematch() } },
                        onHide: nil,
                        leaveLabel: "Back to harbor"
                    ))
                }
            case .failed(let message):
                ZStack {
                    OceanBackdrop()
                    VStack(spacing: Space.m) {
                        Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(theme.danger)
                        Text(message).font(.body).multilineTextAlignment(.center).foregroundStyle(theme.ink)
                        Button("Back to harbor") { leave() }.buttonStyle(.fleet(.secondary, compact: true))
                    }
                    .padding(Space.xxl)
                }
            }
            if showsArrival, let link {
                ArrivalOverlay(myName: settings.playerName, partnerName: game.opponentName, iFireFirst: link.localSeat == 0) {
                    showsArrival = false
                }
                .transition(.opacity)
                .zIndex(30)
            }
            if let link, let rematch = link.rematch {
                VStack {
                    RematchCard(rematch: rematch, partner: link.partner?.name ?? "Your friend", link: link)
                        .padding(.horizontal, Space.l)
                        .padding(.top, Space.s)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.stage)
        .animation(.smooth, value: link?.rematch)
        .animation(.easeInOut(duration: 0.3), value: showsArrival)
        .task { await game.start() }
        .onChange(of: game.stage) { old, new in
            #if DEBUG
            DemoDirector.note("[view] stage \(old) -> \(new)")
            #endif
            // A fresh game across the table: greet and flip for who fires first.
            if link != nil, old == .loading, new == .deploying {
                showsArrival = true
                Analytics.shared.capture("nearby_coin_flip", ["fires_first": .bool(link?.localSeat == 0)])
            }
        }
        .onAppear {
            link?.onRematchStarted = { [weak game] in
                guard let link = (game?.transport as? NearbyTransport)?.link else { return }
                Analytics.shared.capture("nearby_rematch")
                router.activeGame = .online(NearbyLobbyView.makeGame(link: link, myName: settings.playerName, context: modelContext))
            }
        }
    }

    private var loadingText: String {
        if let link, case .reconnecting(let partner) = link.state {
            return "Looking for \(partner.name)'s phone. Open Grid Fleet on it and keep the phones close."
        }
        return "Connecting…"
    }

    private func leave() {
        game.close()
        router.activeGame = nil
    }
}

/// Asking for, or answering, a rematch across the table.
private struct RematchCard: View {
    let rematch: NearbyLink.Rematch
    let partner: String
    let link: NearbyLink
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            switch rematch {
            case .requested:
                ProgressView()
                Text("Asking \(partner) for a rematch…").font(.subheadline)
                Spacer(minLength: 0)
            case .offered(let rules):
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(partner) wants a rematch").font(.headline)
                    Text(rules.summary).font(.footnote).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: Space.xs)
                Button("Not now") { link.declineRematch() }
                    .buttonStyle(.fleet(.secondary, compact: true))
                Button("Play") { link.acceptRematch() }
                    .buttonStyle(.fleet(.primary, compact: true))
            case .declined:
                Text("\(partner) said not now.").font(.subheadline)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(theme.ink)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(theme.backdropBottom.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.accent.opacity(0.6), lineWidth: 1))
    }
}
