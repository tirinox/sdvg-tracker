import Foundation
import GRDB

// Screen models built from the local store. Mirrors web/src/app/views.ts.

public enum DaySection: String, CaseIterable, Sendable {
    case anytime, morning, day, evening
}

/// A group on the Day screen: open items by part of the day, then everything done or skipped.
public enum DayGroup: Hashable, Sendable {
    case section(DaySection)
    case done
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
    public var priority: Priority = .normal
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
    /// Its time has come today (Rules.hasStarted): only then does high priority lead Now.
    public var started = true
    public var sortKey: String
    /// Routines only: how regularly it is done as of today.
    public var adherence: Rules.Adherence? = nil
    /// Routines only: its last days mark by mark, and its streak.
    public var history: Rules.RoutineHistory? = nil

    var closed: Bool { done || skipped }
}

public func sectionOf(_ t: Timing, _ s: Settings) -> DaySection {
    switch t.kind {
    case .part: return t.part.map { DaySection(rawValue: $0.rawValue)! } ?? .anytime
    case .exact: return t.time.map { DaySection(rawValue: Dates.partOfDay("2000-01-01T\($0)", s).rawValue)! } ?? .anytime
    case .none: return .anytime
    }
}

/// Open first, then by priority; untimed before timed ones by time, then by manual order
/// (shared/domain-fixtures/item_order.json).
func compareItems(_ a: DayItem, _ b: DayItem) -> Bool {
    let ad = a.done || a.skipped, bd = b.done || b.skipped
    if ad != bd { return !ad }
    if a.priority != b.priority { return a.priority.rank < b.priority.rank }
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

    /// Non-empty groups in screen order; the items keep the day's order.
    public var groups: [(group: DayGroup, items: [DayItem])] {
        let open = items.filter { !$0.closed }
        let all = DaySection.allCases.map { s in (DayGroup.section(s), open.filter { $0.section == s }) }
            + [(DayGroup.done, items.filter(\.closed))]
        return all.filter { !$0.1.isEmpty }.map { (group: $0.0, items: $0.1) }
    }
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
    public var adherence: Rules.Adherence
    public var history: Rules.RoutineHistory
}

