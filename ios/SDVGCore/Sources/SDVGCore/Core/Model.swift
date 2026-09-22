import Foundation

/// Mirrors shared/schema. Dates are local "YYYY-MM-DD", times local "HH:MM".
public typealias LocalDate = String
public typealias LocalTime = String
/// Local wall-clock moment "YYYY-MM-DDTHH:MM".
public typealias LocalDateTime = String

public enum Entity: String, CaseIterable, Codable, Sendable {
    case task, task_move, routine, routine_version, routine_check, settings
}

public let settingsID = "settings"

public enum TimeKind: String, Codable, Sendable, CaseIterable { case none, part, exact }
public enum PartOfDay: String, Codable, Sendable, CaseIterable { case morning, day, evening }
public enum CheckStatus: String, Codable, Sendable { case done, skipped }

/// A row or a change on the wire: `{entity, id, fields, clocks}`.
public struct Change: Codable, Hashable, Sendable {
    public var entity: String
    public var id: String
    public var fields: Fields
    public var clocks: Clocks

    public init(entity: String, id: String, fields: Fields, clocks: Clocks) {
        self.entity = entity
        self.id = id
        self.fields = fields
        self.clocks = clocks
    }
}

public struct DataRow: Hashable, Sendable {
    public var id: String
    public var fields: Fields
    public var clocks: Clocks

    public init(id: String, fields: Fields = [:], clocks: Clocks = [:]) {
        self.id = id
        self.fields = fields
        self.clocks = clocks
    }
}

public struct Timing: Hashable, Sendable {
    public var kind: TimeKind
    public var part: PartOfDay?
    public var time: LocalTime?

    public init(kind: TimeKind, part: PartOfDay? = nil, time: LocalTime? = nil) {
        self.kind = kind
        self.part = part
        self.time = time
    }

    /// `time_kind` is the source of truth; stale part/time from merges are ignored.
    init(_ f: Fields) {
        kind = f["time_kind"]?.string.flatMap(TimeKind.init) ?? .none
        part = kind == .part ? f["part_of_day"]?.string.flatMap(PartOfDay.init) : nil
        time = kind == .exact ? f["time"]?.string : nil
    }

    var fields: Fields {
        ["time_kind": .string(kind.rawValue), "part_of_day": JSONValue(part?.rawValue), "time": JSONValue(time)]
    }
}

public struct TaskRecord: Hashable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var notes: String
    public var emoji: String?
    public var color: Int
    public var date: LocalDate?
    public var firstDate: LocalDate?
    public var timing: Timing
    public var durationMin: Int?
    public var deadlineDate: LocalDate?
    public var deadlineTime: LocalTime?
    public var doneOn: LocalDate?
    public var deleted: Bool
    public var sortKey: String
    public var createdAt: String?

    public init(_ row: DataRow) {
        let f = row.fields
        id = row.id
        title = f["title"]?.string ?? ""
        notes = f["notes"]?.string ?? ""
        emoji = f["emoji"]?.string
        color = f["color"]?.int ?? 0
        date = f["date"]?.string
        firstDate = f["first_date"]?.string
        timing = Timing(f)
        durationMin = f["duration_min"]?.int
        deadlineDate = f["deadline_date"]?.string
        deadlineTime = f["deadline_time"]?.string
        doneOn = f["done_on"]?.string
        deleted = f["deleted"]?.bool ?? false
        sortKey = f["sort_key"]?.string ?? ""
        createdAt = f["created_at"]?.string
    }
}

public struct RoutineVersionRecord: Hashable, Sendable, Identifiable {
    public let id: String
    public var routineID: String
    public var effectiveFrom: LocalDate
    public var title: String
    public var emoji: String?
    public var color: Int
    public var timing: Timing
    public var durationMin: Int?
    public var weekdays: Int
    public var archived: Bool
    /// Clock of the version; breaks ties between versions with the same effective_from.
    public var hlc: String
    public var fields: Fields

    public init(_ row: DataRow) {
        let f = row.fields
        id = row.id
        routineID = f["routine_id"]?.string ?? ""
        effectiveFrom = f["effective_from"]?.string ?? ""
        title = f["title"]?.string ?? ""
        emoji = f["emoji"]?.string
        color = f["color"]?.int ?? 0
        timing = Timing(f)
        durationMin = f["duration_min"]?.int
        weekdays = f["weekdays"]?.int ?? 127
        archived = f["archived"]?.bool ?? false
        hlc = row.clocks["effective_from"] ?? ""
        fields = f
    }
}

public struct Settings: Hashable, Sendable {
    public var dayStartHour = 4
    public var partMorningFrom = 6
    public var partDayFrom = 12
    public var partEveningFrom = 18
    public var attentionThresholds = [1, 3, 6, 10]
    public var streakMinDone = 1
    /// Show today's progress as "done/total"; false shows only the done count.
    public var showDayTotal = true

    public init() {}

    public init(_ f: Fields) {
        if let v = f["day_start_hour"]?.int { dayStartHour = v }
        if let v = f["part_morning_from"]?.int { partMorningFrom = v }
        if let v = f["part_day_from"]?.int { partDayFrom = v }
        if let v = f["part_evening_from"]?.int { partEveningFrom = v }
        if let v = f["attention_thresholds"]?.array?.compactMap(\.int), v.count == 4 { attentionThresholds = v }
        if let v = f["streak_min_done"]?.int { streakMinDone = v }
        if let v = f["show_day_total"]?.bool { showDayTotal = v }
    }
}
