import Foundation
import GRDB
import XCTest

@testable import SDVGCore

enum GRDBTestHelpers {
    static func outbox(_ db: Database) throws -> [Change] {
        try GRDB.Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY seq").map {
            Change(entity: $0["entity"], id: $0["id"],
                   fields: try JSONCoding.decode(Fields.self, from: $0["fields"]),
                   clocks: try JSONCoding.decode(Clocks.self, from: $0["clocks"]))
        }
    }

    /// Every entity row, for comparing two devices.
    static func snapshot(_ store: Store) throws -> [String: [DataRow]] {
        try store.read { db in
            Dictionary(uniqueKeysWithValues: try Entity.allCases.map { e in
                (e.rawValue, try Rows.fetch(e, db).sorted { $0.id < $1.id })
            })
        }
    }
}

/// In-memory implementation of the /api/sync protocol, used as the HTTP transport.
final class FakeServer: @unchecked Sendable {
    typealias Backup = (records: [String: (change: Change, seq: Int)], seq: Int)

    var serverID = UUID().uuidString.lowercased()
    var epoch = UUID().uuidString.lowercased()
    var token = "test-token"
    var down = false
    /// Sync requests (info probes are not counted).
    var requests = 0
    var reject: (Change) -> Bool = { _ in false }
    private var records: [String: (change: Change, seq: Int)] = [:]
    private var seq = 0
    private let lock = NSLock()

    var transport: HTTPTransport {
        { [self] request in try lock.withLock { try handle(request) } }
    }

    func row(_ entity: String, _ id: String) -> Change? { lock.withLock { records["\(entity)|\(id)"]?.change } }
    var size: Int { lock.withLock { records.count } }

    /// make reset-db: empty, under a new server_id.
    func reset() {
        lock.withLock {
            records = [:]
            seq = 0
            serverID = UUID().uuidString.lowercased()
            epoch = UUID().uuidString.lowercased()
        }
    }

    func backup() -> Backup { lock.withLock { (records, seq) } }

    /// make restore: the backup's rows and server_id, under a new epoch.
    func restore(_ backup: Backup) {
        lock.withLock {
            (records, seq) = backup
            epoch = UUID().uuidString.lowercased()
        }
    }

    private func info(error: String? = nil) -> JSONValue {
        var counts: [String: JSONValue] = [:]
        for r in records.values { counts[r.change.entity] = .int((counts[r.change.entity]?.int ?? 0) + 1) }
        var info: [String: JSONValue] = ["server_id": .string(serverID), "epoch": .string(epoch), "counts": .object(counts)]
        if let error { info["error"] = .string(error) }
        return .object(info)
    }

    private func handle(_ request: URLRequest) throws -> (Data, Int) {
        let probe = request.url?.path == "/api/sync/info"
        if !probe { requests += 1 }
        if down { throw URLError(.cannotConnectToHost) }
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" else { return (Data(), 401) }
        if probe { return (try JSONEncoder().encode(info()), 200) }
        let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
        if let known = body["server_id"]?.string, known != serverID {
            return (try JSONEncoder().encode(["detail": info(error: "server_changed")] as JSONValue), 409)
        }
        let changes = try JSONDecoder().decode([Change].self, from: JSONEncoder().encode(body["changes"]!))
        if let bad = changes.firstIndex(where: reject) {
            let detail: JSONValue = ["detail": ["message": .string("changes[\(bad)]: rejected"), "change_index": .int(bad)]]
            return (try JSONEncoder().encode(detail), 422)
        }
        let rewind = (body["epoch"]?.string).map { $0 != epoch } ?? false || body["cursor"]!.int! > seq
        for c in changes {
            let key = "\(c.entity)|\(c.id)"
            var row = records[key]?.change ?? Change(entity: c.entity, id: c.id, fields: [:], clocks: [:])
            if mergeFields(&row.fields, &row.clocks, c.fields, c.clocks) {
                seq += 1
                records[key] = (row, seq)
            }
        }
        let cursor = rewind ? 0 : body["cursor"]!.int!, limit = body["limit"]!.int!
        let newer = records.values.filter { $0.seq > cursor }.sorted { $0.seq < $1.seq }
        let page = Array(newer.prefix(limit))
        let response: JSONValue = [
            "server_id": .string(serverID), "epoch": .string(epoch), "cursor": .int(page.last?.seq ?? cursor),
            "changes": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(page.map(\.change))),
            "has_more": .bool(newer.count > limit), "rewind": .bool(rewind),
        ]
        return (try JSONEncoder().encode(response), 200)
    }
}

