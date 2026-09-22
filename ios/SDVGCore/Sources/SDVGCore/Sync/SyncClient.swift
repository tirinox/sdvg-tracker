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
    case idle, syncing, offline, unauthorized, unconfigured, error
}

public struct SyncStatus: Equatable, Sendable {
    public var state: SyncState = .idle
    public var lastSyncAt: Date?
    public var error: String?
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

    private func setStatus(_ state: SyncState, _ error: String? = nil) {
        status.state = state
        status.error = error
        if state == .idle { status.lastSyncAt = Date() }
        onStatus(status)
    }

    private struct OutboxEntry {
        var seq: Int64
        var change: Change
    }

    private struct Response: Decodable {
        var server_id: String
        var cursor: Int
        var changes: [Change]
        var has_more: Bool
    }

    private struct Request: Encodable {
        var cursor: Int
        var changes: [Change]
        var limit: Int
    }

    private func run() async {
        guard let cfg = await config(), !cfg.token.isEmpty, let url = URL(string: cfg.baseURL + "/api/sync") else {
            setStatus(.unconfigured)
            return
        }
        setStatus(.syncing)
        do {
            for _ in 0..<Self.maxRounds {
                let limit = batchSize
                let (batch, cursor, knownServer) = try store.read { db in
                    (try Self.outbox(db, limit: limit), try Meta.get(db, "sync_cursor")?.int ?? 0, try Meta.get(db, "sync_server_id")?.string)
                }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(Request(cursor: cursor, changes: batch.map(\.change), limit: batchSize))

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
                if let knownServer, knownServer != body.server_id {
                    try resetForNewServer(body.server_id, pushed: pushed)
                    continue
                }
                let remaining = try await store.writer.write { db -> Int in
                    try Self.deleteOutbox(db, pushed)
                    try store.applyRemote(db, body.changes)
                    try Meta.set(db, "sync_cursor", .int(body.cursor))
                    try Meta.set(db, "sync_server_id", .string(body.server_id))
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

    /// The server database was replaced: start over and hand it every row we have.
    private func resetForNewServer(_ serverID: String, pushed: [Int64]) throws {
        try store.writer.write { db in
            try Self.deleteOutbox(db, pushed)
            for entity in Entity.allCases {
                try db.execute(sql: """
                    INSERT INTO outbox (entity, id, fields, clocks)
                    SELECT '\(entity.rawValue)', id, fields, clocks FROM \(entity.rawValue)
                    """)
            }
            try Meta.set(db, "sync_cursor", .int(0))
            try Meta.set(db, "sync_server_id", .string(serverID))
        }
    }
}