extension Store {
    /// The marks of every routine, or of one.
    func routineChecks(_ db: Database, routineID: String? = nil) throws -> [Rules.CheckRef] {
        let sql = "SELECT routine_id, date, json_extract(fields, '$.status') AS status FROM routine_check"
        let rows = try routineID.map { try GRDB.Row.fetchAll(db, sql: sql + " WHERE routine_id = ?", arguments: [$0]) }
            ?? GRDB.Row.fetchAll(db, sql: sql)
        return rows.compactMap { r in
            guard let rid: String = r["routine_id"], let d: String = r["date"] else { return nil }
            return (rid, d, (r["status"] as String?).flatMap(CheckStatus.init))
        }
    }

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
            durationMin: t.durationMin, priority: t.priority, section: sectionOf(t.timing, s), done: t.doneOn != nil, skipped: false,
            moves: moves, attention: Rules.attentionLevel(moves: moves, thresholds: s.attentionThresholds),
            deadline: deadline, deadlineDate: t.deadlineDate, deadlineTime: t.deadlineTime,
            score: score, reasons: reasons, started: Rules.hasStarted(now: now, settings: s, timing: t.timing),
            sortKey: t.sortKey)
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

            let versions = try routineVersions(db)
            let checks = try routineChecks(db)
            let adherence = Rules.routineAdherence(today: today, versions: versions, checks: checks, warnBelow: s.routineWarnBelow)
            let history = Rules.routineHistory(today: today, versions: versions, checks: checks)
            var items: [DayItem] = []
            for v in Rules.routinesForDay(date, versions).values {
                let st = status[v.routineID] ?? nil
                let (score, reasons) = date == today && st == nil
                    ? Rules.nowScore(now: now, settings: s, timing: v.timing, deadline: .none, moves: 0)
                    : (0, [])
                items.append(DayItem(
                    kind: .routine, refID: v.routineID, title: v.title, emoji: v.emoji, color: v.color, timing: v.timing,
                    durationMin: v.durationMin, priority: v.priority, section: sectionOf(v.timing, s), done: st == .done, skipped: st == .skipped,
                    moves: 0, attention: 0, deadline: .none, deadlineDate: nil, deadlineTime: nil,
                    score: score, reasons: reasons, started: Rules.hasStarted(now: now, settings: s, timing: v.timing),
                    sortKey: sortKeys[v.routineID] ?? "", adherence: adherence[v.routineID],
                    history: history[v.routineID]))
            }
            let moves = try moveCounts(db)
            for t in try Rows.fetch(.task, db, where: "date = ? OR done_on = ?", [date, date]).map(TaskRecord.init) {
                // A task done on another day but still dated here belongs to that other day.
                if t.deleted || (t.doneOn != nil && t.doneOn != date) { continue }
                items.append(taskItem(t, moves: moves[t.id] ?? 0, now: now, s, today: today))
            }
            // Done and skipped go after every open item, whatever part of the day they were planned for.
            let order = DaySection.allCases
            items.sort {
                if $0.closed != $1.closed { return !$0.closed }
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

    /// Adherence of one routine, for its editor; nil for a routine without versions.
    /// With `doneOn`, what it becomes once that day is marked done.
    public func loadRoutineAdherence(_ routineID: String, today: LocalDate, doneOn: LocalDate? = nil) throws -> Rules.Adherence? {
        try read { db in
            let versions = try routineVersions(db, routineID: routineID)
            var checks = try routineChecks(db, routineID: routineID)
            // A later mark of the same day wins.
            if let doneOn { checks.append((routineID, doneOn, .done)) }
            return Rules.routineAdherence(
                today: today, versions: versions, checks: checks, warnBelow: try Rows.settings(db).routineWarnBelow)[routineID]
        }
    }

    /// Day by day history and streak of one routine, for its editor; nil for a routine without versions.
    public func loadRoutineHistory(_ routineID: String, today: LocalDate) throws -> Rules.RoutineHistory? {
        try read { db in
            Rules.routineHistory(
                today: today, versions: try routineVersions(db, routineID: routineID),
                checks: try routineChecks(db, routineID: routineID))[routineID]
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

    /// How many live tasks wear each of the 12 palette colors, for the color picker.
    public func loadColorUses() throws -> [Int] {
        var uses = [Int](repeating: 0, count: 12)
        for t in try read({ db in try Rows.fetch(.task, db).map(TaskRecord.init) }) where !t.deleted {
            uses[(t.color % 12 + 12) % 12] += 1
        }
        return uses
    }

    /// What the title of a new task is checked against; see Rules.checkTitle.
    public func loadListed(today: LocalDate) throws -> [Rules.ListedItem] {
        try read { db in
            let tasks = try Rows.fetch(.task, db, where: "done_on IS NULL OR done_on = ?", [today]).map(TaskRecord.init)
            var items = tasks.filter { !$0.deleted }.map { t in
                Rules.ListedItem(kind: .task, id: t.id, title: t.title, emoji: t.emoji, color: t.color, date: t.date,
                                 doneToday: t.doneOn != nil)
            }
            let doneToday = Set(try Rows.fetch(.routine_check, db, where: "date = ?", [today]).compactMap {
                $0.fields["status"]?.string == CheckStatus.done.rawValue ? $0.fields["routine_id"]?.string : nil
            })
            for v in latestVersions(try routineVersions(db)).values.sorted(by: { $0.routineID < $1.routineID }) where !v.archived {
                items.append(Rules.ListedItem(kind: .routine, id: v.routineID, title: v.title, emoji: v.emoji, color: v.color,
                                              doneToday: doneToday.contains(v.routineID)))
            }
            return items
        }
    }

    public func loadRoutines(today: LocalDate) throws -> [RoutineListItem] {
        try read { db in
            let s = try Rows.settings(db)
            let versions = try routineVersions(db)
            let checks = try routineChecks(db)
            let adherence = Rules.routineAdherence(today: today, versions: versions, checks: checks, warnBelow: s.routineWarnBelow)
            let history = Rules.routineHistory(today: today, versions: versions, checks: checks)
            let latest = latestVersions(versions)
            let sortKeys = Dictionary(
                try Rows.fetch(.routine, db).map { ($0.id, $0.fields["sort_key"]?.string ?? "") }, uniquingKeysWith: { $1 })
            let order = DaySection.allCases
            return latest.values.filter { !$0.archived }.map {
                RoutineListItem(
                    version: $0, pendingFrom: $0.effectiveFrom > today ? $0.effectiveFrom : nil,
                    section: sectionOf($0.timing, s), sortKey: sortKeys[$0.routineID] ?? "",
                    adherence: adherence[$0.routineID] ?? .init(), history: history[$0.routineID] ?? .init())
            }.sorted {
                let a = order.firstIndex(of: $0.section)!, b = order.firstIndex(of: $1.section)!
                if a != b { return a < b }
                if $0.version.priority != $1.version.priority { return $0.version.priority.rank < $1.version.priority.rank }
                let at = $0.version.timing.time ?? "", bt = $1.version.timing.time ?? ""
                return at != bt ? at < bt : $0.sortKey < $1.sortKey
            }
        }
    }
}

/// High priority leads the Now screen only once its time has come; before that it ranks as normal.
/// The latest version of every routine, archived ones included, edits that start after today too.
private func latestVersions(_ versions: [RoutineVersionRecord]) -> [String: RoutineVersionRecord] {
    var latest: [String: RoutineVersionRecord] = [:]
    for v in versions {
        if let cur = latest[v.routineID], (cur.effectiveFrom, cur.hlc) >= (v.effectiveFrom, v.hlc) { continue }
        latest[v.routineID] = v
    }
    return latest
}

private func nowRank(_ i: DayItem) -> Int {
    i.priority == .high && !i.started ? Priority.normal.rank : i.priority.rank
}

/// Top items for the "Now" screen (shared/domain-fixtures/now_pick.json): scored items and
/// high-priority ones whose time has come, by priority and score, topped up with the next open items.
public func pickNow(_ day: DayView, max: Int = 7, min: Int = 5) -> [DayItem] {
    let open = day.items.filter { !$0.done && !$0.skipped }
    let ranked = open.filter { $0.score > 0 || ($0.priority == .high && $0.started) }
        .sorted {
            if nowRank($0) != nowRank($1) { return nowRank($0) < nowRank($1) }
            return $0.score != $1.score ? $0.score > $1.score : compareItems($0, $1)
        }
        .prefix(max)
    let rest = open.filter { item in !ranked.contains { $0.id == item.id } }
    return Array(ranked) + rest.prefix(Swift.max(0, min - ranked.count))
}