final class SyncTests: XCTestCase {
    struct Device {
        let store: Store
        let client: SyncClient
        let status: Box<SyncStatus>
    }

    func device(_ server: FakeServer, batchSize: Int = 500, token: String? = nil) throws -> Device {
        let store = try Store.open(path: nil)
        let status = Box(SyncStatus())
        let cfg = SyncConfig(baseURL: "http://fake", token: token ?? server.token)
        let client = SyncClient(store: store, batchSize: batchSize, transport: server.transport, config: { cfg },
                                onStatus: { status.value = $0 })
        return Device(store: store, client: client, status: status)
    }

    func testTwoDevicesConvergeAfterOfflineEdits() async throws {
        let server = FakeServer()
        let phone = try device(server), web = try device(server)
        let id = try web.store.createTask(TaskDraft(title: "Починить коляску", date: today))
        await web.client.sync()
        await phone.client.sync()

        try phone.store.updateTask(id, ["title": "Починить колесо коляски"])
        try web.store.completeTask(id, today: today)
        await web.client.sync()
        await phone.client.sync()
        await web.client.sync()

        XCTAssertEqual(try GRDBTestHelpers.snapshot(web.store), try GRDBTestHelpers.snapshot(phone.store))
        let task = try phone.store.get(.task, id).map(TaskRecord.init)
        XCTAssertEqual(task?.title, "Починить колесо коляски")
        XCTAssertEqual(task?.doneOn, today)
        XCTAssertEqual(phone.status.value.state, .idle)
    }

