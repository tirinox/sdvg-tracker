import Foundation
import GRDB

// User intents as local writes; each action is one outbox batch. Mirrors web/src/db/actions.ts.

public struct TaskDraft: Sendable, Equatable {
    public var title: String
    public var notes = ""
    public var emoji: String?
    public var color = 7
    public var date: LocalDate?
    public var timing = Timing(kind: .none)
    public var durationMin: Int?
    public var deadlineDate: LocalDate?
    public var deadlineTime: LocalTime?

    public init(title: String = "", date: LocalDate? = nil) {
        self.title = title
        self.date = date
    }

    public init(_ t: TaskRecord) {
        title = t.title
        notes = t.notes
        emoji = t.emoji
        color = t.color
        date = t.date
        timing = t.timing
        durationMin = t.durationMin
        deadlineDate = t.deadlineDate
        deadlineTime = t.deadlineTime
    }

    /// Everything except `date`, which goes through reschedule.
    var contentFields: Fields {
        var f: Fields = [
            "title": .string(title), "notes": .string(notes), "emoji": JSONValue(emoji), "color": .int(color),
            "duration_min": JSONValue(durationMin), "deadline_date": JSONValue(deadlineDate),
            "deadline_time": JSONValue(deadlineDate == nil ? nil : deadlineTime),
        ]
        f.merge(timing.fields) { $1 }
        return f
    }
}

public struct RoutineDraft: Sendable, Equatable {
    public var title: String
    public var emoji: String?
    public var color = 4
    public var timing = Timing(kind: .none)
    public var durationMin: Int?
    public var weekdays = 127

    public init(title: String = "") { self.title = title }

    public init(_ v: RoutineVersionRecord) {
        title = v.title
        emoji = v.emoji
        color = v.color
        timing = v.timing
        durationMin = v.durationMin
        weekdays = v.weekdays
    }

    var fields: Fields {
        var f: Fields = [
            "title": .string(title), "emoji": JSONValue(emoji), "color": .int(color),
            "duration_min": JSONValue(durationMin), "weekdays": .int(weekdays),
        ]
        f.merge(timing.fields) { $1 }
        return f
    }
}

public enum ActionError: Error { case notFound(String) }

extension Store {
    private func nextSortKey(_ entity: Entity) throws -> String {
        let last = try read { db in
            try String.fetchOne(db, sql: "SELECT max(json_extract(fields, '$.sort_key')) FROM \(entity.rawValue)")
        }
        return SortKey.after(last)
    }

    // MARK: tasks

    @discardableResult
    public func createTask(_ d: TaskDraft, now: Date = Date()) throws -> String {
        let id = IDs.new(now: now)
        var f = d.contentFields
        f["date"] = JSONValue(d.date)
        f["first_date"] = JSONValue(d.date)
        f["done_on"] = .null
        f["deleted"] = .bool(false)
        f["sort_key"] = .string(try nextSortKey(.task))
        f["created_at"] = .string(Dates.isoNow(now))
        try write([LocalChange(.task, id, f)])
        return id
    }

    public func updateTask(_ id: String, _ fields: Fields) throws {
        var f = fields
        if let date = fields["date"]?.string, try get(.task, id).map(TaskRecord.init)?.firstDate == nil {
            f["first_date"] = .string(date)
        }
        try write([LocalChange(.task, id, f)])
    }

    public func saveTask(_ id: String, _ d: TaskDraft, today: LocalDate) throws {
        try updateTask(id, d.contentFields)
        if try get(.task, id).map(TaskRecord.init)?.date != d.date {
            try rescheduleTask(id, to: d.date, today: today)
        }
    }

    public func completeTask(_ id: String, today: LocalDate) throws {
        try write([LocalChange(.task, id, ["done_on": .string(today)])])
    }

    public func reopenTask(_ id: String) throws {
        try write([LocalChange(.task, id, ["done_on": .null])])
    }

    public func deleteTask(_ id: String) throws {
        try write([LocalChange(.task, id, ["deleted": true])])
    }

    /// "Tomorrow": one manual move. An inbox task is just planned for tomorrow, without a move.
    public func postponeTask(_ id: String, today: LocalDate) throws {
        guard let task = try get(.task, id).map(TaskRecord.init) else { throw ActionError.notFound(id) }
        let tomorrow = Dates.addDays(today, 1)
        guard let from = task.date else {
            try updateTask(id, ["date": .string(tomorrow)])
            return
        }
        let to = from < today ? tomorrow : Dates.addDays(from, 1)
        try write([
            LocalChange(.task_move, IDs.taskMove(id, from), [
                "task_id": .string(id), "from_date": .string(from), "to_date": .string(to), "kind": "manual",
            ]),
            LocalChange(.task, id, ["date": .string(to)]),
        ])
    }

    /// Pushing a planned task to a later day counts as a postpone (one manual move).
    public func rescheduleTask(_ id: String, to: LocalDate?, today: LocalDate) throws {
        guard let task = try get(.task, id).map(TaskRecord.init) else { throw ActionError.notFound(id) }
        guard let from = task.date, let to, to > from, to > today, task.doneOn == nil else {
            try updateTask(id, ["date": JSONValue(to)])
            return
        }
        try write([
            LocalChange(.task_move, IDs.taskMove(id, from), [
                "task_id": .string(id), "from_date": .string(from), "to_date": .string(to), "kind": "manual",
            ]),
            LocalChange(.task, id, ["date": .string(to)]),
        ])
    }

    /// A new task with the same content, planned for `date`: not done and with no moves of its own.
    /// A deadline that passes before that day stays behind, or the copy would be born overdue.
    @discardableResult
    public func copyTask(_ d: TaskDraft, to date: LocalDate, now: Date = Date()) throws -> String {
        var copy = d
        copy.date = date
        if let deadline = d.deadlineDate, deadline < date {
            copy.deadlineDate = nil
            copy.deadlineTime = nil
        }
        return try createTask(copy, now: now)
    }

