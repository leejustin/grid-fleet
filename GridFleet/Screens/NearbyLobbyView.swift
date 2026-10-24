import GridFleetCore
import SwiftData
import SwiftUI

/// Two phones at the same table: find your friend's phone and start a game. No account or internet needed.
struct NearbyLobbyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme

    @State private var link: NearbyLink?
    @State private var name = ""
    @State private var showsRules = false
    @State private var launched = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        ScreenScroll {
            VStack(spacing: Space.m) {
                TableIllustration()
                    .frame(height: 112)
                Text("Sit across from your friend and half-fold both phones like the board game, lids back to back in the middle so neither of you can see the other's screen. Then open this screen on both.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)

            if let link, link.state == .permissionDenied {
                permissionNotice
            }

            if let link, case .invited(let captain, let rules) = link.state {
                invitation(from: captain, rules: rules, link: link)
            }

            ContentSection("Your name", footer: "This is what your friend sees.") {
                TextField("Your name", text: $name)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 52)
                    .surface()
                    .onSubmit(applyName)
            }

            ContentSection("Nearby") {
                VStack(spacing: 0) {
                    if let link, !link.nearby.isEmpty {
                        ForEach(Array(link.nearby.enumerated()), id: \.element.id) { index, captain in
                            if index > 0 { RowDivider() }
                            Button { invite(captain) } label: {
                                ListRow(systemImage: "iphone", title: captain.name, detail: detail(for: captain, link: link)) {
                                    if case .inviting(let pending) = link.state, pending == captain {
                                        ProgressView()
                                    } else {
                                        Text("Invite").font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(isBusy)
                        }
                    } else {
                        HStack(spacing: Space.s) {
                            ProgressView()
                            Text("Looking for phones nearby…").font(.body).foregroundStyle(theme.inkSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 56)
                    }
                }
                .surface()
            }

            ContentSection("Rules", footer: "Used when you send the invite. If your friend invites you, their rules apply.") {
                Button { showsRules = true } label: {
                    ListRow(systemImage: "slider.horizontal.3", title: settings.lastRules.summary)
                }
                .buttonStyle(PressableStyle())
                .surface()
            }

            if let link, case .failed(let message) = link.state {
                Text(message).font(.footnote).foregroundStyle(theme.danger)
            }
        }
        .oceanNavigation("Across the table")
        .sheet(isPresented: $showsRules) {
            NavigationStack {
                ScreenScroll { RulesPicker(rules: $settings.lastRules) }
                    .navigationTitle("Rules")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsRules = false } } }
            }
            .presentationBackground(theme.backdropBottom)
        }
        .onAppear {
            name = settings.playerName == "Captain" ? "" : settings.playerName
            if !store.allows(settings.lastRules) { settings.lastRules = .classic }
            startLink()
            if settings.playerName == "Captain" { nameFocused = true }
        }
        .onDisappear {
            if !launched { link?.stop() }
        }
        .onChange(of: link?.state) { _, state in
            if case .connected? = state { launch() }
        }
    }

    private var isBusy: Bool {
        guard let link else { return true }
        switch link.state {
        case .inviting, .invited, .connected: return true
        default: return false
        }
    }

    private func detail(for captain: NearbyLink.Captain, link: NearbyLink) -> String {
        if case .inviting(let pending) = link.state, pending == captain { return "Waiting for them to accept" }
        return "Tap to invite"
    }

    private func invitation(from captain: NearbyLink.Captain, rules: GameRules, link: NearbyLink) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(captain.name) wants to play").font(.headline)
                Text(rules.summary).font(.subheadline).foregroundStyle(theme.inkSecondary)
            }
            HStack(spacing: Space.xs) {
                Button("Play") { link.accept() }
                    .buttonStyle(.fleet(.primary, compact: true))
                Button("Not now") { link.decline() }
                    .buttonStyle(.fleet(.secondary, compact: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .surface()
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.accent, lineWidth: 1.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Network is off").font(.headline)
                Text("Grid Fleet needs Local Network access to find your friend's phone. Turn it on in Settings, then come back.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.fleet(.primary, compact: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .surface()
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(theme.danger.opacity(0.6), lineWidth: 1))
    }

    private func applyName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != settings.playerName else { return }
        settings.playerName = trimmed
        // Peers see the name we advertise, so start over with the new one.
        link?.stop()
        startLink()
    }

    private func startLink() {
        let new = NearbyLink(name: settings.playerName, captainID: settings.captainID)
        new.start()
        link = new
    }

    private func invite(_ captain: NearbyLink.Captain) {
        applyName()
        Haptics.tap()
        Analytics.shared.capture("nearby_invite_sent", settings.lastRules.analyticsProperties)
        link?.invite(captain, rules: settings.lastRules)
    }

    private func launch() {
        guard let link, !launched else { return }
        launched = true
        Analytics.shared.capture("nearby_connected", ["inviter": .bool(link.isInviter)])
        router.activeGame = .online(NearbyLobbyView.makeGame(link: link, myName: settings.playerName, context: modelContext))
    }

    /// Picks an interrupted game back up: same game ID and partner, starting from what this phone last saw.
    static func rejoin(_ saved: SavedNearbyGame, myName: String, captainID: String, context: ModelContext) -> OnlineGame {
        let link = NearbyLink(name: myName, captainID: captainID)
        link.resume(gameID: saved.gameID, partnerID: saved.partnerID, partnerName: saved.partnerName, isInviter: saved.isInviter, seat: saved.seat ?? (saved.isInviter ? 0 : 1), rules: saved.rules)
        link.start()
        let ledger = SecretStore(context: context).lastSeen(for: saved.matchID)
        return makeGame(link: link, myName: myName, context: context, resumeFrom: ledger)
    }

    static func makeGame(link: NearbyLink, myName: String, context: ModelContext, resumeFrom ledger: MatchLedger? = nil) -> OnlineGame {
        SavedNearbyGame.save(from: link)
        let game = OnlineGame(transport: NearbyTransport(link: link, resumeFrom: ledger), rules: link.rules, myName: myName, store: SecretStore(context: context))
        game.onComplete = { summary in Persistence.record(summary, in: context) }
        return game
    }
}

