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

    func testCopyIsAFreshTaskOnItsOwnDay() throws {
        let s = try store()
        var source = TaskDraft(title: "Полить цветы", date: today)
        source.notes = "и фикус"
        source.emoji = "🪴"
        source.color = 4
        source.timing = Timing(kind: .part, part: .morning)
        source.durationMin = 10
        source.deadlineDate = "2026-09-24"
        source.deadlineTime = "12:00"
        let id = try s.createTask(source)
        try s.postponeTask(id, today: today)
        try s.completeTask(id, today: "2026-09-23")

        let copy = try s.copyTask(source, to: "2026-09-24")
        XCTAssertNotEqual(copy, id)
        let t = try XCTUnwrap(try s.get(.task, copy).map(TaskRecord.init))
        var expected = source
        expected.date = "2026-09-24"
        XCTAssertEqual(TaskDraft(t), expected)
        XCTAssertEqual(t.firstDate, "2026-09-24")
        XCTAssertNil(t.doneOn)
        XCTAssertFalse(t.deleted)
        XCTAssertEqual(try s.moveCount(copy), 0)
        XCTAssertGreaterThan(t.sortKey, try XCTUnwrap(try s.get(.task, id).map(TaskRecord.init)).sortKey)

        let late = try XCTUnwrap(try s.get(.task, try s.copyTask(source, to: "2026-09-25")).map(TaskRecord.init))
        XCTAssertNil(late.deadlineDate)
        XCTAssertNil(late.deadlineTime)
        let original = try XCTUnwrap(try s.get(.task, id).map(TaskRecord.init))
        XCTAssertEqual(original.date, "2026-09-23")
        XCTAssertEqual(original.doneOn, "2026-09-23")
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

    func testRoutineAdherenceOnTheListTheDayAndTheEditor() throws {
        let s = try store()
        let r = try s.createRoutine(RoutineDraft(title: "Зарядка"), today: "2026-09-16")
        try s.setRoutineCheck(r, date: "2026-09-18", status: .done)
        try s.setRoutineCheck(r, date: "2026-09-21", status: .skipped)
        _ = try s.createTask(TaskDraft(title: "Лампочка", date: today))

        // 18 done, 19 and 20 missed, 21 skipped, today not marked yet.
        let listed = try XCTUnwrap(s.loadRoutines(today: today).first).adherence
        XCTAssertEqual(listed, Rules.Adherence(from: "2026-09-18", done: 1, total: 3, warning: true))
        XCTAssertEqual(listed.percent, 33)
        let day = try s.loadDay(today, now: nowLocal)
        XCTAssertEqual(day.items.map(\.title), ["Зарядка", "Лампочка"])
        XCTAssertEqual(day.items.map(\.adherence?.percent), [33, nil])
        XCTAssertEqual(try s.loadRoutineAdherence(r, today: today), listed)

        try s.updateSettings(["routine_warn_below": 30])
        XCTAssertFalse(try s.loadRoutines(today: today)[0].adherence.warning)
        // What a check would make it, before it is written: today, or a missed day counted already.
        let checked = try s.loadRoutineAdherence(r, today: today, doneOn: today)
        let caughtUp = try XCTUnwrap(s.loadRoutineAdherence(r, today: today, doneOn: "2026-09-19"))
        XCTAssertEqual([caughtUp.done, caughtUp.total, caughtUp.percent], [2, 3, 67])
        try s.setRoutineCheck(r, date: today, status: .done)
        let after = try s.loadRoutines(today: today)[0].adherence
        XCTAssertEqual([after.done, after.total, after.percent], [2, 4, 50])
        XCTAssertEqual(checked, after)
    }

    func testListedForTitleCheck() throws {
        let s = try store()
        let yesterday = "2026-09-21"
        _ = try s.createTask(TaskDraft(title: "Во входящих", date: nil))
        _ = try s.createTask(TaskDraft(title: "Через неделю", date: "2026-09-29"))
        let vip = try s.createTask(TaskDraft(title: "Выдать ВИП статус", date: today))
        try s.completeTask(vip, today: today)
        let old = try s.createTask(TaskDraft(title: "Вчерашняя", date: yesterday))
        try s.completeTask(old, today: yesterday)
        try s.deleteTask(try s.createTask(TaskDraft(title: "Удалённая", date: today)))
        let lunch = try s.createRoutine(RoutineDraft(title: "Обед"), today: today)
        let shower = try s.createRoutine(RoutineDraft(title: "Душ"), today: today)
        try s.setRoutineCheck(shower, date: today, status: .done)
        try s.archiveRoutine(try s.createRoutine(RoutineDraft(title: "Старая рутина"), today: yesterday), today: today)

        let listed = try s.loadListed(today: today)
        XCTAssertEqual(Set(listed.map { "\($0.kind) \($0.title) \($0.doneToday)" }), [
            "routine Душ true", "routine Обед false",
            "task Во входящих false", "task Выдать ВИП статус true", "task Через неделю false",
        ])
        guard case .taken(let item) = Rules.checkTitle(listed, title: "обед") else { return XCTFail("обед is taken") }
        XCTAssertEqual(item.id, lunch)
        guard case .doneToday(_, let next) = Rules.checkTitle(listed, title: "Выдать ВИП статус") else {
            return XCTFail("done today")
        }
        XCTAssertEqual(next, "Выдать ВИП статус (1)")
        XCTAssertEqual(Rules.checkTitle(listed, title: "Вчерашняя"), .free(similar: []))
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
        XCTAssertEqual(day.items.map(\.title), ["Душ", "Пообедать", "Созвон", "Лампочка"])
        XCTAssertEqual(day.items.map(\.section), [.morning, .day, .day, .anytime])
        XCTAssertEqual(day.done, 1)
        XCTAssertEqual(day.total, 4)
        XCTAssertEqual(day.items.first { $0.refID == callID }?.score, 100)
        XCTAssertEqual(pickNow(day).first?.refID, callID)
    }

    func testDayGroupsCloseAtTheEnd() throws {
        let s = try store()
        let shower = try s.createRoutine(RoutineDraft(title: "Душ").with { $0.timing = Timing(kind: .part, part: .morning) }, today: today)
        let gym = try s.createRoutine(RoutineDraft(title: "Спортзал").with { $0.timing = Timing(kind: .part, part: .evening) }, today: today)
        _ = try s.createRoutine(RoutineDraft(title: "Пообедать").with { $0.timing = Timing(kind: .exact, time: "13:00") }, today: today)
        var call = TaskDraft(title: "Созвон", date: today)
        call.timing = Timing(kind: .exact, time: "08:30")
        let callID = try s.createTask(call)
        _ = try s.createTask(TaskDraft(title: "Лампочка", date: today))
        try s.setRoutineCheck(gym, date: today, status: .skipped)
        try s.setRoutineCheck(shower, date: today, status: .done)
        try s.completeTask(callID, today: today)

        let groups = try s.loadDay(today, now: nowLocal).groups
        XCTAssertEqual(groups.map(\.group), [.section(.anytime), .section(.day), .done])
        XCTAssertEqual(groups.map { $0.items.map(\.title) }, [["Лампочка"], ["Пообедать"], ["Душ", "Созвон", "Спортзал"]])
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
