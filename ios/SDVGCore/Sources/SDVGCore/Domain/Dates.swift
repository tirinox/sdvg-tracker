import Foundation

/// Calendar arithmetic on local "YYYY-MM-DD" strings via epoch days, so DST never shifts a day.
public enum Dates {
    static func parts(_ date: LocalDate) -> (Int, Int, Int) {
        let p = date.split(separator: "-").compactMap { Int($0) }
        return (p[0], p[1], p[2])
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public static func epochDay(_ date: LocalDate) -> Int {
        var (y, m, d) = parts(date)
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public static func fromEpochDay(_ days: Int) -> LocalDate {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func addDays(_ date: LocalDate, _ days: Int) -> LocalDate {
        fromEpochDay(epochDay(date) + days)
    }

    /// Whole days from `from` to `to` (negative if `to` is earlier).
    public static func daysBetween(_ from: LocalDate, _ to: LocalDate) -> Int {
        epochDay(to) - epochDay(from)
    }

    /// 0 = Monday ... 6 = Sunday.
    public static func weekdayIndex(_ date: LocalDate) -> Int {
        ((epochDay(date) + 3) % 7 + 7) % 7
    }

    static func minuteOf(_ v: LocalDateTime) -> Int {
        let date = String(v.prefix(10))
        let time = v.dropFirst(11).prefix(5).split(separator: ":").compactMap { Int($0) }
        return epochDay(date) * 1440 + time[0] * 60 + time[1]
    }

    public static func minutesBetween(_ from: LocalDateTime, _ to: LocalDateTime) -> Int {
        minuteOf(to) - minuteOf(from)
    }

    public static func hour(of now: LocalDateTime) -> Int {
        Int(now.dropFirst(11).prefix(2)) ?? 0
    }

    /// Current local wall-clock moment as "YYYY-MM-DDTHH:MM".
    public static func localNow(_ date: Date = Date(), calendar: Calendar = .current) -> LocalDateTime {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    /// Local date of a UTC ISO instant ("2026-09-22T07:00:00Z").
    public static func localDate(ofISO iso: String, calendar: Calendar = .current) -> LocalDate? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date.map { String(localNow($0, calendar: calendar).prefix(10)) }
    }

    public static func isoNow(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Logical today = local date of (now - day_start_hour): at 01:30 it is still yesterday.
    public static func logicalDay(_ now: LocalDateTime, dayStartHour: Int) -> LocalDate {
        let date = String(now.prefix(10))
        return hour(of: now) < dayStartHour ? addDays(date, -1) : date
    }

    /// The logical day `date` ends at day_start_hour on the next calendar date, not at midnight.
    public static func dayEnd(_ date: LocalDate, dayStartHour: Int) -> LocalDateTime {
        String(format: "%@T%02d:00", addDays(date, 1), dayStartHour)
    }

    public enum DayEndLevel: String { case calm, soon, urgent }

    /// How close the end of the day is: the last hour is soon, the last half hour urgent.
    public static func dayEndLevel(secondsLeft: Int) -> DayEndLevel {
        if secondsLeft <= 30 * 60 { return .urgent }
        if secondsLeft <= 60 * 60 { return .soon }
        return .calm
    }

    /// The real moment of a local wall-clock time, in the calendar's time zone.
    public static func instant(of moment: LocalDateTime, calendar: Calendar = .current) -> Date? {
        var c = DateComponents()
        c.year = Int(moment.prefix(4))
        c.month = Int(moment.dropFirst(5).prefix(2))
        c.day = Int(moment.dropFirst(8).prefix(2))
        c.hour = Int(moment.dropFirst(11).prefix(2))
        c.minute = Int(moment.dropFirst(14).prefix(2))
        return calendar.date(from: c)
    }

    /// Evening lasts until day_start_hour; from day_start_hour until part_day_from it is morning.
    public static func partOfDay(_ now: LocalDateTime, _ s: Settings) -> PartOfDay {
        let h = hour(of: now)
        if h >= s.partEveningFrom || h < s.dayStartHour { return .evening }
        if h >= s.partDayFrom { return .day }
        return .morning
    }
}