    func testDoubleRolloverAndTwoLunches() async throws {
        let server = FakeServer()
        let phone = try device(server), web = try device(server)
        let id = try web.store.createTask(TaskDraft(title: "Висит", date: "2026-09-20"))
        let lunch = try web.store.createRoutine(RoutineDraft(title: "Пообедать"), today: "2026-09-20")
        await web.client.sync()
        await phone.client.sync()

        for d in [web, phone] {
            try d.store.runRollover(today: today)
            try d.store.setRoutineCheck(lunch, date: today, status: .done)
        }
        await web.client.sync()
        await phone.client.sync()
        await web.client.sync()

        XCTAssertEqual(try phone.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM task_move") }, 2)
        XCTAssertEqual(try phone.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM routine_check") }, 1)
        XCTAssertEqual(server.row("task", id)?.fields["date"], .string(today))
        XCTAssertEqual(try GRDBTestHelpers.snapshot(web.store), try GRDBTestHelpers.snapshot(phone.store))
    }

    func testOfflineAndWrongTokenKeepTheOutbox() async throws {
        let server = FakeServer()
        let d = try device(server)
        try d.store.createTask(TaskDraft(title: "Офлайн"))
        server.down = true
        await d.client.sync()
        XCTAssertEqual(d.status.value.state, .offline)
        server.down = false
        server.token = "rotated"
        await d.client.sync()
        XCTAssertEqual(d.status.value.state, .unauthorized)
        XCTAssertEqual(try d.store.read { try GRDBTestHelpers.outbox($0) }.count, 1)
    }

    func testRejectedChangeIsQuarantined() async throws {
        let server = FakeServer()
        let d = try device(server)
        let good = try d.store.createTask(TaskDraft(title: "Хорошая"))
        let bad = try d.store.createTask(TaskDraft(title: "Плохая"))
        server.reject = { $0.id == bad }
        await d.client.sync()
        XCTAssertEqual(d.status.value.state, .idle)
        XCTAssertNotNil(server.row("task", good))
        XCTAssertNil(server.row("task", bad))
        XCTAssertEqual(try d.store.read { try String.fetchOne($0, sql: "SELECT id FROM rejected") }, bad)
    }

    func testPaging() async throws {
        let server = FakeServer()
        let web = try device(server, batchSize: 7)
        for i in 0..<30 { try web.store.createTask(TaskDraft(title: "Задача \(i)", date: today)) }
        await web.client.sync()
        XCTAssertEqual(server.size, 30)

        let phone = try device(server, batchSize: 4)
        await phone.client.sync()
        XCTAssertEqual(try GRDBTestHelpers.snapshot(phone.store), try GRDBTestHelpers.snapshot(web.store))
    }

    func testPausesOnResetServerAndSendsNothing() async throws {
        let server = FakeServer()
        let web = try device(server)
        try web.store.createTask(TaskDraft(title: "Старая", date: today))
        await web.client.sync()

        server.reset()
        try web.store.createTask(TaskDraft(title: "Новая", date: today))
        await web.client.sync()
        XCTAssertEqual(web.status.value.state, .serverChanged)
        XCTAssertEqual(web.status.value.serverChange, ServerChange(
            kind: .changed, serverID: server.serverID,
            server: SyncCounts(task: 0, routine: 0), local: SyncCounts(task: 2, routine: 0)))
        XCTAssertEqual(server.size, 0)
        XCTAssertEqual(try web.store.read { try GRDBTestHelpers.outbox($0) }.count, 1)

        await web.client.sync() // asks again, still sends nothing
        XCTAssertEqual(web.status.value.state, .serverChanged)
        XCTAssertEqual(server.size, 0)
    }

    func testTakesServerDataAsItIs() async throws {
        let server = FakeServer()
        let web = try device(server)
        try web.store.createTask(TaskDraft(title: "Тестовая", date: today))
        await web.client.sync()

        server.reset()
        let phone = try device(server)
        let real = try phone.store.createTask(TaskDraft(title: "Настоящая", date: today))
        await phone.client.sync()
        await web.client.sync()
        XCTAssertEqual(web.status.value.state, .serverChanged)

        try await web.client.takeServerData()
        XCTAssertEqual(web.status.value.state, .idle)
        XCTAssertEqual(try web.store.read { try Rows.fetch(.task, $0) }.map(\.id), [real])
        XCTAssertEqual(try GRDBTestHelpers.snapshot(web.store), try GRDBTestHelpers.snapshot(phone.store))
        XCTAssertEqual(server.size, 1)
    }

    func testMergesIntoNewDataSetWhenAsked() async throws {
        let server = FakeServer()
        let web = try device(server)
        let id = try web.store.createTask(TaskDraft(title: "Починить коляску", date: today))
        try web.store.postponeTask(id, today: today)
        await web.client.sync()

        server.reset()
        await web.client.sync()
        try await web.client.mergeWithServer()
        XCTAssertEqual(web.status.value.state, .idle)
        XCTAssertEqual(server.size, 2)

        let phone = try device(server)
        await phone.client.sync()
        XCTAssertEqual(try GRDBTestHelpers.snapshot(phone.store), try GRDBTestHelpers.snapshot(web.store))
    }

    func testFirstConnectionAsksWhenBothSidesHaveData() async throws {
        let server = FakeServer()
        let phone = try device(server)
        try phone.store.createTask(TaskDraft(title: "С телефона", date: today))
        await phone.client.sync()

        let web = try device(server)
        try web.store.createTask(TaskDraft(title: "Из браузера", date: today))
        await web.client.sync()
        XCTAssertEqual(web.status.value.state, .serverChanged)
        XCTAssertEqual(web.status.value.serverChange?.kind, .first)
        XCTAssertEqual(web.status.value.serverChange?.server, SyncCounts(task: 1, routine: 0))
        XCTAssertEqual(server.size, 1)

        try await web.client.mergeWithServer()
        await phone.client.sync()
        XCTAssertEqual(server.size, 2)
        XCTAssertEqual(try GRDBTestHelpers.snapshot(web.store), try GRDBTestHelpers.snapshot(phone.store))
    }

    func testConnectsToEmptyServerWithoutAsking() async throws {
        let server = FakeServer()
        let web = try device(server)
        try web.store.createTask(TaskDraft(title: "Первая", date: today))
        await web.client.sync()
        XCTAssertEqual(web.status.value.state, .idle)
        XCTAssertEqual(server.size, 1)
    }

    func testRestoredServerGetsBackWhatItsBackupLacks() async throws {
        let server = FakeServer()
        let web = try device(server), phone = try device(server)
        let id = try web.store.createTask(TaskDraft(title: "Починить коляску", date: today))
        await web.client.sync()
        await phone.client.sync()
        let backup = server.backup()

        try phone.store.updateTask(id, ["title": "После бэкапа"])
        let later = try phone.store.createTask(TaskDraft(title: "Тоже после", date: today))
        await phone.client.sync()
        await web.client.sync()

        server.restore(backup)
        await web.client.sync() // rewind: sends every row it has
        XCTAssertEqual(web.status.value.state, .idle)
        XCTAssertEqual(server.row("task", id)?.fields["title"], .string("После бэкапа"))
        XCTAssertNotNil(server.row("task", later))

        await phone.client.sync()
        XCTAssertEqual(try GRDBTestHelpers.snapshot(phone.store), try GRDBTestHelpers.snapshot(web.store))
        let fresh = try device(server)
        await fresh.client.sync()
        XCTAssertEqual(try GRDBTestHelpers.snapshot(fresh.store), try GRDBTestHelpers.snapshot(web.store))
    }
}

/// Against a real backend: `make test-ios-live` starts one on a throwaway database.
final class LiveSyncTests: XCTestCase {
    func testTwoDevicesThroughRealServer() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["SDVG_LIVE_URL"], let token = env["SDVG_LIVE_TOKEN"] else {
            throw XCTSkip("SDVG_LIVE_URL not set")
        }
        let cfg = SyncConfig(baseURL: url, token: token)
        func device() throws -> (Store, SyncClient) {
            let store = try Store.open(path: nil)
            return (store, SyncClient(store: store, config: { cfg }))
        }
        let (web, webSync) = try device(), (phone, phoneSync) = try device()
        let id = try web.createTask(TaskDraft(title: "Починить коляску", date: "2026-09-20"))
        let lunch = try web.createRoutine(RoutineDraft(title: "Пообедать"), today: today)
        await webSync.sync()
        await phoneSync.sync()

        for s in [web, phone] {
            try s.runRollover(today: today)
            try s.setRoutineCheck(lunch, date: today, status: .done)
        }
        try phone.updateTask(id, ["title": "Починить колесо коляски"])
        try web.completeTask(id, today: today)
        await webSync.sync()
        await phoneSync.sync()
        await webSync.sync()

        let phoneStatus = await phoneSync.status
        XCTAssertEqual(phoneStatus.state, .idle, phoneStatus.error ?? "")
        XCTAssertEqual(try GRDBTestHelpers.snapshot(web), try GRDBTestHelpers.snapshot(phone))
        XCTAssertEqual(try phone.moveCount(id), 2)
        XCTAssertEqual(try phone.get(.task, id).map(TaskRecord.init)?.title, "Починить колесо коляски")
        XCTAssertEqual(try phone.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM rejected") }, 0)
    }
}
