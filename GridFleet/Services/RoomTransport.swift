import CloudKit
import GridFleetCore

enum RoomError: LocalizedError {
    case notFound
    case full
    case noICloud

    var errorDescription: String? {
        switch self {
        case .notFound: "No room with that code. Check it and try again."
        case .full: "That room already has two captains."
        case .noICloud: "Room codes need iCloud. Sign in under Settings > [your name]."
        }
    }
}

/// A match shared through a six-character code, stored in CloudKit's public database.
@MainActor
final class RoomTransport: LedgerTransport {
    static let recordType = "Room"
    /// No 0/O or 1/I, so codes are easy to read aloud.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    let code: String
    let isHost: Bool
    let captainID: String
    let mode: GameMode = .room
    let turnTimeLimit: TimeInterval? = nil
    var onRemoteUpdate: ((MatchLedger) -> Void)?
    var onOpponentLeft: (() -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var isRealtime: Bool { false }

    private var record: CKRecord
    private var latest: MatchLedger?
    private var pollTask: Task<Void, Never>?

    private static var database: CKDatabase { CKContainer(identifier: Persistence.cloudContainer).publicCloudDatabase }

    private init(code: String, isHost: Bool, captainID: String, record: CKRecord) {
        self.code = code
        self.isHost = isHost
        self.captainID = captainID
        self.record = record
        self.latest = (record["ledger"] as? Data).flatMap { try? MatchLedger.decode($0) }
    }

    static func makeCode() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    static func recordID(for code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "room-\(code)")
    }

    static func normalize(_ code: String) -> String {
        code.uppercased().filter { alphabet.contains($0) }
    }

    /// Opens a new room and returns it with its code.
    static func create(rules: GameRules, hostName: String, captainID: String) async throws -> RoomTransport {
        guard try await CKContainer(identifier: Persistence.cloudContainer).accountStatus() == .available else { throw RoomError.noICloud }
        for _ in 0..<5 {
            let code = makeCode()
            let record = CKRecord(recordType: recordType, recordID: recordID(for: code))
            var ledger = MatchLedger(rules: rules)
            ledger.seats[0].displayName = hostName
            record["ledger"] = try ledger.encoded()
            record["host"] = captainID
            do {
                let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                if let result = saved.values.first, case .success(let stored) = result {
                    return RoomTransport(code: code, isHost: true, captainID: captainID, record: stored)
                }
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue // Code taken; try another.
            }
        }
        throw RoomError.full
    }

    static func join(code raw: String, guestName: String, captainID: String) async throws -> RoomTransport {
        let code = normalize(raw)
        guard try await CKContainer(identifier: Persistence.cloudContainer).accountStatus() == .available else { throw RoomError.noICloud }
        let record: CKRecord
        do {
            record = try await database.record(for: recordID(for: code))
        } catch let error as CKError where error.code == .unknownItem {
            throw RoomError.notFound
        }
        let host = record["host"] as? String
        if host == captainID {
            return RoomTransport(code: code, isHost: true, captainID: captainID, record: record)
        }
        if let guest = record["guest"] as? String {
            guard guest == captainID else { throw RoomError.full }
            return RoomTransport(code: code, isHost: false, captainID: captainID, record: record)
        }
        record["guest"] = captainID
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
        guard let result = saved.values.first, case .success(let stored) = result else { throw RoomError.full }
        return RoomTransport(code: code, isHost: false, captainID: captainID, record: stored)
    }

    var matchID: String { "room-\(code)" }
    var localSeat: Int { isHost ? 0 : 1 }
    var localPlayerID: String? { captainID }

    var opponentName: String {
        latest?.seats[MatchLedger.opponent(of: localSeat)].displayName ?? (isHost ? "Waiting for crew" : "Host")
    }

    var opponentDetail: String { "Room \(code)" }
    let forfeitedSeat: Int? = nil

    var isLocalTurn: Bool { (latest?.actingSeat ?? 0) == localSeat }

    var shareURL: URL { URL(string: "gridfleet://room/\(code)")! }

    func load() async throws -> MatchLedger? {
        startPolling()
        return latest
    }

    func share(_ ledger: MatchLedger) async throws { try await write(ledger) }
    func endTurn(_ ledger: MatchLedger) async throws { try await write(ledger) }
    func endMatch(_ ledger: MatchLedger) async throws { try await write(ledger) }
    func resign(_ ledger: MatchLedger) async throws { try await write(ledger) }

    func close() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func write(_ ledger: MatchLedger) async throws {
        latest = ledger
        for attempt in 0..<3 {
            record["ledger"] = try ledger.encoded()
            do {
                let (saved, _) = try await Self.database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
                if let result = saved.values.first {
                    switch result {
                    case .success(let stored): record = stored
                    case .failure(let error): throw error
                    }
                }
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                // Someone else touched the record (the guest joining, say). Take theirs and write again.
                if let server = error.serverRecord { record = server }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.poll()
            }
        }
    }

    private func poll() async {
        guard let fresh = try? await Self.database.record(for: record.recordID) else { return }
        guard fresh.recordChangeTag != record.recordChangeTag else { return }
        record = fresh
        guard let data = fresh["ledger"] as? Data, let ledger = try? MatchLedger.decode(data) else { return }
        latest = ledger
        onRemoteUpdate?(ledger)
    }
}
