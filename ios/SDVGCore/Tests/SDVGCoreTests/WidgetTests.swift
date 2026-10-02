import Foundation
import XCTest

@testable import SDVGCore

final class WidgetTests: XCTestCase {
    /// Tuesday 14:40 — the "day" part of the day.
    let now = "2026-09-22T14:40"
    let day = "2026-09-22"

    override func setUp() {
        super.setUp()
        L10n.current = .ru
    }

    private func filled() throws -> Store {
        let s = try Store.open(path: nil)
        var call = TaskDraft(title: "Созвон", date: day)
        call.timing = Timing(kind: .exact, time: "15:00")
        try s.createTask(call)
        var evening = TaskDraft(title: "Почитать", date: day)
        evening.timing = Timing(kind: .part, part: .evening)
        try s.createTask(evening)
        var stuck = TaskDraft(title: "Коляска", date: day)
        stuck.deadlineDate = Dates.addDays(day, -1)
        let stuckID = try s.createTask(stuck)
        for _ in 0..<3 { try s.postponeTask(stuckID, today: day) }
        try s.updateTask(stuckID, ["date": .string(day)])
        let done = try s.createTask(TaskDraft(title: "Лампочка", date: day))
        try s.completeTask(done, today: day)
        var lunch = RoutineDraft(title: "Пообедать")
        lunch.timing = Timing(kind: .exact, time: "13:00")
        let lunchID = try s.createRoutine(lunch, today: day)
        try s.setRoutineCheck(lunchID, date: day, status: .done)
        var walk = RoutineDraft(title: "Прогулка")
        walk.timing = Timing(kind: .part, part: .day)
        try s.createRoutine(walk, today: day)
        return s
    }

    func testSnapshotRanksAndCounts() throws {
        let snap = try filled().widgetSnapshot(now: now)
        XCTAssertEqual(snap.date, day)
        XCTAssertEqual(snap.done, 2) // lamp + lunch
        XCTAssertEqual(snap.total, 6)
        XCTAssertEqual(snap.progressText, "2/6")
        // Overdue deadline (90) + 3 postpones (24) outranks a call starting in 20 minutes (100).
        XCTAssertEqual(snap.items.map(\.item.title).prefix(2), ["Коляска", "Созвон"])
        XCTAssertFalse(snap.items.contains { $0.item.done })
    }

    func testOneBadgePerItem() throws {
        let snap = try filled().widgetSnapshot(now: now)
        let byTitle = Dictionary(uniqueKeysWithValues: snap.items.map { ($0.item.title, $0) })
        XCTAssertEqual(byTitle["Созвон"]?.badge, "15:00")
        XCTAssertEqual(byTitle["Созвон"]?.badgeKind, .time)
        XCTAssertEqual(byTitle["Коляска"]?.badgeKind, .deadline)
        XCTAssertEqual(byTitle["Коляска"]?.badge, "просрочено")
        XCTAssertEqual(byTitle["Прогулка"]?.badge, nil)
    }

    func testBadgesInEnglish() throws {
        L10n.current = .en
        defer { L10n.current = .ru }
        let snap = try filled().widgetSnapshot(now: now)
        XCTAssertEqual(snap.items.first { $0.item.title == "Коляска" }?.badge, "overdue")
    }

    func testCurrentPartAndNextPart() throws {
        let snap = try filled().widgetSnapshot(now: now)
        XCTAssertEqual(snap.part, .day)
        // Counted: only items of this part. Listed: those plus "anytime" ones as filler.
        XCTAssertEqual(snap.partTotal, 3) // Пообедать, Созвон, Прогулка
        XCTAssertEqual(snap.partDone, 1) // Пообедать
        XCTAssertEqual(snap.partItems.map(\.item.title).sorted(), ["Коляска", "Пообедать", "Прогулка", "Созвон"])
        XCTAssertEqual(snap.nextPart, .evening)
        XCTAssertEqual(snap.nextPartCount, 1) // "Почитать"
    }

    func testFilters() throws {
        let store = try filled()
        let tasks = try store.widgetSnapshot(now: now, filter: .tasks)
        XCTAssertFalse(tasks.items.contains { $0.item.kind == .routine })
        XCTAssertEqual(tasks.total, 4)
        let routines = try store.widgetSnapshot(now: now, filter: .routines)
        XCTAssertEqual(routines.total, 2)
        XCTAssertEqual(routines.done, 1)
    }

    func testProgressTextFollowsTheSetting() throws {
        let store = try filled()
        try store.updateSettings(["show_day_total": false])
        XCTAssertEqual(try store.widgetSnapshot(now: now).progressText, "2")
    }

    func testRecordText() throws {
        let store = try filled()
        XCTAssertNil(try store.widgetSnapshot(now: now).recordText) // no history yet
        let r = try store.createRoutine(RoutineDraft(title: "Вода"), today: "2026-09-19")
        try store.setRoutineCheck(r, date: "2026-09-20", status: .done)
        try store.setRoutineCheck(r, date: "2026-09-21", status: .done)
        XCTAssertEqual(try store.widgetSnapshot(now: now).recordText, "рекорд дня!") // 2 today vs 1 before
    }

    func testRefreshDatesAreFutureAndSorted() throws {
        let store = try filled()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let nowDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 14, minute: 40))!
        let dates = try store.widgetRefreshDates(now: nowDate, calendar: calendar)
        XCTAssertFalse(dates.isEmpty)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertTrue(dates.allSatisfy { $0 > nowDate })
        // The 15:00 call: its -30 point is already past, its start and end are not.
        XCTAssertFalse(dates.contains(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 14, minute: 30))!))
        XCTAssertTrue(dates.contains(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15, minute: 0))!))
        XCTAssertTrue(dates.contains(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 16, minute: 1))!))
        XCTAssertTrue(dates.contains(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 18, minute: 0))!))
    }
}
