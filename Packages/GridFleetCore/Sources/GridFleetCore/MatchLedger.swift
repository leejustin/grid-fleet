import Foundation

public enum LedgerError: Error, Equatable, Sendable {
    case notYourTurn
    case notDeployed
    case alreadyDeployed
    case unresolvedIncoming
    case wrongPhase
    case commitmentMismatch
    case volley(VolleyError)
}

/// Shared state for a game between two devices that each know only their own fleet.
///
/// Each fleet is published as a salted hash. Shots go into the ledger unresolved. The defender's
/// device resolves them the next time it acts, so every result comes from the one device that knows
/// the fleet. When the game ends both fleets are revealed and either side can audit the other.
///
/// Turn order: seat 0 fires first. Whoever acts next resolves the shots fired at them, then fires.
public struct MatchLedger: Hashable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case battle
        /// The loser has revealed; waiting for the winner to reveal.
        case reveal
        case complete
    }

    public struct Seat: Hashable, Codable, Sendable {
        public var playerID: String?
        public var displayName: String?
        public var commitment: FleetCommitment?
        public var reveal: FleetSecret?
        public var arsenal: Arsenal
    }

    public struct Volley: Hashable, Codable, Sendable {
        public var seat: Int
        public var strikes: [Strike]
        /// Filled in by the defender. Nil while the shot is still in the air.
        public var reports: [StrikeReport]?
        public var firedAt: Date
    }

    public var version = 1
    public var rules: GameRules
    public var seats: [Seat]
    public var volleys: [Volley] = []
    public var phase: Phase = .battle
    public var winner: Int?
    public var resignedSeat: Int?
    public var updatedAt: Date

    public init(rules: GameRules, now: Date = .now) {
        self.rules = rules
        self.seats = [
            Seat(arsenal: rules.startingArsenal),
            Seat(arsenal: rules.startingArsenal),
        ]
        self.updatedAt = now
    }

    // MARK: Reading

    public static func opponent(of seat: Int) -> Int { 1 - seat }

    /// The seat that must act next, or nil when the game is complete.
    public var actingSeat: Int? {
        switch phase {
        case .complete: return nil
        case .reveal: return winner
        case .battle:
            guard let last = volleys.last else { return 0 }
            return Self.opponent(of: last.seat)
        }
    }

    public func isDeployed(_ seat: Int) -> Bool { seats[seat].commitment != nil }

    /// What `seat` knows about the opponent's fleet.
    public func target(for seat: Int) -> TargetBoard {
        var board = TargetBoard(rules: rules)
        for volley in volleys where volley.seat == seat {
            for report in volley.reports ?? [] { board.record(report) }
        }
        return board
    }

    /// Shots `seat` fired that the opponent hasn't answered yet.
    public func strikesInFlight(from seat: Int) -> [Strike] {
        volleys.filter { $0.seat == seat && $0.reports == nil }.flatMap(\.strikes)
    }

    public func unresolvedIncoming(for seat: Int) -> [Volley] {
        volleys.filter { $0.seat == Self.opponent(of: seat) && $0.reports == nil }
    }

    /// Reports given by the defender in `seat`, in order. These are what an audit replays.
    public func reportsGiven(by seat: Int) -> [StrikeReport] {
        volleys.filter { $0.seat == Self.opponent(of: seat) }.flatMap { $0.reports ?? [] }
    }

    /// The seat's own ocean, rebuilt from its secret fleet and every answered shot.
    public func ocean(for seat: Int, secret: FleetSecret) -> OceanGrid {
        var ocean = OceanGrid(rules: rules, fleet: secret.fleet)
        for volley in volleys where volley.seat == Self.opponent(of: seat) {
            guard volley.reports != nil else { continue }
            for strike in volley.strikes { _ = try? ocean.resolve(strike) }
        }
        return ocean
    }

    public func shotsAllowed(for seat: Int, secret: FleetSecret) -> Int {
        rules.shotsPerTurn(shipsAfloat: ocean(for: seat, secret: secret).shipsAfloat.count, untargetedCells: target(for: seat).untargeted.count)
    }

    public func audit(of seat: Int) -> AuditResult? {
        guard let reveal = seats[seat].reveal, let commitment = seats[seat].commitment else { return nil }
        return FleetAudit.audit(secret: reveal, commitment: commitment, rules: rules, reports: reportsGiven(by: seat))
    }

    // MARK: Acting

    /// Publishes the seat's sealed fleet.
    public mutating func deploy(seat: Int, secret: FleetSecret, playerID: String?, displayName: String?, now: Date = .now) throws {
        guard phase == .battle else { throw LedgerError.wrongPhase }
        guard seats[seat].commitment == nil else { throw LedgerError.alreadyDeployed }
        guard secret.fleet.isValid(for: rules) else { throw LedgerError.volley(.notDeployed) }
        seats[seat].commitment = secret.commitment
        seats[seat].playerID = playerID
        seats[seat].displayName = displayName
        updatedAt = now
    }

    /// Answers every shot fired at the seat. If that sinks the last ship, the seat reveals its fleet and loses.
    @discardableResult
    public mutating func resolveIncoming(seat: Int, secret: FleetSecret, now: Date = .now) throws -> [StrikeReport] {
        guard let commitment = seats[seat].commitment else { throw LedgerError.notDeployed }
        guard secret.commitment == commitment else { throw LedgerError.commitmentMismatch }
        guard phase == .battle else { return [] }
        var ocean = self.ocean(for: seat, secret: secret)
        var newReports: [StrikeReport] = []
        for index in volleys.indices where volleys[index].seat == Self.opponent(of: seat) && volleys[index].reports == nil {
            var reports: [StrikeReport] = []
            for strike in volleys[index].strikes {
                if let report = try? ocean.resolve(strike) { reports.append(report) }
            }
            volleys[index].reports = reports
            newReports += reports
        }
        if ocean.isDefeated {
            winner = Self.opponent(of: seat)
            seats[seat].reveal = secret
            phase = .reveal
        }
        if !newReports.isEmpty { updatedAt = now }
        return newReports
    }

    public mutating func fire(seat: Int, strikes: [Strike], secret: FleetSecret, now: Date = .now) throws {
        guard phase == .battle else { throw LedgerError.wrongPhase }
        guard actingSeat == seat else { throw LedgerError.notYourTurn }
        guard isDeployed(seat) else { throw LedgerError.notDeployed }
        guard unresolvedIncoming(for: seat).isEmpty else { throw LedgerError.unresolvedIncoming }
        do {
            try target(for: seat).validate(strikes, shotsAllowed: shotsAllowed(for: seat, secret: secret), arsenal: seats[seat].arsenal)
        } catch let error as VolleyError {
            throw LedgerError.volley(error)
        }
        for strike in strikes { seats[seat].arsenal.spend(strike.weapon) }
        volleys.append(Volley(seat: seat, strikes: strikes, reports: nil, firedAt: now))
        updatedAt = now
    }

    /// The winner reveals their fleet so the loser can audit it. Ends the game.
    public mutating func revealAsWinner(seat: Int, secret: FleetSecret, now: Date = .now) throws {
        guard phase == .reveal, winner == seat else { throw LedgerError.wrongPhase }
        seats[seat].reveal = secret
        phase = .complete
        updatedAt = now
    }

    /// Gives up. The seat reveals its fleet on the way out.
    public mutating func resign(seat: Int, secret: FleetSecret?, now: Date = .now) {
        guard phase != .complete else { return }
        resignedSeat = seat
        winner = Self.opponent(of: seat)
        if let secret { seats[seat].reveal = secret }
        phase = .complete
        updatedAt = now
    }

    // MARK: Wire format

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = try encoder.encode(self)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    public static func decode(_ data: Data) throws -> MatchLedger {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let json = try (data as NSData).decompressed(using: .zlib) as Data
        return try decoder.decode(MatchLedger.self, from: json)
    }
}
