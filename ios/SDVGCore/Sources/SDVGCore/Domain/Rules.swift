import Foundation

// Normative rules: see the descriptions in shared/domain-fixtures/*.json.

public protocol VersionRef {
    var routineID: String { get }
    var effectiveFrom: LocalDate { get }
    var weekdays: Int { get }
    var archived: Bool { get }
    var hlc: String { get }
}

extension RoutineVersionRecord: VersionRef {}

public enum Rules {
    /// Per routine: the version with max (effective_from, hlc) among effective_from <= date,
    /// kept if not archived and its weekday bit is set.
    public static func routinesForDay<V: VersionRef>(_ date: LocalDate, _ versions: [V]) -> [String: V] {
        var current: [String: V] = [:]
        for v in versions where v.effectiveFrom <= date {
            if let cur = current[v.routineID],
               (cur.effectiveFrom, cur.hlc) >= (v.effectiveFrom, v.hlc) { continue }
            current[v.routineID] = v
        }
        let bit = 1 << Dates.weekdayIndex(date)
        return current.filter { !$0.value.archived && $0.value.weekdays & bit != 0 }
    }

    public struct PlannedMove: Hashable, Sendable {
        public var id: String
        public var taskID: String
        public var fromDate: LocalDate
        public var toDate: LocalDate
        public var kind: String
    }

    public struct RolloverTask: Sendable {
        public var id: String
        public var date: LocalDate?
        public var doneOn: LocalDate?
        public var deleted: Bool

        public init(id: String, date: LocalDate?, doneOn: LocalDate?, deleted: Bool) {
            self.id = id
            self.date = date
            self.doneOn = doneOn
            self.deleted = deleted
        }
    }

    /// One auto move per missed day for every open task planned before today.
    public static func planRollover(today: LocalDate, tasks: [RolloverTask]) -> (moves: [PlannedMove], dates: [String: LocalDate]) {
        var moves: [PlannedMove] = []
        var dates: [String: LocalDate] = [:]
        for t in tasks {
            guard t.doneOn == nil, !t.deleted, let start = t.date, start < today else { continue }
            var d = start
            while d < today {
                let next = Dates.addDays(d, 1)
                moves.append(PlannedMove(id: IDs.taskMove(t.id, d), taskID: t.id, fromDate: d, toDate: next, kind: "auto"))
                d = next
            }
            dates[t.id] = today
        }
        return (moves, dates)
    }

    public static func attentionLevel(moves: Int, thresholds: [Int]) -> Int {
        thresholds.filter { moves >= $0 }.count
    }

    /// How loudly to celebrate a task done after `moves` postpones:
    /// 0 just the check, 1 confetti, 2 fireworks, 3 big fireworks with applause.
    public static func celebrationLevel(moves: Int) -> Int {
        moves >= 10 ? 3 : moves >= 5 ? 2 : moves >= 1 ? 1 : 0
    }

    public enum DeadlineStatus: String, Sendable { case none, ok, soon, today, overdue }

    public static func deadlineStatus(
        now: LocalDateTime, dayStartHour: Int, createdOn: LocalDate,
        deadlineDate: LocalDate?, deadlineTime: LocalTime?, done: Bool
    ) -> DeadlineStatus {
        guard !done, let dd = deadlineDate else { return .none }
        let today = Dates.logicalDay(now, dayStartHour: dayStartHour)
        if let dt = deadlineTime, now >= "\(dd)T\(dt)" { return .overdue }
        if today > dd { return .overdue }
        if today == dd { return .today }
        let left = Dates.daysBetween(today, dd)
        let total = Dates.daysBetween(createdOn, dd)
        let elapsed = Dates.daysBetween(createdOn, today)
        if left <= 2 || (total > 0 && Double(elapsed) / Double(total) > 0.8) { return .soon }
        return .ok
    }

    public struct DayStats: Hashable, Sendable {
        public var done = 0
        public var skipped = 0
        public init(done: Int = 0, skipped: Int = 0) {
            self.done = done
            self.skipped = skipped
        }
    }

