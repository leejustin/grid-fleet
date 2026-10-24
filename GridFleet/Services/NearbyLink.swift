import Foundation
import GridFleetCore
import Network
import Observation

/// Finds friends' phones in the same room and connects to one, with no internet or account.
///
/// Every phone on this screen advertises itself over Bonjour (peer-to-peer Wi-Fi included) and browses
/// for the others. One player taps the other's name; the inviter sets the rules and flips a coin for who
/// fires first. If the connection drops mid-game, the inviter keeps reaching out to the same captain and the
/// game resumes.
@MainActor
@Observable
final class NearbyLink {
    static let serviceType = "_gridfleet._tcp"

    struct Captain: Identifiable, Hashable {
        let id: String
        let name: String
        /// Nil until the captain shows up on the network (for example, rejoining after a relaunch).
        let endpoint: NWEndpoint?

        static func == (lhs: Captain, rhs: Captain) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Everything the two phones say to each other.
    private enum Message: Codable {
        case hello(id: String, name: String)
        /// `inviterSeat` is the coin flip: seat 0 fires first.
        case invite(gameID: String, rules: GameRules, inviterSeat: Int?)
        case accept(gameID: String)
        case decline
        case ledger(Data)
        case rematch(gameID: String, rules: GameRules, askerSeat: Int?)
        case rematchAccept(gameID: String)
        case rematchDecline
    }

    enum State: Equatable {
        case searching
        case inviting(Captain)
        case invited(by: Captain, rules: GameRules)
        case connected(Captain)
        /// Rejoining a game after a relaunch: waiting for the partner to show up.
        case reconnecting(Captain)
        /// The player turned off Local Network access for the app.
        case permissionDenied
        case failed(String)
    }

    enum Rematch: Equatable {
        case requested
        case offered(GameRules)
        case declined
    }

    private(set) var nearby: [Captain] = []
    private(set) var state: State = .searching
    /// The game in progress. Fixed for the life of the link so reconnections rejoin it.
    private(set) var gameID: String?
    private(set) var rules: GameRules = .classic
    private(set) var isInviter = false
    /// This phone's seat in the game. Seat 0 fires first.
    private(set) var localSeat = 0
    /// The captain we're playing, kept through disconnections.
    private(set) var partner: Captain?

    /// A rematch being negotiated after a game ends.
    private(set) var rematch: Rematch?

    var onData: ((Data) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    /// Called on both phones when a rematch is agreed. The link has a fresh game ID by then.
    var onRematchStarted: (() -> Void)?

    let captainID: String
    let name: String

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var connectionReady = false
    /// Who's on the other end of an incoming connection, once they've said hello.
    private var incomingCaptain: Captain?
    private var retryTask: Task<Void, Never>?
    private var pendingRematchID: String?
    private var pendingRematchSeat = 0
    private var offeredRematchID: String?
    private var offeredRematchSeat = 1

    init(name: String, captainID: String) {
        self.name = String(name.prefix(40))
        self.captainID = captainID
    }

    private static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }

