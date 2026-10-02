import Foundation
import XCTest

@testable import SDVGCore

private struct FixtureVersion: VersionRef {
    var id: String
    var routineID: String
    var effectiveFrom: LocalDate
    var weekdays: Int
    var archived: Bool
    var hlc: String
}

private func settings(_ v: JSONValue?) -> Settings { Settings(v?.object ?? [:]) }

private func versions(_ i: JSONValue) -> [FixtureVersion] {
    i["versions"]!.array!.map {
        FixtureVersion(
            id: $0["id"]!.string!, routineID: $0["routine_id"]!.string!, effectiveFrom: $0["effective_from"]!.string!,
            weekdays: $0["weekdays"]!.int!, archived: $0["archived"]!.bool!, hlc: $0["hlc"]!.string!)
    }
}

private func timing(_ i: JSONValue) -> Timing {
    Timing([
        "time_kind": i["time_kind"] ?? "none", "part_of_day": i["part_of_day"] ?? nil, "time": i["time"] ?? nil,
    ])
}

/// A list item of item_order / now_pick: only what ordering looks at.
private func orderItem(_ j: JSONValue) -> DayItem {
    DayItem(
        kind: .task, refID: j["id"]!.string!, title: "", emoji: nil, color: 0,
        timing: j["time"]?.string.map { Timing(kind: .exact, time: $0) } ?? Timing(kind: .none),
        durationMin: nil, priority: Priority(j["priority"]), section: .anytime,
        done: j["done"]!.bool!, skipped: j["skipped"]!.bool!, moves: 0, attention: 0, deadline: .none,
        deadlineDate: nil, deadlineTime: nil, score: j["score"]?.int ?? 0, reasons: [], sortKey: j["sort_key"]!.string!)
}