    /// Deleted tasks still count: the work was done. Cleared checks count as nothing.
    public static func dayStats(date: LocalDate, taskDoneOn: [LocalDate?], checks: [(date: LocalDate, status: CheckStatus?)]) -> DayStats {
        var s = DayStats(done: taskDoneOn.filter { $0 == date }.count)
        for c in checks where c.date == date {
            if c.status == .done { s.done += 1 } else if c.status == .skipped { s.skipped += 1 }
        }
        return s
    }

    /// Success days in the unbroken run of success/neutral days ending today; a neutral day keeps
    /// the streak without adding to it; today counts only once it is a success.
    public static func streak(today: LocalDate, days: [LocalDate: DayStats], minDone: Int) -> Int {
        enum Kind { case success, neutral, fail }
        func kind(_ d: LocalDate) -> Kind {
            let s = days[d] ?? DayStats()
            if s.done >= minDone { return .success }
            return s.skipped > 0 ? .neutral : .fail
        }
        var n = 0
        var d = kind(today) == .success ? today : Dates.addDays(today, -1)
        while true {
            switch kind(d) {
            case .fail: return n
            case .success: n += 1
            case .neutral: break
            }
            d = Dates.addDays(d, -1)
        }
    }

    public struct DayRecord: Hashable, Sendable {
        /// Day the previous record was first set; nil when nothing was done before today.
        public var bestDate: LocalDate?
        public var bestDone = 0
        public var todayDone = 0
        /// How many more to do today to beat the record.
        public var toBeat: Int { max(0, bestDone + 1 - todayDone) }
        public var broken: Bool { bestDone > 0 && todayDone > bestDone }
    }

    /// Most done in a day before today (earliest day on a tie) and how today compares to it.
    public static func dayRecord(today: LocalDate, days: [LocalDate: DayStats]) -> DayRecord {
        var r = DayRecord(todayDone: days[today]?.done ?? 0)
        for (d, s) in days where d < today && s.done > 0 {
            if s.done > r.bestDone || (s.done == r.bestDone && d < r.bestDate!) {
                r.bestDate = d
                r.bestDone = s.done
            }
        }
        return r
    }

    /// Levels 0...4 relative to personal history: quartiles of the non-zero counts.
    public static func heatmapLevels(_ counts: [Int]) -> [Int] {
        let v = counts.filter { $0 > 0 }.sorted()
        guard !v.isEmpty else { return counts.map { _ in 0 } }
        let q = [0.25, 0.5, 0.75].map { v[Int((Double(v.count) * $0).rounded(.up)) - 1] }
        return counts.map { c in c == 0 ? 0 : 1 + q.filter { c > $0 }.count }
    }

    public static let heatmapWeeks = 53

    /// Monday-first week columns; the last column is the week containing today.
    public static func heatmapGrid(today: LocalDate) -> [LocalDate] {
        let monday = Dates.addDays(today, -Dates.weekdayIndex(today))
        let first = Dates.addDays(monday, -7 * (heatmapWeeks - 1))
        return (0..<(heatmapWeeks * 7)).map { Dates.addDays(first, $0) }
    }

    public enum ScoreReason: String, Sendable { case now, deadline, postponed }

    /// Ranking for the "Now" screen: now + deadline + postpone components.
    public static func nowScore(
        now: LocalDateTime, settings s: Settings, timing: Timing, deadline: DeadlineStatus, moves: Int
    ) -> (score: Int, reasons: [ScoreReason]) {
        var reasons: [ScoreReason] = []
        var nowPart = 0
        if timing.kind == .exact, let time = timing.time {
            var day = Dates.logicalDay(now, dayStartHour: s.dayStartHour)
            if (Int(time.prefix(2)) ?? 0) < s.dayStartHour { day = Dates.addDays(day, 1) }
            let mins = Dates.minutesBetween("\(day)T\(time)", now)
            if mins >= -30 && mins <= 60 { nowPart = 100 }
        } else if timing.kind == .part, timing.part == Dates.partOfDay(now, s) {
            nowPart = 50
        }
        if nowPart > 0 { reasons.append(.now) }
        let dl = [DeadlineStatus.overdue: 90, .today: 80, .soon: 60][deadline] ?? 0
        if dl > 0 { reasons.append(.deadline) }
        let postponed = min(moves * 8, 70)
        if postponed > 0 { reasons.append(.postponed) }
        return (nowPart + dl + postponed, reasons)
    }
}
