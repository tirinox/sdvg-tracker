import Foundation

// What a widget shows, built from the local store. The widget extension reads the same
// database as the app, so it works offline and needs no network of its own.

public enum WidgetFilter: String, CaseIterable, Sendable {
    case all, tasks, routines

    func keeps(_ item: DayItem) -> Bool {
        switch self {
        case .all: true
        case .tasks: item.kind == .task
        case .routines: item.kind == .routine
        }
    }
}

public struct WidgetSnapshot: Sendable {
    public struct Item: Identifiable, Sendable {
        public var id: String { item.id }
        public var item: DayItem
        /// One short label: time, deadline or postpone count — never all three.
        public var badge: String?
        public var badgeKind: BadgeKind
    }

    public enum BadgeKind: String, Sendable { case none, time, deadline, moves }

    public var date: LocalDate
    public var now: LocalDateTime
    /// Highest ranked open items, already filtered.
    public var items: [Item]
    public var done: Int
    public var total: Int
    /// Items of the current part of day (large widget), done ones last.
    public var part: DaySection
    public var partItems: [Item]
    public var partDone: Int
    public var partTotal: Int
    public var streak: Int
    public var record: Rules.DayRecord
    public var showDayTotal: Bool
    /// Items left after the ones shown in `partItems`.
    public var moreInPart: Int
    public var nextPart: DaySection?
    public var nextPartCount: Int

    public var progressText: String {
        showDayTotal ? "\(done)/\(total)" : "\(done)"
    }

    /// "ещё 3 до рекорда" / "рекорд дня!" — nil when there is no history yet.
    public var recordText: String? {
        guard record.bestDone > 0 else { return nil }
        if record.broken { return "рекорд дня!" }
        return "до рекорда \(record.toBeat)"
    }
}

extension Store {
    /// Everything a widget needs in one read.
    public func widgetSnapshot(now: LocalDateTime, filter: WidgetFilter = .all, limit: Int = 7) throws -> WidgetSnapshot {
        let settings = try self.settings()
        let today = Dates.logicalDay(now, dayStartHour: settings.dayStartHour)
        let day = try loadDay(today, now: now)
        let stats = try loadStats(today: today)

        let kept = day.items.filter(filter.keeps)
        let open = kept.filter { !$0.done && !$0.skipped }
        let ranked = pickNow(DayView(date: today, items: kept), max: limit, min: limit)

        let part = DaySection(rawValue: Dates.partOfDay(now, settings).rawValue) ?? .anytime
        // The counter is about this part of the day only; "anytime" items just fill the list up,
        // otherwise a pile of undated tasks would make every part look hopeless.
        let inPart = kept.filter { $0.section == part }
        let partOpen = inPart.filter { !$0.done && !$0.skipped }
        let filler = kept.filter { $0.section == .anytime && !$0.done && !$0.skipped }
        let shown = Array((inPart + filler).prefix(6))
        let order = DaySection.allCases
        let next = order.firstIndex(of: part).flatMap { order.indices.contains($0 + 1) ? order[$0 + 1] : nil }

        return WidgetSnapshot(
            date: today,
            now: now,
            items: ranked.map { badged($0, today: today) },
            done: kept.filter(\.done).count,
            total: kept.filter { !$0.skipped }.count,
            part: part,
            partItems: shown.map { badged($0, today: today) },
            partDone: inPart.filter(\.done).count,
            partTotal: inPart.filter { !$0.skipped }.count,
            streak: stats.streak,
            record: stats.record,
            showDayTotal: settings.showDayTotal,
            moreInPart: max(0, partOpen.count + filler.count - shown.count),
            nextPart: next,
            nextPartCount: next.map { n in kept.filter { $0.section == n && !$0.done && !$0.skipped }.count } ?? 0)
    }

    private func badged(_ item: DayItem, today: LocalDate) -> WidgetSnapshot.Item {
        if let time = item.timing.time {
            return .init(item: item, badge: time, badgeKind: .time)
        }
        if item.deadline == .overdue || item.deadline == .today || item.deadline == .soon {
            let left = item.deadlineDate.map { Dates.daysBetween(today, $0) } ?? 0
            let text = switch item.deadline {
            case .overdue: "просрочено"
            case .today: "сегодня"
            default: "\(left) дн."
            }
            return .init(item: item, badge: text, badgeKind: .deadline)
        }
        if item.moves > 0 {
            return .init(item: item, badge: "↻ \(item.moves)", badgeKind: .moves)
        }
        return .init(item: item, badge: nil, badgeKind: .none)
    }

    /// When the widget should be rebuilt: around timed items, at part boundaries and at the
    /// start of the next logical day. Sorted, future-only, capped.
    public func widgetRefreshDates(now: Date = Date(), calendar: Calendar = .current) throws -> [Date] {
        let settings = try self.settings()
        let nowLocal = Dates.localNow(now, calendar: calendar)
        let today = Dates.logicalDay(nowLocal, dayStartHour: settings.dayStartHour)
        var moments: [LocalDateTime] = []

        for date in [today, Dates.addDays(today, 1)] {
            let day = try loadDay(date, now: nowLocal)
            for item in day.items where !item.done && !item.skipped {
                guard let time = item.timing.time else { continue }
                let calDate = (Int(time.prefix(2)) ?? 0) < settings.dayStartHour ? Dates.addDays(date, 1) : date
                moments.append(contentsOf: [
                    shift("\(calDate)T\(time)", by: -30), "\(calDate)T\(time)", shift("\(calDate)T\(time)", by: 61),
                ])
            }
            for hour in [settings.partMorningFrom, settings.partDayFrom, settings.partEveningFrom, settings.dayStartHour] {
                moments.append("\(date)T\(String(format: "%02d", hour)):00")
            }
        }
        return moments.filter { $0 > nowLocal }.sorted().prefix(40).compactMap { date(from: $0, calendar: calendar) }
    }

    private func shift(_ moment: LocalDateTime, by minutes: Int) -> LocalDateTime {
        let total = Dates.minuteOf(moment) + minutes
        let day = Dates.fromEpochDay(Int(floor(Double(total) / 1440)))
        let inDay = ((total % 1440) + 1440) % 1440
        return String(format: "%@T%02d:%02d", day, inDay / 60, inDay % 60)
    }

    private func date(from moment: LocalDateTime, calendar: Calendar) -> Date? {
        var c = DateComponents()
        c.year = Int(moment.prefix(4))
        c.month = Int(moment.dropFirst(5).prefix(2))
        c.day = Int(moment.dropFirst(8).prefix(2))
        c.hour = Int(moment.dropFirst(11).prefix(2))
        c.minute = Int(moment.dropFirst(14).prefix(2))
        return calendar.date(from: c)
    }
}
