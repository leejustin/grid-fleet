import GridFleetCore
import SwiftData
import SwiftUI

/// Play anyone with a six-character code. Rooms live in iCloud, so no Game Center account is needed.
struct RoomCodeView: View {
    enum Mode: Hashable { case host, join }

    @Environment(AppSettings.self) private var settings
    @Environment(StoreService.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme

    @State private var mode: Mode = .host
    @State private var rules = GameRules.classic
    @State private var code = ""
    @State private var hostedRoom: RoomTransport?
    @State private var working = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScreenScroll {
            Picker("Mode", selection: $mode) {
                Text("Host a room").tag(Mode.host)
                Text("Join a room").tag(Mode.join)
            }
            .pickerStyle(.segmented)
            if mode == .host { host } else { join }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(theme.danger)
            }
        }
        .oceanNavigation("Room code")
        .onAppear(perform: consumePendingCode)
        .onChange(of: router.pendingRoomCode) { consumePendingCode() }
        .onAppear { rules = store.allows(settings.lastRules) ? settings.lastRules : .classic }
    }

    private func consumePendingCode() {
        if let pending = router.pendingRoomCode {
            router.pendingRoomCode = nil
            mode = .join
            code = pending
        }
    }

    @ViewBuilder
    private var host: some View {
        if let room = hostedRoom {
            VStack(spacing: Space.l) {
                VStack(spacing: Space.xs) {
                    Text("Your room code").font(.subheadline).foregroundStyle(theme.inkSecondary)
                    CodeDisplay(code: room.code)
                }
                Text("Share it with your opponent. You fire first; they can join whenever they're ready.")
                    .font(.subheadline)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: Space.xs) {
                    ShareLink(item: room.shareURL, message: Text("Join my Grid Fleet battle. Room code \(room.code).")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.fleet(.secondary, compact: true))
                    Button {
                        UIPasteboard.general.string = room.code
                        Haptics.tap()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.fleet(.secondary, compact: true))
                }
                Button("Deploy fleet") { launch(room) }
                    .buttonStyle(.fleet)
            }
            .frame(maxWidth: .infinity)
            .padding(Space.l)
            .surface()
        } else {
            RulesPicker(rules: $rules)
            Button {
                openRoom()
            } label: {
                if working { ProgressView() } else { Text("Open a room") }
            }
            .buttonStyle(.fleet)
            .disabled(working)
        }
    }

    private var join: some View {
        VStack(spacing: Space.l) {
            Text("Enter the six-character code your opponent shared.")
                .font(.subheadline)
                .foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                CodeDisplay(code: code.padding(toLength: 6, withPad: " ", startingAt: 0), active: codeFocused)
                TextField("Code", text: $code)
                    .focused($codeFocused)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .onChange(of: code) { _, value in
                        let clean = String(RoomTransport.normalize(value).prefix(6))
                        if clean != value { code = clean }
                    }
                    .accessibilityLabel("Room code")
            }
            .onTapGesture { codeFocused = true }
            Button {
                joinRoom()
            } label: {
                if working { ProgressView() } else { Text("Join room") }
            }
            .buttonStyle(.fleet)
            .disabled(code.count != 6 || working)
        }
        .onAppear { codeFocused = code.isEmpty }
    }

    private func openRoom() {
        working = true
        error = nil
        settings.lastRules = rules
        Task {
            defer { working = false }
            do {
                hostedRoom = try await RoomTransport.create(rules: rules, hostName: settings.playerName, captainID: settings.captainID)
                Analytics.shared.capture("room_created", rules.analyticsProperties)
                Haptics.hit()
            } catch {
                Analytics.shared.capture("online_error", ["kind": "room_create"])
                self.error = error.localizedDescription
            }
        }
    }

    private func joinRoom() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let room = try await RoomTransport.join(code: code, guestName: settings.playerName, captainID: settings.captainID)
                Analytics.shared.capture("room_joined")
                launch(room)
            } catch {
                Analytics.shared.capture("online_error", ["kind": .string(error is RoomError ? "room_\(error)" : "room_join")])
                self.error = error.localizedDescription
            }
        }
    }

    private func launch(_ room: RoomTransport) {
        let game = OnlineGame(transport: room, rules: rules, myName: settings.playerName, store: SecretStore(context: modelContext))
        let context = modelContext
        game.onComplete = { summary in Persistence.record(summary, in: context) }
        router.activeGame = .online(game)
    }
}

/// Six letter tiles.
struct CodeDisplay: View {
    let code: String
    var active = false
    @Environment(\.theme) private var theme

    var body: some View {
        let characters = Array(code.prefix(6))
        let cursor = characters.firstIndex(of: " ")
        HStack(spacing: Space.xs) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.ink)
                    .frame(width: 44, height: 54)
                    .surface(Radius.small)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(theme.accent, lineWidth: active && index == cursor ? 2 : 0)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code \(code.trimmingCharacters(in: .whitespaces).map(String.init).joined(separator: " "))")
    }
}
