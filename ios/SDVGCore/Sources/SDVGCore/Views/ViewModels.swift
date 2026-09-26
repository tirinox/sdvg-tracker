import Foundation
import GRDB

// Screen models built from the local store. Mirrors web/src/app/views.ts.

public enum DaySection: String, CaseIterable, Sendable {
    case anytime, morning, day, evening
}

public struct DayItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case task, routine }

    public var id: String { "\(kind.rawValue):\(refID)" }
    public var kind: Kind
    public var refID: String
    public var title: String
    public var emoji: String?
    public var color: Int
    public var timing: Timing
    public var durationMin: Int?
    public var section: DaySection
    public var done: Bool
    public var skipped: Bool
    public var moves: Int
    public var attention: Int
    public var deadline: Rules.DeadlineStatus
    public var deadlineDate: LocalDate?
    public var deadlineTime: LocalTime?
    public var score: Int
    public var reasons: [Rules.ScoreReason]
    public var sortKey: String
}

public func sectionOf(_ t: Timing, _ s: Settings) -> DaySection {
    switch t.kind {
    case .part: return t.part.map { DaySection(rawValue: $0.rawValue)! } ?? .anytime
    case .exact: return t.time.map { DaySection(rawValue: Dates.partOfDay("2000-01-01T\($0)", s).rawValue)! } ?? .anytime
    case .none: return .anytime
    }
}

/// Open first; timed ones by time, then the rest by manual order.
func compareItems(_ a: DayItem, _ b: DayItem) -> Bool {
    let ad = a.done || a.skipped, bd = b.done || b.skipped
    if ad != bd { return !ad }
    let at = a.timing.time, bt = b.timing.time
    if let at, let bt, at != bt { return at < bt }
    if (at == nil) != (bt == nil) { return at == nil }
    return a.sortKey < b.sortKey
}

public struct DayView: Sendable {
    public var date: LocalDate
    public var items: [DayItem]
    public var done: Int { items.filter(\.done).count }
    public var total: Int { items.filter { !$0.skipped }.count }

    public func items(in section: DaySection) -> [DayItem] { items.filter { $0.section == section } }
}

public struct StatsView: Sendable {
    public struct Cell: Hashable, Sendable {
        public var date: LocalDate
        public var count: Int
        /// -1 for days after today.
        public var level: Int
    }

    public var streak: Int
    public var totalDone: Int
    public var record: Rules.DayRecord
    public var heatmap: [Cell]
}

public struct RoutineListItem: Identifiable, Sendable {
    public var id: String { version.routineID }
    public var version: RoutineVersionRecord
    /// Set when an edit takes effect after today.
    public var pendingFrom: LocalDate?
    public var section: DaySection
    public var sortKey: String
}

extension Store {
    func moveCounts(_ db: Database) throws -> [String: Int] {
        let rows = try GRDB.Row.fetchAll(db, sql: "SELECT task_id, count(*) AS n FROM task_move GROUP BY task_id")
        return Dictionary(uniqueKeysWithValues: rows.compactMap { r in (r["task_id"] as String?).map { ($0, r["n"] as Int) } })
    }

    func taskItem(_ t: TaskRecord, moves: Int, now: LocalDateTime, _ s: Settings, today: LocalDate) -> DayItem {
        let deadline = Rules.deadlineStatus(
            now: now, dayStartHour: s.dayStartHour,
            createdOn: t.createdAt.flatMap { Dates.localDate(ofISO: $0) } ?? today,
            deadlineDate: t.deadlineDate, deadlineTime: t.deadlineTime, done: t.doneOn != nil)
        let open = t.date == today && t.doneOn == nil
        let (score, reasons) = open
            ? Rules.nowScore(now: now, settings: s, timing: t.timing, deadline: deadline, moves: moves)
            : (0, [])
        return DayItem(
            kind: .task, refID: t.id, title: t.title, emoji: t.emoji, color: t.color, timing: t.timing,
            durationMin: t.durationMin, section: sectionOf(t.timing, s), done: t.doneOn != nil, skipped: false,
            moves: moves, attention: Rules.attentionLevel(moves: moves, thresholds: s.attentionThresholds),
            deadline: deadline, deadlineDate: t.deadlineDate, deadlineTime: t.deadlineTime,
            score: score, reasons: reasons, sortKey: t.sortKey)
    }