    func start() {
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: captainID, type: Self.serviceType, domain: nil, txtRecord: NWTXTRecord(["id": captainID, "name": name]))
            listener.newConnectionHandler = { [weak self] connection in
                let box = UncheckedBox(value: connection)
                MainActor.assumeIsolated { self?.accepted(box.value) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                let box = UncheckedBox(value: state)
                MainActor.assumeIsolated { self?.networkStateChanged(listener: box.value) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed("Couldn't start looking for nearby phones.")
        }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: Self.parameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let box = UncheckedBox(value: results)
            MainActor.assumeIsolated { self?.updateNearby(box.value) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            let box = UncheckedBox(value: state)
            MainActor.assumeIsolated { self?.networkStateChanged(browser: box.value) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Picks up a game after the app was closed. Call before `start()`.
    func resume(gameID: String, partnerID: String, partnerName: String, isInviter: Bool, seat: Int, rules: GameRules) {
        self.gameID = gameID
        self.rules = rules
        self.isInviter = isInviter
        self.localSeat = seat
        let partner = Captain(id: partnerID, name: partnerName, endpoint: nil)
        self.partner = partner
        state = .reconnecting(partner)
        // The inviter reaches out; the other phone just listens and accepts the same game.
        if isInviter { scheduleRedial() }
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error, code == -65570 { return true } // kDNSServiceErr_PolicyDenied
        return false
    }

    private func networkStateChanged(browser: NWBrowser.State) {
        switch browser {
        case .waiting(let error), .failed(let error):
            if Self.isPolicyDenied(error) { state = .permissionDenied }
        case .ready:
            if state == .permissionDenied { state = .searching }
        default:
            break
        }
    }

    private func networkStateChanged(listener: NWListener.State) {
        switch listener {
        case .waiting(let error), .failed(let error):
            if Self.isPolicyDenied(error) { state = .permissionDenied }
        default:
            break
        }
    }

    // MARK: Rematch

    /// Asks the other phone for another game with the same rules, with a fresh coin flip for who fires first.
    func requestRematch() {
        let id = UUID().uuidString
        pendingRematchID = id
        pendingRematchSeat = Int.random(in: 0...1)
        rematch = .requested
        send(.rematch(gameID: id, rules: rules, askerSeat: pendingRematchSeat))
    }

    func acceptRematch() {
        guard case .offered = rematch, let id = offeredRematchID else { return }
        send(.rematchAccept(gameID: id))
        startRematch(gameID: id, asInviter: false, seat: offeredRematchSeat)
    }

    func declineRematch() {
        rematch = nil
        offeredRematchID = nil
        send(.rematchDecline)
    }

    private func startRematch(gameID id: String, asInviter: Bool, seat: Int) {
        gameID = id
        isInviter = asInviter
        localSeat = seat
        rematch = nil
        pendingRematchID = nil
        offeredRematchID = nil
        onRematchStarted?()
    }

    func stop() {
        retryTask?.cancel()
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        connectionReady = false
    }

    var isConnected: Bool {
        if case .connected = state { return connectionReady }
        return false
    }

    // MARK: Inviting

    func invite(_ captain: Captain, rules: GameRules) {
        gameID = UUID().uuidString
        self.rules = rules
        isInviter = true
        localSeat = Int.random(in: 0...1)
        partner = captain
        state = .inviting(captain)
        dial(captain)
        // Give up if they don't answer.
        let pending = gameID
        Task {
            try? await Task.sleep(for: .seconds(30))
            if case .inviting = self.state, self.gameID == pending {
                self.state = .failed("\(captain.name) didn't answer. Try again?")
                self.reset()
            }
        }
    }

    func cancelInvite() {
        reset()
        state = .searching
    }

    func accept() {
        guard case .invited(let captain, _) = state, let gameID else { return }
        send(.accept(gameID: gameID))
        connectionReady = true
        state = .connected(captain)
        onConnectionChanged?(true)
    }

    func decline() {
        send(.decline)
        reset()
        state = .searching
    }

    func send(_ data: Data) {
        send(.ledger(data))
    }

    private func reset() {
        connection?.cancel()
        connection = nil
        connectionReady = false
        gameID = nil
        partner = nil
        isInviter = false
        localSeat = 0
        incomingCaptain = nil
    }

    /// Opens a connection to a captain and asks them to play (or to resume our game).
    private func dial(_ captain: Captain) {
        connection?.cancel()
        guard let endpoint = captain.endpoint else { return }
        let connection = NWConnection(to: endpoint, using: Self.parameters())
        self.connection = connection
        connectionReady = false
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionStateChanged(state, for: connection) }
        }
        connection.start(queue: .main)
        receive(on: connection)
        send(.hello(id: captainID, name: name), on: connection)
        if let gameID { send(.invite(gameID: gameID, rules: rules, inviterSeat: localSeat), on: connection) }
    }

    // MARK: Events

    private func updateNearby(_ results: Set<NWBrowser.Result>) {
        var found: [Captain] = []
        for result in results {
            guard case .bonjour(let txt) = result.metadata, let id = txt["id"], id != captainID else { continue }
            found.append(Captain(id: id, name: txt["name"] ?? "Captain", endpoint: result.endpoint))
        }
        nearby = found.sorted { $0.name < $1.name }
        // Keep the partner's latest address for reconnecting.
        if let partner, let fresh = found.first(where: { $0.id == partner.id }) {
            self.partner = fresh
            if case .reconnecting = state { state = .reconnecting(fresh) }
        }
    }

    private func accepted(_ incoming: NWConnection) {
        // Only one game at a time; a reconnecting partner replaces the old connection.
        connection?.cancel()
        connection = incoming
        connectionReady = false
        incoming.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionStateChanged(state, for: incoming) }
        }
        incoming.start(queue: .main)
        receive(on: incoming)
    }