/// One adapter per shared/domain-fixtures file: fixture input -> implementation -> expect shape.
private let runners: [String: @Sendable (JSONValue) -> JSONValue] = [
    "logical_day": { i in
        ["date": .string(Dates.logicalDay(i["now"]!.string!, dayStartHour: i["day_start_hour"]!.int!))]
    },
    "part_of_day": { i in
        ["part": .string(Dates.partOfDay(i["now"]!.string!, settings(i["settings"])).rawValue)]
    },
    "day_end": { i in
        let now = i["now"]!.string!, start = i["day_start_hour"]!.int!
        let endsAt = Dates.dayEnd(Dates.logicalDay(now, dayStartHour: start), dayStartHour: start)
        let left = Dates.minutesBetween(now, endsAt)
        return ["ends_at": .string(endsAt), "minutes_left": .int(left),
                "level": .string(Dates.dayEndLevel(secondsLeft: left * 60).rawValue)]
    },
    "routines_for_day": { i in
        let picked = Rules.routinesForDay(i["date"]!.string!, versions(i))
        return ["versions": .object(picked.mapValues { .string($0.id) })]
    },
    "routine_adherence": { i in
        let checks = i["checks"]!.array!.map {
            (routineID: $0["routine_id"]!.string!, date: $0["date"]!.string!, status: $0["status"]?.string.flatMap(CheckStatus.init))
        }
        let result = Rules.routineAdherence(
            today: i["today"]!.string!, versions: versions(i), checks: checks, warnBelow: i["warn_below"]!.int!)
        return ["routines": .object(result.mapValues { a in
            ["from": a.from.map(JSONValue.string) ?? .null, "done": .int(a.done), "total": .int(a.total),
             "percent": a.percent.map(JSONValue.int) ?? .null, "warning": .bool(a.warning)]
        })]
    },
    "auto_rollover": { i in
        let tasks = i["tasks"]!.array!.map {
            Rules.RolloverTask(id: $0["id"]!.string!, date: $0["date"]?.string, doneOn: $0["done_on"]?.string, deleted: $0["deleted"]!.bool!)
        }
        let plan = Rules.planRollover(today: i["today"]!.string!, tasks: tasks)
        let moves: [JSONValue] = plan.moves.map {
            ["id": .string($0.id), "task_id": .string($0.taskID), "from_date": .string($0.fromDate),
             "to_date": .string($0.toDate), "kind": .string($0.kind)]
        }
        return ["new_moves": .array(moves), "task_dates": .object(plan.dates.mapValues { .string($0) })]
    },
    "attention_level": { i in
        ["level": .int(Rules.attentionLevel(moves: i["moves"]!.int!, thresholds: i["thresholds"]!.array!.map { $0.int! }))]
    },
    "celebration_level": { i in ["level": .int(Rules.celebrationLevel(moves: i["moves"]!.int!))] },
    "deadline_status": { i in
        let status = Rules.deadlineStatus(
            now: i["now"]!.string!, dayStartHour: i["day_start_hour"]!.int!, createdOn: i["created_on"]!.string!,
            deadlineDate: i["deadline_date"]?.string, deadlineTime: i["deadline_time"]?.string, done: i["done"]!.bool!)
        return ["status": .string(status.rawValue)]
    },
    "day_stats": { i in
        let s = Rules.dayStats(
            date: i["date"]!.string!,
            taskDoneOn: i["tasks"]!.array!.map { $0["done_on"]?.string },
            checks: i["routine_checks"]!.array!.map { ($0["date"]!.string!, $0["status"]?.string.flatMap(CheckStatus.init)) })
        return ["done": .int(s.done), "skipped": .int(s.skipped)]
    },
    "streak": { i in
        let days = i["days"]!.object!.mapValues { Rules.DayStats(done: $0["done"]!.int!, skipped: $0["skipped"]!.int!) }
        return ["streak": .int(Rules.streak(today: i["today"]!.string!, days: days, minDone: i["streak_min_done"]!.int!))]
    },
    "day_record": { i in
        let days = i["days"]!.object!.mapValues { Rules.DayStats(done: $0["done"]!.int!, skipped: $0["skipped"]!.int!) }
        let r = Rules.dayRecord(today: i["today"]!.string!, days: days)
        return ["best_date": r.bestDate.map(JSONValue.string) ?? .null, "best_done": .int(r.bestDone),
                "today_done": .int(r.todayDone), "to_beat": .int(r.toBeat), "broken": .bool(r.broken)]
    },
    "now_score": { i in
        let item = i["item"]!
        let r = Rules.nowScore(
            now: i["now"]!.string!, settings: settings(i["settings"]), timing: timing(item),
            deadline: Rules.DeadlineStatus(rawValue: item["deadline_status"]!.string!)!, moves: item["moves"]!.int!)
        return ["score": .int(r.score), "reasons": .array(r.reasons.map { .string($0.rawValue) })]
    },
    "item_order": { i in
        ["order": .array(i["items"]!.array!.map(orderItem).sorted(by: compareItems).map { .string($0.refID) })]
    },
    "now_pick": { i in
        let day = DayView(date: "", items: i["items"]!.array!.map(orderItem))
        return ["ids": .array(pickNow(day, max: i["max"]!.int!, min: i["min"]!.int!).map { .string($0.refID) })]
    },
    "heatmap_levels": { i in
        ["levels": .array(Rules.heatmapLevels(i["counts"]!.array!.map { $0.int! }).map(JSONValue.int))]
    },
    "heatmap_grid": { i in
        let days = Rules.heatmapGrid(today: i["today"]!.string!)
        return ["first": .string(days.first!), "last": .string(days.last!), "days": .int(days.count)]
    },
    "title_suggestions": { i in
        let tasks = i["tasks"]!.array!.map {
            Rules.HistoryTask(
                id: $0["id"]!.string!, title: $0["title"]!.string!, emoji: $0["emoji"]?.string, color: $0["color"]!.int!,
                durationMin: $0["duration_min"]?.int, doneOn: $0["done_on"]?.string, deleted: $0["deleted"]!.bool!,
                createdOn: $0["created_on"]!.string!)
        }
        let list = Rules.suggestTitles(Rules.titleHistory(tasks, today: i["today"]!.string!), query: i["query"]!.string!, limit: i["limit"]!.int!)
        return ["suggestions": .array(list.map {
            ["title": .string($0.title), "emoji": JSONValue($0.emoji), "color": .int($0.color),
             "duration_min": JSONValue($0.durationMin), "uses": .int($0.uses)]
        })]
    },
]

final class DomainFixtureTests: XCTestCase {
    func testEveryFixtureFileHasARunner() throws {
        let kinds = try sharedFiles("domain-fixtures").map { String($0.dropLast(5)) }
        XCTAssertEqual(runners.keys.sorted(), kinds)
    }

    func testDomainFixtures() throws {
        for (kind, run) in runners {
            for c in try loadShared("domain-fixtures/\(kind).json")["cases"]!.array! {
                XCTAssertEqual(run(c["input"]!), c["expect"]!, "\(kind): \(c["name"]!.string!)")
            }
        }
    }

    func testDateArithmetic() {
        XCTAssertEqual(Dates.addDays("2024-02-28", 1), "2024-02-29")
        XCTAssertEqual(Dates.addDays("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(Dates.addDays("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(Dates.weekdayIndex("2026-09-21"), 0) // Monday
        XCTAssertEqual(Dates.daysBetween("2025-09-22", "2026-09-22"), 365)
    }
}