    public func loadDay(_ date: LocalDate, now: LocalDateTime) throws -> DayView {
        try read { db in
            let s = try Rows.settings(db)
            let today = Dates.logicalDay(now, dayStartHour: s.dayStartHour)
            let status = Dictionary(
                try Rows.fetch(.routine_check, db, where: "date = ?", [date]).map {
                    ($0.fields["routine_id"]?.string ?? "", $0.fields["status"]?.string.flatMap(CheckStatus.init))
                }, uniquingKeysWith: { $1 })
            let sortKeys = Dictionary(
                try Rows.fetch(.routine, db).map { ($0.id, $0.fields["sort_key"]?.string ?? "") }, uniquingKeysWith: { $1 })

            var items: [DayItem] = []
            for v in Rules.routinesForDay(date, try routineVersions(db)).values {
                let st = status[v.routineID] ?? nil
                let (score, reasons) = date == today && st == nil
                    ? Rules.nowScore(now: now, settings: s, timing: v.timing, deadline: .none, moves: 0)
                    : (0, [])
                items.append(DayItem(
                    kind: .routine, refID: v.routineID, title: v.title, emoji: v.emoji, color: v.color, timing: v.timing,
                    durationMin: v.durationMin, section: sectionOf(v.timing, s), done: st == .done, skipped: st == .skipped,
                    moves: 0, attention: 0, deadline: .none, deadlineDate: nil, deadlineTime: nil,
                    score: score, reasons: reasons, sortKey: sortKeys[v.routineID] ?? ""))
            }
            let moves = try moveCounts(db)
            for t in try Rows.fetch(.task, db, where: "date = ? OR done_on = ?", [date, date]).map(TaskRecord.init) {
                // A task done on another day but still dated here belongs to that other day.
                if t.deleted || (t.doneOn != nil && t.doneOn != date) { continue }
                items.append(taskItem(t, moves: moves[t.id] ?? 0, now: now, s, today: today))
            }
            let order = DaySection.allCases
            items.sort {
                let a = order.firstIndex(of: $0.section)!, b = order.firstIndex(of: $1.section)!
                return a != b ? a < b : compareItems($0, $1)
            }
            return DayView(date: date, items: items)
        }
    }

    /// Done/skipped per day, by the day_stats rule in one pass.
    private static func statsByDay(_ db: Database) throws -> [LocalDate: Rules.DayStats] {
        var byDay: [LocalDate: Rules.DayStats] = [:]
        for d in try String.fetchAll(db, sql: "SELECT done_on FROM task WHERE done_on IS NOT NULL") {
            byDay[d, default: .init()].done += 1
        }
        for r in try GRDB.Row.fetchAll(db, sql: "SELECT date, json_extract(fields, '$.status') AS status FROM routine_check") {
            guard let d: String = r["date"], let st: String = r["status"] else { continue }
            if st == "done" { byDay[d, default: .init()].done += 1 }
            if st == "skipped" { byDay[d, default: .init()].skipped += 1 }
        }
        return byDay
    }

    public func loadRecord(today: LocalDate) throws -> Rules.DayRecord {
        try read { Rules.dayRecord(today: today, days: try Self.statsByDay($0)) }
    }

    /// True once per day on this device: when today's record is broken and it was not celebrated yet.
    /// Marks the day as celebrated.
    public func claimRecordCelebration(_ record: Rules.DayRecord, today: LocalDate) throws -> Bool {
        guard record.broken else { return false }
        return try writer.write { db in
            if try Meta.get(db, "record_celebrated")?.string == today { return false }
            try Meta.set(db, "record_celebrated", .string(today))
            return true
        }
    }