    private func connectionStateChanged(_ newState: NWConnection.State, for changed: NWConnection) {
        guard changed === connection else { return }
        switch newState {
        case .failed, .cancelled:
            let wasPlaying = connectionReady
            connectionReady = false
            if case .connected = state, wasPlaying {
                onConnectionChanged?(false)
                if isInviter { scheduleRedial() }
            } else if case .inviting(let captain) = state {
                state = .failed("Couldn't reach \(captain.name). Try again?")
                reset()
            }
        default:
            break
        }
    }

    private func scheduleRedial() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, !self.connectionReady, let partner = self.partner else { return }
                if partner.endpoint != nil { self.dial(partner) }
            }
        }
    }

    private func handle(_ message: Message, from source: NWConnection) {
        switch message {
        case .hello(let id, let name):
            let endpoint = nearby.first { $0.id == id }?.endpoint
            incomingCaptain = Captain(id: id, name: name, endpoint: endpoint)
        case .invite(let id, let invitedRules, let inviterSeat):
            guard let captain = incomingCaptain else { return }
            if let gameID, id == gameID, partner?.id == captain.id {
                // Our partner reconnecting to the same game.
                send(.accept(gameID: id), on: source)
                connectionReady = true
                state = .connected(captain)
                onConnectionChanged?(true)
            } else if gameID == nil {
                gameID = id
                rules = invitedRules
                isInviter = false
                localSeat = MatchLedger.opponent(of: inviterSeat ?? 0)
                partner = captain
                state = .invited(by: captain, rules: invitedRules)
            } else {
                send(.decline, on: source)
            }
        case .accept(let id):
            guard id == gameID, let partner else { return }
            retryTask?.cancel()
            connectionReady = true
            state = .connected(partner)
            onConnectionChanged?(true)
        case .decline:
            if case .inviting(let captain) = state {
                state = .failed("\(captain.name) said not now.")
            }
            reset()
        case .ledger(let data):
            onData?(data)
        case .rematch(let id, let offeredRules, let askerSeat):
            let seat = MatchLedger.opponent(of: askerSeat ?? 0)
            if rematch == .requested, let mine = pendingRematchID {
                // Both asked at once: the lower game ID wins, and both phones agree on which that is.
                if id < mine {
                    send(.rematchAccept(gameID: id))
                    rules = offeredRules
                    startRematch(gameID: id, asInviter: false, seat: seat)
                }
                return
            }
            offeredRematchID = id
            offeredRematchSeat = seat
            rules = offeredRules
            rematch = .offered(offeredRules)
        case .rematchAccept(let id):
            guard id == pendingRematchID else { return }
            startRematch(gameID: id, asInviter: true, seat: pendingRematchSeat)
        case .rematchDecline:
            pendingRematchID = nil
            rematch = .declined
        }
    }

    // MARK: Framing: a 4-byte length, then JSON.

    private func send(_ message: Message) {
        guard let connection else { return }
        send(message, on: connection)
    }

    private func send(_ message: Message, on connection: NWConnection) {
        guard let body = try? JSONEncoder().encode(message) else { return }
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        connection.send(content: frame, completion: .idempotent)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            let box = UncheckedBox(value: (header, isComplete, error))
            MainActor.assumeIsolated {
                guard let self else { return }
                let (header, isComplete, error) = box.value
                guard error == nil, let header, header.count == 4 else {
                    if isComplete || error != nil { connection.cancel() }
                    return
                }
                let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian)
                guard length > 0, length < 2_000_000 else {
                    connection.cancel()
                    return
                }
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
                    let bodyBox = UncheckedBox(value: (body, error))
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let (body, error) = bodyBox.value
                        guard error == nil, let body, let message = try? JSONDecoder().decode(Message.self, from: body) else {
                            connection.cancel()
                            return
                        }
                        self.handle(message, from: connection)
                        self.receive(on: connection)
                    }
                }
            }
        }
    }
}

