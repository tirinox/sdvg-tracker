import Foundation
import GRDB

public struct LocalChange: Sendable {
    public var entity: Entity
    public var id: String
    public var fields: Fields

    public init(_ entity: Entity, _ id: String, _ fields: Fields) {
        self.entity = entity
        self.id = id
        self.fields = fields
    }
}

/// The local source of truth. Local writes get HLC clocks and go to the outbox in the same
/// transaction; remote changes are merged without touching the outbox.
public final class Store: @unchecked Sendable {
    public let writer: any DatabaseWriter
    public let clock: HybridClock
    private let lock = NSLock()
    private var listeners: [UUID: @Sendable () -> Void] = [:]

    /// `path == nil` opens an in-memory database (tests).
    public static func open(path: String?, nowMs: @escaping @Sendable () -> Int64 = HybridClock.wallMs) throws -> Store {
        let writer: any DatabaseWriter
        if let path {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            writer = try DatabasePool(path: path)
        } else {
            writer = try DatabaseQueue()
        }
        try Schema.migrator.migrate(writer)
        let (nodeID, last) = try writer.write { db -> (String, String?) in
            var nodeID = try Meta.get(db, "node_id")?.string
            if nodeID == nil {
                nodeID = HybridClock.randomNodeID()
                try Meta.set(db, "node_id", .string(nodeID!))
            }
            return (nodeID!, try Meta.get(db, "hlc")?.string)
        }
        return Store(writer: writer, clock: HybridClock(nodeID: nodeID, resumingFrom: last, nowMs: nowMs))
    }

    init(writer: any DatabaseWriter, clock: HybridClock) {
        self.writer = writer
        self.clock = clock
    }

    public var nodeID: String { clock.nodeID }

    /// Called after every committed local write (the sync scheduler debounces on this).
    @discardableResult
    public func onLocalWrite(_ listener: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.withLock { listeners[id] = listener }
        return id
    }

    public func write(_ changes: [LocalChange]) throws {
        guard !changes.isEmpty else { return }
        try writer.write { db in
            var last = ""
            for c in changes {
                last = clock.now()
                let change = Change(
                    entity: c.entity.rawValue, id: c.id, fields: c.fields,
                    clocks: Dictionary(uniqueKeysWithValues: c.fields.keys.map { ($0, last) }))
                try Rows.merge(db, change)
                try db.execute(
                    sql: "INSERT INTO outbox (entity, id, fields, clocks) VALUES (?, ?, ?, ?)",
                    arguments: [change.entity, change.id, try JSONCoding.string(change.fields), try JSONCoding.string(change.clocks)])
            }
            try Meta.set(db, "hlc", .string(last))
        }
        for listener in lock.withLock({ Array(listeners.values) }) { listener() }
    }

    /// Merge changes pulled from the server; runs inside the caller's write transaction.
    public func applyRemote(_ db: Database, _ changes: [Change]) throws {
        var last: String?
        for change in changes {
            if let newest = change.clocks.values.max() { last = clock.receive(newest) }
            try Rows.merge(db, change)
        }
        if let last { try Meta.set(db, "hlc", .string(last)) }
    }

    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        try writer.read(block)
    }

    public func get(_ entity: Entity, _ id: String) throws -> DataRow? {
        try writer.read { try Rows.fetch(entity, $0, id: id) }
    }

    public func settings() throws -> Settings {
        try writer.read { try Rows.settings($0) }
    }

    public func meta(_ key: String) throws -> JSONValue? {
        try writer.read { try Meta.get($0, key) }
    }

    public func setMeta(_ key: String, _ value: JSONValue) throws {
        try writer.write { try Meta.set($0, key, value) }
    }
}

enum Schema {
    /// Rows keep the wire shape (fields/clocks as JSON); generated columns index into fields.
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            let indexed: [Entity: [String]] = [
                .task: ["date", "done_on"],
                .task_move: ["task_id"],
                .routine_version: ["routine_id"],
                .routine_check: ["date", "routine_id"],
            ]
            for entity in Entity.allCases {
                let columns = (indexed[entity] ?? []).map {
                    ", \($0) TEXT GENERATED ALWAYS AS (json_extract(fields, '$.\($0)')) VIRTUAL"
                }.joined()
                try db.execute(sql: """
                    CREATE TABLE \(entity.rawValue) (
                        id TEXT PRIMARY KEY NOT NULL, fields TEXT NOT NULL, clocks TEXT NOT NULL\(columns))
                    """)
                for column in indexed[entity] ?? [] {
                    try db.execute(sql: "CREATE INDEX \(entity.rawValue)_\(column) ON \(entity.rawValue)(\(column))")
                }
            }
            try db.execute(sql: """
                CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, id TEXT NOT NULL,
                    fields TEXT NOT NULL, clocks TEXT NOT NULL);
                CREATE TABLE rejected (seq INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, id TEXT NOT NULL,
                    fields TEXT NOT NULL, clocks TEXT NOT NULL, error TEXT NOT NULL, rejected_at TEXT NOT NULL);
                CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                """)
        }
        return m
    }
}

public enum Rows {
    public static func fetch(_ entity: Entity, _ db: Database, where condition: String? = nil, _ arguments: StatementArguments = []) throws -> [DataRow] {
        let sql = "SELECT id, fields, clocks FROM \(entity.rawValue)" + (condition.map { " WHERE \($0)" } ?? "")
        return try GRDB.Row.fetchAll(db, sql: sql, arguments: arguments).map(decode)
    }

    public static func fetch(_ entity: Entity, _ db: Database, id: String) throws -> DataRow? {
        try fetch(entity, db, where: "id = ?", [id]).first
    }

    static func decode(_ r: GRDB.Row) throws -> DataRow {
        DataRow(
            id: r["id"],
            fields: try JSONCoding.decode(Fields.self, from: r["fields"]),
            clocks: try JSONCoding.decode(Clocks.self, from: r["clocks"]))
    }

    static func put(_ db: Database, _ entity: String, _ row: DataRow) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(entity) (id, fields, clocks) VALUES (?, ?, ?)",
            arguments: [row.id, try JSONCoding.string(row.fields), try JSONCoding.string(row.clocks)])
    }

    @discardableResult
    static func merge(_ db: Database, _ change: Change) throws -> Bool {
        guard let entity = Entity(rawValue: change.entity) else { return false }
        var row = try fetch(entity, db, id: change.id) ?? DataRow(id: change.id)
        guard mergeFields(&row.fields, &row.clocks, change.fields, change.clocks) else { return false }
        try put(db, change.entity, row)
        return true
    }

    public static func settings(_ db: Database) throws -> Settings {
        Settings(try fetch(.settings, db, id: settingsID)?.fields ?? [:])
    }
}

public enum Meta {
    public static func get(_ db: Database, _ key: String) throws -> JSONValue? {
        guard let text = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) else { return nil }
        return try JSONCoding.decode(JSONValue.self, from: text)
    }

    public static func set(_ db: Database, _ key: String, _ value: JSONValue) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, try JSONCoding.string(value)])
    }
}