    public func loadStats(today: LocalDate) throws -> StatsView {
        try read { db in
            let s = try Rows.settings(db)
            let byDay = try Self.statsByDay(db)
            let grid = Rules.heatmapGrid(today: today)
            let past = grid.filter { $0 <= today }
            let levels = Rules.heatmapLevels(past.map { byDay[$0]?.done ?? 0 })
            let cells = grid.enumerated().map { i, d in
                StatsView.Cell(date: d, count: byDay[d]?.done ?? 0, level: d <= today ? levels[i] : -1)
            }
            return StatsView(
                streak: Rules.streak(today: today, days: byDay, minDone: s.streakMinDone),
                totalDone: byDay.values.reduce(0) { $0 + $1.done },
                record: Rules.dayRecord(today: today, days: byDay),
                heatmap: cells)
        }
    }

    public func loadInbox(now: LocalDateTime) throws -> [DayItem] {
        try read { db in
            let s = try Rows.settings(db)
            let today = Dates.logicalDay(now, dayStartHour: s.dayStartHour)
            let moves = try moveCounts(db)
            return try Rows.fetch(.task, db, where: "date IS NULL AND done_on IS NULL").map(TaskRecord.init)
                .filter { !$0.deleted }
                .map { taskItem($0, moves: moves[$0.id] ?? 0, now: now, s, today: today) }
                .sorted(by: compareItems)
        }
    }

    /// Every task as history for title suggestions; see Rules.titleHistory.
    public func loadTitleHistory(today: LocalDate) throws -> [Rules.TitleGroup] {
        let tasks = try read { db in try Rows.fetch(.task, db).map(TaskRecord.init) }
        return Rules.titleHistory(tasks.map { t in
            // Only open tasks are dated by creation, and parsing timestamps is the slow part.
            let open = t.doneOn == nil && !t.deleted
            return Rules.HistoryTask(
                id: t.id, title: t.title, emoji: t.emoji, color: t.color, durationMin: t.durationMin,
                doneOn: t.doneOn, deleted: t.deleted,
                createdOn: open ? t.createdAt.flatMap { Dates.localDate(ofISO: $0) } ?? today : today)
        }, today: today)
    }

    public func loadRoutines(today: LocalDate) throws -> [RoutineListItem] {
        try read { db in
            let s = try Rows.settings(db)
            var latest: [String: RoutineVersionRecord] = [:]
            for v in try routineVersions(db) {
                if let cur = latest[v.routineID], (cur.effectiveFrom, cur.hlc) >= (v.effectiveFrom, v.hlc) { continue }
                latest[v.routineID] = v
            }
            let sortKeys = Dictionary(
                try Rows.fetch(.routine, db).map { ($0.id, $0.fields["sort_key"]?.string ?? "") }, uniquingKeysWith: { $1 })
            let order = DaySection.allCases
            return latest.values.filter { !$0.archived }.map {
                RoutineListItem(
                    version: $0, pendingFrom: $0.effectiveFrom > today ? $0.effectiveFrom : nil,
                    section: sectionOf($0.timing, s), sortKey: sortKeys[$0.routineID] ?? "")
            }.sorted {
                let a = order.firstIndex(of: $0.section)!, b = order.firstIndex(of: $1.section)!
                if a != b { return a < b }
                let at = $0.version.timing.time ?? "", bt = $1.version.timing.time ?? ""
                return at != bt ? at < bt : $0.sortKey < $1.sortKey
            }
        }
    }
}

/// Top items for the "Now" screen: highest score first, topped up with the next open items.
public func pickNow(_ day: DayView, max: Int = 7, min: Int = 5) -> [DayItem] {
    let open = day.items.filter { !$0.done && !$0.skipped }
    let ranked = open.filter { $0.score > 0 }
        .sorted { $0.score != $1.score ? $0.score > $1.score : compareItems($0, $1) }
        .prefix(max)
    let rest = open.filter { item in !ranked.contains { $0.id == item.id } }
    return Array(ranked) + rest.prefix(Swift.max(0, min - ranked.count))
}
