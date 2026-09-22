import XCTest

@testable import SDVGCore

let today = "2026-09-22"
let nowLocal = "2026-09-22T14:40"

final class StoreTests: XCTestCase {
    func store() throws -> Store { try Store.open(path: nil) }

    func testWriteQueuesOneClockPerChange() throws {
        let s = try store()
        let id = try s.createTask(TaskDraft(title: "Починить коляску", date: today))
        let outbox = try s.read { try GRDBTestHelpers.outbox($0) }
        XCTAssertEqual(outbox.count, 1)
        XCTAssertEqual(outbox[0].id, id)
        XCTAssertEqual(Set(outbox[0].clocks.values).count, 1)
        XCTAssertEqual(Set(outbox[0].clocks.keys), Set(outbox[0].fields.keys))
    }

    func testClockResumesAfterReopen() throws {
        let path = NSTemporaryDirectory() + UUID().uuidString + "/db.sqlite"
        let first = try Store.open(path: path, nowMs: { 1_790_000_000_000 })
        let id = try first.createTask(TaskDraft(title: "a"))
        let c1 = try first.read { try GRDBTestHelpers.outbox($0) }[0].clocks["title"]!
        let second = try Store.open(path: path, nowMs: { 1_700_000_000_000 })
        XCTAssertEqual(second.nodeID, first.nodeID)
        try second.updateTask(id, ["title": "b"])
        let c2 = try second.read { try GRDBTestHelpers.outbox($0) }[1].clocks["title"]!
        XCTAssertGreaterThan(c2, c1)
    }

    func testPostponeAndReschedule() throws {
        let s = try store()
        let id = try s.createTask(TaskDraft(title: "Коляска", date: today))
        try s.postponeTask(id, today: today)
        XCTAssertEqual(try s.get(.task, id).map(TaskRecord.init)?.date, "2026-09-23")
        XCTAssertEqual(try s.get(.task_move, IDs.taskMove(id, today))?.fields["kind"], "manual")
        try s.rescheduleTask(id, to: "2026-09-30", today: today)
        XCTAssertEqual(try s.moveCount(id), 2)
        try s.rescheduleTask(id, to: "2026-09-25", today: today) // earlier: not a postpone
        XCTAssertEqual(try s.moveCount(id), 2)

        let inbox = try s.createTask(TaskDraft(title: "Когда-нибудь"))
        try s.postponeTask(inbox, today: today)
        XCTAssertEqual(try s.moveCount(inbox), 0)
        XCTAssertEqual(try s.get(.task, inbox).map(TaskRecord.init)?.firstDate, "2026-09-23")
    }

    func testRolloverCountsMissedDaysAndIsIdempotent() throws {
        let s = try store()
        let open = try s.createTask(TaskDraft(title: "Висит", date: "2026-09-19"))
        let done = try s.createTask(TaskDraft(title: "Сделано", date: "2026-09-19"))
        try s.completeTask(done, today: "2026-09-19")
        XCTAssertEqual(try s.runRollover(today: today), 1)
        XCTAssertEqual(try s.moveCount(open), 3)
        XCTAssertEqual(try s.moveCount(done), 0)
        let queued = try s.read { try GRDBTestHelpers.outbox($0) }.count
        XCTAssertEqual(try s.runRollover(today: today), 0)
        XCTAssertEqual(try s.read { try GRDBTestHelpers.outbox($0) }.count, queued)
    }

    func testRoutineVersioning() throws {
        let s = try store()
        let lunch = try s.createRoutine(RoutineDraft(title: "Пообедать"), today: "2026-09-20")
        var d = RoutineDraft(title: "Пообедать без телефона")
        try s.editRoutine(lunch, d, today: today)
        XCTAssertEqual(try s.routinesOn("2026-09-21")[lunch]?.title, "Пообедать")
        XCTAssertEqual(try s.routinesOn(today)[lunch]?.title, "Пообедать без телефона")

        try s.setRoutineCheck(lunch, date: today, status: .done)
        d.title = "Обед"
        try s.editRoutine(lunch, d, today: today) // today is marked: applies from tomorrow
        XCTAssertEqual(try s.routinesOn(today)[lunch]?.title, "Пообедать без телефона")
        XCTAssertEqual(try s.routinesOn("2026-09-23")[lunch]?.title, "Обед")

        try s.archiveRoutine(lunch, today: "2026-09-24")
        XCTAssertNil(try s.routinesOn("2026-09-24")[lunch])
        XCTAssertNotNil(try s.routinesOn("2026-09-23")[lunch])
    }

    func testDayViewSectionsAndNow() throws {
        let s = try store()
        _ = try s.createRoutine(RoutineDraft(title: "Пообедать") .with { $0.timing = Timing(kind: .exact, time: "13:00") }, today: today)
        _ = try s.createRoutine(RoutineDraft(title: "Душ").with { $0.timing = Timing(kind: .part, part: .morning) }, today: today)
        var call = TaskDraft(title: "Созвон", date: today)
        call.timing = Timing(kind: .exact, time: "15:00")
        let callID = try s.createTask(call)
        let lamp = try s.createTask(TaskDraft(title: "Лампочка", date: today))
        try s.completeTask(lamp, today: today)
        _ = try s.createTask(TaskDraft(title: "Завтра", date: "2026-09-23"))

        let day = try s.loadDay(today, now: nowLocal)
        XCTAssertEqual(day.items.map(\.title), ["Лампочка", "Душ", "Пообедать", "Созвон"])
        XCTAssertEqual(day.items.map(\.section), [.anytime, .morning, .day, .day])
        XCTAssertEqual(day.done, 1)
        XCTAssertEqual(day.total, 4)
        XCTAssertEqual(day.items.first { $0.refID == callID }?.score, 100)
        XCTAssertEqual(pickNow(day).first?.refID, callID)
    }

    func testStats() throws {
        let s = try store()
        let r = try s.createRoutine(RoutineDraft(title: "Вода"), today: "2026-09-19")
        for d in ["2026-09-19", "2026-09-20", "2026-09-21"] { try s.setRoutineCheck(r, date: d, status: .done) }
        let stats = try s.loadStats(today: today)
        XCTAssertEqual(stats.streak, 3)
        XCTAssertEqual(stats.totalDone, 3)
        XCTAssertEqual(stats.heatmap.count, 371)
    }
}

extension RoutineDraft {
    func with(_ edit: (inout RoutineDraft) -> Void) -> RoutineDraft {
        var copy = self
        edit(&copy)
        return copy
    }
}