/// Two half-folded phones facing each other across a table.
struct TableIllustration: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !MotionBudget.shared.allowsAmbient(reduceMotion: reduceMotion))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Like the board game: the two lids stand back to back in the middle, each screen facing
                // its own captain on the outside, so neither can see the other's fleet.
                let tableY = size.height * 0.84
                let mid = size.width / 2
                let gap: CGFloat = 26
                let trayLength: CGFloat = 50
                let lidLength: CGFloat = 52
                var table = Path()
                table.move(to: CGPoint(x: mid - 170, y: tableY))
                table.addLine(to: CGPoint(x: mid + 170, y: tableY))
                context.stroke(table, with: .color(theme.hairline), lineWidth: 2)
                for side in [-1.0, 1.0] {
                    let hinge = CGPoint(x: mid + side * gap, y: tableY - 3)
                    let tray = CGPoint(x: hinge.x + side * trayLength, y: tableY - 3)
                    // The lid leans back, away from its captain and toward the middle.
                    let lean = Angle.degrees(12)
                    let lid = CGPoint(x: hinge.x - side * lidLength * sin(lean.radians), y: hinge.y - lidLength * cos(lean.radians))
                    var phone = Path()
                    phone.move(to: tray)
                    phone.addLine(to: hinge)
                    phone.addLine(to: lid)
                    context.stroke(phone, with: .color(theme.ink.opacity(0.85)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    // Both screens glow toward their own captain: the lid's outer face and the tray's top.
                    var glow = Path()
                    glow.move(to: CGPoint(x: hinge.x + side * 3.5, y: hinge.y - 7))
                    glow.addLine(to: CGPoint(x: lid.x + side * 3.5, y: lid.y + 4))
                    glow.move(to: CGPoint(x: hinge.x + side * 7, y: hinge.y - 3.5))
                    glow.addLine(to: CGPoint(x: tray.x - side * 3, y: tray.y - 3.5))
                    context.stroke(glow, with: .color(theme.accent.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    // The captain, sitting on the outside.
                    let head = CGPoint(x: tray.x + side * 42, y: tableY - 46)
                    context.fill(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)), with: .color(theme.inkSecondary.opacity(0.7)))
                    var shoulders = Path()
                    shoulders.addArc(center: CGPoint(x: head.x, y: head.y + 34), radius: 20, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                    context.stroke(shoulders, with: .color(theme.inkSecondary.opacity(0.7)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                // A signal passing between the phones, over the lids.
                for i in 0..<3 {
                    let phase = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let r = CGFloat(6 + phase * 20)
                    let arc = Path { p in
                        p.addArc(center: CGPoint(x: mid, y: tableY - 66), radius: r, startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
                    }
                    context.stroke(arc, with: .color(theme.accent.opacity(0.5 * (1 - phase))), lineWidth: 1.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
