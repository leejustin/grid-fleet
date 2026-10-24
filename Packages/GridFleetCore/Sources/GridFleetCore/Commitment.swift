import CryptoKit
import Foundation

/// A fleet plus the random salt that hides it. Kept on the owner's device until the game ends.
public struct FleetSecret: Hashable, Codable, Sendable {
    public var fleet: Fleet
    public var salt: Data

    public init(fleet: Fleet, salt: Data) {
        self.fleet = fleet
        self.salt = salt
    }

    public init(fleet: Fleet) {
        var rng = SystemRandomNumberGenerator()
        self.init(fleet: fleet, salt: Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }))
    }

    /// A stable text form of the fleet. Order-independent.
    public var canonicalFleet: String {
        fleet.ships
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.origin.row),\($0.origin.column),\($0.orientation == .horizontal ? "h" : "v")" }
            .joined(separator: ";")
    }

    public var commitment: FleetCommitment {
        var hasher = SHA256()
        hasher.update(data: Data("gridfleet.v1|".utf8))
        hasher.update(data: Data(canonicalFleet.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: salt)
        return FleetCommitment(digest: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

/// The published hash of a fleet. Reveals nothing until the secret is shown.
public struct FleetCommitment: Hashable, Codable, Sendable {
    public var digest: String

    public init(digest: String) {
        self.digest = digest
    }

    /// The first characters, for showing in the UI.
    public var short: String { String(digest.prefix(8)).uppercased() }
}

public enum AuditResult: Hashable, Codable, Sendable {
    /// The revealed fleet matches the hash, is legal, and every reported result was honest.
    case verified
    /// The revealed fleet doesn't match the hash committed at the start.
    case commitmentMismatch
    /// The revealed fleet breaks the rules.
    case illegalFleet
    /// A reported result doesn't match the revealed fleet.
    case falseReport(Strike)

    public var isClean: Bool { self == .verified }

    public var headline: String {
        switch self {
        case .verified: "Fleet verified"
        case .commitmentMismatch: "Fleet doesn't match its seal"
        case .illegalFleet: "Fleet broke the rules"
        case .falseReport: "A result was misreported"
        }
    }
}

public enum FleetAudit {
    /// Checks a revealed fleet against its commitment and against every report the defender gave.
    public static func audit(secret: FleetSecret, commitment: FleetCommitment, rules: GameRules, reports: [StrikeReport]) -> AuditResult {
        guard secret.commitment == commitment else { return .commitmentMismatch }
        guard secret.fleet.isValid(for: rules) else { return .illegalFleet }
        var ocean = OceanGrid(rules: rules, fleet: secret.fleet)
        for report in reports {
            guard let honest = try? ocean.resolve(report.strike), honest == report else {
                return .falseReport(report.strike)
            }
        }
        return .verified
    }
}