/// A game across the table, carried over a nearby link.
@MainActor
final class NearbyTransport: LedgerTransport {
    let link: NearbyLink
    let mode: GameMode = .nearby
    let turnTimeLimit: TimeInterval? = nil
    let forfeitedSeat: Int? = nil
    var onRemoteUpdate: ((MatchLedger) -> Void)?
    var onOpponentLeft: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private var latest: MatchLedger?
    private var firstLedger: CheckedContinuation<MatchLedger?, Never>?
    private var heardFromOpponent = false
    private var handshakeTask: Task<Void, Never>?

    init(link: NearbyLink, resumeFrom ledger: MatchLedger? = nil) {
        self.link = link
        self.latest = ledger
        link.onData = { [weak self] data in self?.received(data) }
        link.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            if connected, let latest = self.latest {
                // Back together: send what we have so both sides catch up.
                self.link.send((try? latest.encoded()) ?? Data())
            }
            self.onConnectionChanged?(connected)
        }
    }

    var matchID: String { "nearby-\(link.gameID ?? "unknown")" }
    var localSeat: Int { link.localSeat }
    var localPlayerID: String? { link.captainID }
    var opponentName: String { link.partner?.name ?? "Your friend" }
    var opponentDetail: String { "Across the table" }
    var isLocalTurn: Bool { (latest?.actingSeat ?? 0) == localSeat }
    var isRealtime: Bool { true }

    func load() async throws -> MatchLedger? {
        // Rejoining: start from what this phone last saw. The partner's copy merges in on reconnect.
        if let latest { return latest }
        if localSeat == 0 {
            let ledger = MatchLedger(rules: link.rules)
            latest = ledger
            try await share(ledger)
            handshakeTask = Task { [weak self] in
                for _ in 0..<40 {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled, !self.heardFromOpponent, let latest = self.latest else { return }
                    try? await self.share(latest)
                }
            }
            return ledger
        }
        if let latest { return latest }
        return await withCheckedContinuation { continuation in
            firstLedger = continuation
        }
    }

    func share(_ ledger: MatchLedger) async throws {
        latest = ledger
        link.send(try ledger.encoded())
    }

    func endTurn(_ ledger: MatchLedger) async throws { try await share(ledger) }
    func endMatch(_ ledger: MatchLedger) async throws { try await share(ledger) }
    func resign(_ ledger: MatchLedger) async throws { try await share(ledger) }

    func close() {
        handshakeTask?.cancel()
        link.stop()
    }

    private func received(_ data: Data) {
        guard let ledger = try? MatchLedger.decode(data) else { return }
        heardFromOpponent = true
        latest = ledger
        if let pending = firstLedger {
            firstLedger = nil
            link.send(data)
            pending.resume(returning: ledger)
            return
        }
        onRemoteUpdate?(ledger)
    }
}

/// The across-the-table game in progress, kept so it can be rejoined after the app is closed.
struct SavedNearbyGame: Codable {
    var gameID: String
    var partnerID: String
    var partnerName: String
    var isInviter: Bool
    /// Missing in games saved before the coin flip, when the inviter always took seat 0.
    var seat: Int?
    var rules: GameRules
    var savedAt: Date

    private static let key = "savedNearbyGame"

    var matchID: String { "nearby-\(gameID)" }

    @MainActor
    static func save(from link: NearbyLink) {
        guard let gameID = link.gameID, let partner = link.partner else { return }
        let saved = SavedNearbyGame(gameID: gameID, partnerID: partner.id, partnerName: partner.name, isInviter: link.isInviter, seat: link.localSeat, rules: link.rules, savedAt: .now)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: key)
    }

    static func load() -> SavedNearbyGame? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedNearbyGame.self, from: $0) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
