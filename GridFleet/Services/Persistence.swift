import Foundation
import GridFleetCore
import SwiftData

enum GameMode: String, Codable, CaseIterable {
    case computer
    case passAndPlay
    case online
    case live
    case room
    case nearby

    var displayName: String {
        switch self {
        case .computer: "Vs Computer"
        case .passAndPlay: "Pass & Play"
        case .online: "Online"
        case .live: "Live"
        case .room: "Room Code"
        case .nearby: "Across the Table"
        }
    }
}

/// One finished game, for the logbook. Synced with iCloud.
@Model
final class GameRecord {
    var id: UUID = UUID()
    var playedAt: Date = Date.now
    var modeRaw: String = GameMode.computer.rawValue
    var difficultyRaw: String?
    var presetRaw: String = BoardPreset.classic.rawValue
    var salvo: Bool = false
    var specials: Bool = false
    var won: Bool = false
    var opponentName: String = ""
    var shotsFired: Int = 0
    var hits: Int = 0
    var turns: Int = 0
    var shipsLost: Int = 0
    var durationSeconds: Double = 0
    /// Online games: whether the opponent's revealed fleet matched its seal. Nil if not checked.
    var verified: Bool?

    init() {}

    var mode: GameMode { GameMode(rawValue: modeRaw) ?? .computer }
    var difficulty: AIDifficulty? { difficultyRaw.flatMap(AIDifficulty.init(rawValue:)) }
    var preset: BoardPreset { BoardPreset(rawValue: presetRaw) ?? .classic }
    var accuracy: Double { shotsFired == 0 ? 0 : Double(hits) / Double(shotsFired) }
}

/// A medal earned in a battle. Synced with iCloud.
@Model
final class MedalAward {
    var medalRaw: String = ""
    var earnedAt: Date = Date.now
    var opponentName: String = ""

    init(medal: Medal, opponentName: String) {
        self.medalRaw = medal.rawValue
        self.opponentName = opponentName
    }

    var medal: Medal? { Medal(rawValue: medalRaw) }
}

/// A sealed fleet for an online game, plus the last match state this device saw. Synced with iCloud
/// so a game can continue on another device.
@Model
final class MatchSecretRecord {
    var matchID: String = ""
    var secretData: Data?
    var lastSeenLedger: Data?
    var recorded: Bool = false
    var createdAt: Date = Date.now

    init(matchID: String) {
        self.matchID = matchID
    }
}

/// A finished game, ready for the logbook.
struct GameSummary {
    var mode: GameMode
    var difficulty: AIDifficulty?
    var rules: GameRules
    var won: Bool
    var opponentName: String
    var stats: BattleStats
    var shipsLost: Int
    var duration: TimeInterval
    var verified: Bool?
    var medals: [Medal] = []
}

enum Persistence {
    static let cloudContainer = "iCloud.com.leejustin.gridfleet"

    static func makeContainer() -> ModelContainer {
        let schema = Schema([GameRecord.self, MatchSecretRecord.self, MedalAward.self])
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainer))
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // No iCloud: keep everything on this device.
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
            } catch {
                return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            }
        }
    }

    static func record(_ summary: GameSummary, in context: ModelContext) {
        let record = GameRecord()
        record.modeRaw = summary.mode.rawValue
        record.difficultyRaw = summary.difficulty?.rawValue
        record.presetRaw = summary.rules.preset.rawValue
        record.salvo = summary.rules.firing == .salvo
        record.specials = summary.rules.specialWeapons
        record.won = summary.won
        record.opponentName = summary.opponentName
        record.shotsFired = summary.stats.shotsFired
        record.hits = summary.stats.hits
        record.turns = summary.stats.turns
        record.shipsLost = summary.shipsLost
        record.durationSeconds = summary.duration
        record.verified = summary.verified
        context.insert(record)
        for medal in summary.medals {
            context.insert(MedalAward(medal: medal, opponentName: summary.opponentName))
        }
        try? context.save()
    }
}

/// Keeps each online game's sealed fleet on this device (and in the player's iCloud).
@MainActor
struct SecretStore {
    let context: ModelContext

    private func record(_ matchID: String) -> MatchSecretRecord? {
        var descriptor = FetchDescriptor<MatchSecretRecord>(predicate: #Predicate { $0.matchID == matchID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func recordOrNew(_ matchID: String) -> MatchSecretRecord {
        if let existing = record(matchID) { return existing }
        let new = MatchSecretRecord(matchID: matchID)
        context.insert(new)
        return new
    }

    func secret(for matchID: String) -> FleetSecret? {
        record(matchID)?.secretData.flatMap { try? JSONDecoder().decode(FleetSecret.self, from: $0) }
    }

    func save(_ secret: FleetSecret, for matchID: String) {
        recordOrNew(matchID).secretData = try? JSONEncoder().encode(secret)
        try? context.save()
    }

    func lastSeen(for matchID: String) -> MatchLedger? {
        record(matchID)?.lastSeenLedger.flatMap { try? MatchLedger.decode($0) }
    }

    func saveLastSeen(_ ledger: MatchLedger, for matchID: String) {
        recordOrNew(matchID).lastSeenLedger = try? ledger.encoded()
        try? context.save()
    }

    /// Marks the game as logged. Returns false if it already was.
    func markRecorded(_ matchID: String) -> Bool {
        let record = recordOrNew(matchID)
        guard !record.recorded else { return false }
        record.recorded = true
        try? context.save()
        return true
    }
}
