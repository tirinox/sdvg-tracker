import Foundation
import GRDB

public struct SyncConfig: Equatable, Sendable {
    public var baseURL: String
    public var token: String

    public init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum SyncState: String, Sendable {
    case idle, syncing, offline, unauthorized, unconfigured, serverChanged, error
}

/// Tasks and routines, on the server or on this device.
public struct SyncCounts: Equatable, Sendable {
    public var task: Int
    public var routine: Int
    public var isEmpty: Bool { task + routine == 0 }

    public init(task: Int, routine: Int) {
        self.task = task
        self.routine = routine
    }
}

/// The server holds data this device has not synced with; sync waits for the user's choice.
public struct ServerChange: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable { case changed, first }
    /// .changed: the server's data set was replaced; .first: first connection, both sides have data.
    public var kind: Kind
    public var serverID: String
    public var server: SyncCounts
    public var local: SyncCounts
    public var id: String { serverID }
}

public struct SyncStatus: Equatable, Sendable {
    public var state: SyncState = .idle
    public var lastSyncAt: Date?
    public var error: String?
    /// Set while state is .serverChanged.
    public var serverChange: ServerChange?
    public init() {}
}

/// Sends a request, returns body and status code. Injected so tests can use a fake server.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, Int)

public let urlSessionTransport: HTTPTransport = { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// Implements the /api/sync protocol from shared/README.md over the local Store.
public actor SyncClient {
    private let store: Store
    private let config: @Sendable () async -> SyncConfig?
    private let transport: HTTPTransport
    private let batchSize: Int
    private let onStatus: @Sendable (SyncStatus) -> Void
    private var running: Task<Void, Never>?
    private var again = false
    public private(set) var status = SyncStatus()

    private static let maxRounds = 1000

    public init(
        store: Store, batchSize: Int = 500, transport: @escaping HTTPTransport = urlSessionTransport,
        config: @escaping @Sendable () async -> SyncConfig?, onStatus: @escaping @Sendable (SyncStatus) -> Void = { _ in }
    ) {
        self.store = store
        self.batchSize = batchSize
        self.transport = transport
        self.config = config
        self.onStatus = onStatus
    }

    /// Single-flight: a call during a running sync schedules exactly one more round.
    public func sync() async {
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                again = false
                await run()
            } while again
        }
        running = task
        await task.value
        running = nil
    }

    private func setStatus(_ state: SyncState, _ error: String? = nil, serverChange: ServerChange? = nil) {
        status.state = state
        status.error = error
        // A pending question stays up while the next sync checks again, so it does not flicker.
        if state != .syncing { status.serverChange = serverChange }
        if state == .idle { status.lastSyncAt = Date() }
        onStatus(status)
    }

    private struct OutboxEntry {
        var seq: Int64
        var change: Change
    }

    private struct Response: Decodable {
        var server_id: String
        var epoch: String
        var cursor: Int
        var changes: [Change]
        var has_more: Bool
        var rewind: Bool
    }

    private struct Request: Encodable {
        var cursor: Int
        var changes: [Change]
        var limit: Int
        /// Omitted before the first sync; a different one is refused with 409.
        var server_id: String?
        var epoch: String?
    }

    /// GET /api/sync/info, and the detail of a 409 server_changed.
    private struct ServerInfo: Decodable {
        var server_id: String
        var counts: [String: Int]
    }

    private struct Conflict: Decodable {
        var detail: ServerInfo
    }

    private func run() async {
        guard let cfg = await config(), !cfg.token.isEmpty, let url = URL(string: cfg.baseURL + "/api/sync") else {
            setStatus(.unconfigured)
            return
        }
        setStatus(.syncing)
        do {
            if try store.read({ try Meta.get($0, Self.serverKey) }) == nil, !(try await firstContact(cfg)) { return }
            for _ in 0..<Self.maxRounds {
                let limit = batchSize
                let (batch, cursor, knownServer, epoch) = try store.read { db in
                    (try Self.outbox(db, limit: limit), try Meta.get(db, Self.cursorKey)?.int ?? 0,
                     try Meta.get(db, Self.serverKey)?.string, try Meta.get(db, Self.epochKey)?.string)
                }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(Request(
                    cursor: cursor, changes: batch.map(\.change), limit: batchSize, server_id: knownServer, epoch: epoch))

                let data: Data, code: Int
                do {
                    (data, code) = try await transport(request)
                } catch {
                    setStatus(.offline)
                    return
                }

                if code == 401 {
                    setStatus(.unauthorized)
                    return
                }
                if code == 409 {
                    // Another data set: nothing was applied, and nothing is sent until the user decides.
                    try pause(.changed, JSONDecoder().decode(Conflict.self, from: data).detail)
                    return
                }
                if code == 422 {
                    let detail = (try? JSONDecoder().decode(JSONValue.self, from: data))?["detail"]
                    guard let index = detail?["change_index"]?.int, batch.indices.contains(index) else {
                        setStatus(.error, "Server rejected the request")
                        return
                    }
                    try quarantine(batch[index], error: detail?["message"]?.string ?? "HTTP 422")
                    continue
                }
                guard (200..<300).contains(code) else {
                    setStatus(code >= 500 ? .offline : .error, "HTTP \(code)")
                    return
                }

                let body = try JSONDecoder().decode(Response.self, from: data)
                let pushed = batch.map(\.seq)
                let remaining = try await store.writer.write { db -> Int in
                    try Self.deleteOutbox(db, pushed)
                    try store.applyRemote(db, body.changes)
                    // Restored from a backup: it lacks whatever changed after the backup, so send it all.
                    if body.rewind { try Self.enqueueAll(db) }
                    try Meta.set(db, Self.cursorKey, .int(body.cursor))
                    try Meta.set(db, Self.serverKey, .string(body.server_id))
                    try Meta.set(db, Self.epochKey, .string(body.epoch))
                    return try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox") ?? 0
                }
                if !body.has_more && remaining == 0 {
                    setStatus(.idle)
                    return
                }
            }
            setStatus(.error, "Sync did not settle")
        } catch {
            setStatus(.error, String(describing: error))
        }
    }

    private static func outbox(_ db: Database, limit: Int) throws -> [OutboxEntry] {
        try GRDB.Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY seq LIMIT ?", arguments: [limit]).map { r in
            OutboxEntry(seq: r["seq"], change: Change(
                entity: r["entity"], id: r["id"],
                fields: try JSONCoding.decode(Fields.self, from: r["fields"]),
                clocks: try JSONCoding.decode(Clocks.self, from: r["clocks"])))
        }
    }

    private static func deleteOutbox(_ db: Database, _ seqs: [Int64]) throws {
        guard !seqs.isEmpty else { return }
        try db.execute(sql: "DELETE FROM outbox WHERE seq IN (\(seqs.map(String.init).joined(separator: ",")))")
    }

    private func quarantine(_ entry: OutboxEntry, error: String) throws {
        try store.writer.write { db in
            try Self.deleteOutbox(db, [entry.seq])
            try db.execute(
                sql: "INSERT INTO rejected (entity, id, fields, clocks, error, rejected_at) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [entry.change.entity, entry.change.id, try JSONCoding.string(entry.change.fields),
                            try JSONCoding.string(entry.change.clocks), error, Dates.isoNow()])
        }
    }

    private static let cursorKey = "sync_cursor"
    private static let serverKey = "sync_server_id"
    private static let epochKey = "sync_epoch"

    /// Answer to .serverChanged: drop this device's data and download the server's.
    public func takeServerData() async throws {
        try await store.writer.write { db in
            for entity in Entity.allCases { try db.execute(sql: "DELETE FROM \(entity.rawValue)") }
            try db.execute(sql: "DELETE FROM outbox")
            try db.execute(sql: "DELETE FROM rejected")
            try db.execute(sql: "DELETE FROM meta WHERE key IN (?, ?, ?)",
                           arguments: [Self.cursorKey, Self.serverKey, Self.epochKey])
        }
        await sync()
    }

    /// Answer to .serverChanged: send every row of this device into the server's data set.
    public func mergeWithServer() async throws {
        guard let change = status.serverChange else { return }
        try await store.writer.write { db in
            try Self.enqueueAll(db)
            try Meta.set(db, Self.cursorKey, .int(0))
            try Meta.set(db, Self.serverKey, .string(change.serverID))
            try db.execute(sql: "DELETE FROM meta WHERE key = ?", arguments: [Self.epochKey])
        }
        await sync()
    }

    private func pause(_ kind: ServerChange.Kind, _ info: ServerInfo) throws {
        let server = SyncCounts(task: info.counts["task"] ?? 0, routine: info.counts["routine"] ?? 0)
        let change = ServerChange(kind: kind, serverID: info.server_id, server: server, local: try localCounts())
        setStatus(.serverChanged, serverChange: change)
    }

    private func localCounts() throws -> SyncCounts {
        try store.read { db in
            SyncCounts(task: try Int.fetchOne(db, sql: "SELECT count(*) FROM task") ?? 0,
                       routine: try Int.fetchOne(db, sql: "SELECT count(*) FROM routine") ?? 0)
        }
    }

    /// Before the first sync, a device that already has tasks or routines looks at the server:
    /// if that has data too, merging is the user's call. False = stop (status is set).
    private func firstContact(_ cfg: SyncConfig) async throws -> Bool {
        guard try !localCounts().isEmpty else { return true }
        guard let url = URL(string: cfg.baseURL + "/api/sync/info") else { return true }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        let data: Data, code: Int
        do {
            (data, code) = try await transport(request)
        } catch {
            setStatus(.offline)
            return false
        }
        guard code == 200 else {
            setStatus(code == 401 ? .unauthorized : code >= 500 ? .offline : .error, "HTTP \(code)")
            return false
        }
        let info = try JSONDecoder().decode(ServerInfo.self, from: data)
        if (info.counts["task"] ?? 0) + (info.counts["routine"] ?? 0) == 0 { return true }
        try pause(.first, info)
        return false
    }

    /// Replaces the outbox with every row we have, whole: they already hold every local change.
    private static func enqueueAll(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM outbox")
        for entity in Entity.allCases {
            try db.execute(sql: """
                INSERT INTO outbox (entity, id, fields, clocks)
                SELECT '\(entity.rawValue)', id, fields, clocks FROM \(entity.rawValue)
                """)
        }
    }
}