    /// Moves every open task planned before today to today. Safe to call repeatedly.
    @discardableResult
    public func runRollover(today: LocalDate) throws -> Int {
        let (tasks, existing) = try read { db -> ([Rules.RolloverTask], Set<String>) in
            let rows = try Rows.fetch(.task, db, where: "date < ?", [today]).map(TaskRecord.init)
            let ids = try String.fetchSet(db, sql: "SELECT id FROM task_move")
            return (rows.map { Rules.RolloverTask(id: $0.id, date: $0.date, doneOn: $0.doneOn, deleted: $0.deleted) }, ids)
        }
        let plan = Rules.planRollover(today: today, tasks: tasks)
        var changes = plan.moves.filter { !existing.contains($0.id) }.map {
            LocalChange(.task_move, $0.id, [
                "task_id": .string($0.taskID), "from_date": .string($0.fromDate), "to_date": .string($0.toDate), "kind": .string($0.kind),
            ])
        }
        changes += plan.dates.sorted { $0.key < $1.key }.map { LocalChange(.task, $0.key, ["date": .string($0.value)]) }
        try write(changes)
        return plan.dates.count
    }

    public func moveCount(_ taskID: String) throws -> Int {
        try read { try Int.fetchOne($0, sql: "SELECT count(*) FROM task_move WHERE task_id = ?", arguments: [taskID]) ?? 0 }
    }

    // MARK: routines

    public func routineVersions(_ db: Database, routineID: String? = nil) throws -> [RoutineVersionRecord] {
        let rows = try routineID.map { try Rows.fetch(.routine_version, db, where: "routine_id = ?", [$0]) }
            ?? Rows.fetch(.routine_version, db)
        return rows.map(RoutineVersionRecord.init)
    }

    public func routinesOn(_ date: LocalDate) throws -> [String: RoutineVersionRecord] {
        Rules.routinesForDay(date, try read { try routineVersions($0) })
    }

    @discardableResult
    public func createRoutine(_ d: RoutineDraft, today: LocalDate, now: Date = Date()) throws -> String {
        let routineID = IDs.new(now: now)
        let created = Dates.isoNow(now)
        var f = d.fields
        f["routine_id"] = .string(routineID)
        f["effective_from"] = .string(today)
        f["archived"] = false
        f["created_at"] = .string(created)
        try write([
            LocalChange(.routine, routineID, ["sort_key": .string(try nextSortKey(.routine)), "created_at": .string(created)]),
            LocalChange(.routine_version, IDs.new(now: now), f),
        ])
        return routineID
    }

    public func latestVersion(_ routineID: String) throws -> RoutineVersionRecord? {
        try read { try routineVersions($0, routineID: routineID) }
            .max { ($0.effectiveFrom, $0.hlc) < ($1.effectiveFrom, $1.hlc) }
    }

    /// Changes apply from today, or from tomorrow if today's occurrence is already marked.
    private func addVersion(_ routineID: String, _ patch: Fields, today: LocalDate) throws {
        guard let latest = try latestVersion(routineID) else { throw ActionError.notFound(routineID) }
        let check = try get(.routine_check, IDs.routineCheck(routineID, today))
        let marked = check?.fields["status"].map { !$0.isNull } ?? false
        var f = latest.fields
        f.merge(patch) { $1 }
        f["effective_from"] = .string(marked ? Dates.addDays(today, 1) : today)
        f["created_at"] = .string(Dates.isoNow())
        try write([LocalChange(.routine_version, IDs.new(), f)])
    }

    public func editRoutine(_ routineID: String, _ d: RoutineDraft, today: LocalDate) throws {
        guard let latest = try latestVersion(routineID) else { throw ActionError.notFound(routineID) }
        let patch = d.fields.filter { latest.fields[$0.key] != $0.value }
        if !patch.isEmpty { try addVersion(routineID, patch, today: today) }
    }

    public func archiveRoutine(_ routineID: String, today: LocalDate) throws {
        try addVersion(routineID, ["archived": true], today: today)
    }

    public func setRoutineCheck(_ routineID: String, date: LocalDate, status: CheckStatus?, now: Date = Date()) throws {
        let v = try routinesOn(date)[routineID]
        let snapshot: JSONValue = v.map {
            var s: Fields = ["title": .string($0.title), "emoji": JSONValue($0.emoji), "color": .int($0.color)]
            s.merge($0.timing.fields) { $1 }
            return .object(s)
        } ?? .null
        try write([LocalChange(.routine_check, IDs.routineCheck(routineID, date), [
            "routine_id": .string(routineID), "date": .string(date), "status": JSONValue(status?.rawValue),
            "done_at": status == .done ? .string(Dates.isoNow(now)) : .null, "snapshot": snapshot,
        ])])
    }

    // MARK: settings

    public func updateSettings(_ patch: Fields) throws {
        try write([LocalChange(.settings, settingsID, patch)])
    }
}

/// Fractional index keys compatible with the web's `fractional-indexing` ordering (plain string
/// comparison). Only appending is needed on iOS so far.
public enum SortKey {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// A key that sorts after `last` (or a first key when there is none).
    public static func after(_ last: String?) -> String {
        guard let last, !last.isEmpty else { return "a0" }
        var chars = Array(last)
        // Increment the last digit; if it overflows, append a digit instead (still sorts after).
        if let i = digits.firstIndex(of: chars[chars.count - 1]), i + 1 < digits.count {
            chars[chars.count - 1] = digits[i + 1]
            return String(chars)
        }
        return last + "V"
    }
}
