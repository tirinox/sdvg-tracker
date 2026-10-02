import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// Labels in the interface language and the shared palette, used by the app and the widgets.

public enum Fmt {
    private struct Formatters: @unchecked Sendable {
        let dayMonth, weekday, shortDM, monthOnly: DateFormatter

        init(_ lang: Language) {
            func formatter(_ template: String) -> DateFormatter {
                let f = DateFormatter()
                f.locale = lang.locale
                f.timeZone = TimeZone(identifier: "UTC")
                f.setLocalizedDateFormatFromTemplate(template)
                return f
            }
            dayMonth = formatter("d MMMM")
            weekday = formatter("EEEE")
            shortDM = formatter("d MMM")
            monthOnly = formatter("LLL")
            monthOnly.dateFormat = "LLL"
        }
    }

    private static let ru = Formatters(.ru), en = Formatters(.en)
    private static var f: Formatters { L10n.current == .ru ? ru : en }

    private static func date(_ d: LocalDate) -> Date {
        Date(timeIntervalSince1970: Double(Dates.epochDay(d)) * 86400 + 43200)
    }

    public static func shortDate(_ d: LocalDate) -> String { f.shortDM.string(from: date(d)).replacingOccurrences(of: ".", with: "") }
    public static func month(_ d: LocalDate) -> String { f.monthOnly.string(from: date(d)).replacingOccurrences(of: ".", with: "") }

    public static func relativeDay(_ d: LocalDate, today: LocalDate) -> String? {
        d == today ? tr("Сегодня", "Today")
            : d == Dates.addDays(today, 1) ? tr("Завтра", "Tomorrow")
            : d == Dates.addDays(today, -1) ? tr("Вчера", "Yesterday") : nil
    }

    public static func dayTitle(_ d: LocalDate, today: LocalDate) -> (title: String, subtitle: String) {
        let wd = f.weekday.string(from: date(d)), dm = f.dayMonth.string(from: date(d))
        return relativeDay(d, today: today).map { ($0, "\(wd), \(dm)") } ?? (wd.prefix(1).uppercased() + wd.dropFirst(), dm)
    }

    /// "3 дня" / "3 days".
    public static func days(_ n: Int) -> String { trn(n, ru: ("день", "дня", "дней"), en: ("day", "days")) }

    /// How far a day is from today: "завтра", "через 3 дня", "5 дней назад".
    public static func dayDistance(_ d: LocalDate, today: LocalDate) -> String {
        let n = Dates.daysBetween(today, d)
        switch n {
        case 0: return tr("сегодня", "today")
        case 1: return tr("завтра", "tomorrow")
        case 2: return tr("послезавтра", "the day after tomorrow")
        case -1: return tr("вчера", "yesterday")
        case -2: return tr("позавчера", "the day before yesterday")
        default:
            let days = days(abs(n))
            return n > 0 ? tr("через \(days)", "in \(days)") : tr("\(days) назад", "\(days) ago")
        }
    }

    public static func partTitle(_ p: PartOfDay) -> String {
        switch p {
        case .morning: tr("Утро", "Morning")
        case .day: tr("День", "Afternoon")
        case .evening: tr("Вечер", "Evening")
        }
    }

    public static func sectionTitle(_ s: DaySection) -> String {
        switch s {
        case .anytime: tr("В любое время", "Anytime")
        case .morning: partTitle(.morning)
        case .day: partTitle(.day)
        case .evening: partTitle(.evening)
        }
    }

    public static func groupTitle(_ g: DayGroup) -> String {
        switch g {
        case .section(let s): sectionTitle(s)
        case .done: tr("Сделано", "Done")
        }
    }

    public static func duration(_ min: Int?) -> String {
        guard let min, min > 0 else { return "" }
        if min < 60 { return tr("\(min) мин", "\(min) min") }
        let h = min / 60, m = min % 60
        return m > 0 ? tr("\(h) ч \(m) мин", "\(h) h \(m) min") : tr("\(h) ч", "\(h) h")
    }

    public static func timing(_ t: Timing, duration minutes: Int?) -> String {
        let dur = duration(minutes)
        let head: String? = switch t.kind {
        case .exact: t.time
        case .part: t.part.map(partTitle)
        case .none: nil
        }
        return [head, dur.isEmpty ? nil : dur].compactMap { $0 }.joined(separator: " · ")
    }

    public static func deadline(_ i: DayItem, today: LocalDate) -> String {
        guard i.deadline != .none, let dd = i.deadlineDate else { return "" }
        let time = i.deadlineTime.map { tr(" до \($0)", " by \($0)") } ?? ""
        switch i.deadline {
        case .overdue:
            let late = Dates.daysBetween(dd, today)
            return late > 0 ? tr("просрочено на \(days(late))", "\(days(late)) overdue") : tr("просрочено\(time)", "overdue\(time)")
        case .today: return tr("дедлайн сегодня\(time)", "due today\(time)")
        default:
            let left = Dates.daysBetween(today, dd)
            return left == 1 ? tr("дедлайн завтра\(time)", "due tomorrow\(time)") : tr("дедлайн через \(days(left))", "due in \(days(left))")
        }
    }

    /// "!! важно": the tag of a high-priority item.
    public static var priorityTag: String { tr("!! важно", "!! important") }
    public static var lowPriority: String { tr("↓ не срочно", "↓ not urgent") }

    public static func priority(_ p: Priority) -> String {
        switch p {
        case .high: tr("!! Высокий", "!! High")
        case .normal: tr("Обычный", "Normal")
        case .low: tr("↓ Низкий", "↓ Low")
        }
    }

    public static func moves(_ n: Int) -> String { trn(n, ru: ("перенос", "переноса", "переносов"), en: ("move", "moves")) }

    /// Where a routine's percent comes from: «сделано 5 из 8 дней с 5 сент».
    public static func adherence(_ a: Rules.Adherence) -> String {
        let from = a.from.map(shortDate)
        return tr(
            "сделано \(a.done) из \(a.total) \(plural(a.total, "дня", "дней", "дней"))\(from.map { " с \($0)" } ?? "")",
            "done \(a.done) of \(a.total) \(a.total == 1 ? "day" : "days")\(from.map { " since \($0)" } ?? "")")
    }

    /// Timing hint for the Now screen (deadline and moves already have tags on the row).
    public static func nowHint(_ i: DayItem, now: LocalDateTime, today: LocalDate) -> String? {
        guard i.reasons.contains(.now) else { return nil }
        guard let time = i.timing.time else { return tr("🕐 самое время", "🕐 good time for it") }
        var mins = Dates.minutesBetween(now, "\(today)T\(time)")
        if mins < -12 * 60 { mins += 24 * 60 }
        return mins > 0 ? tr("⏰ через \(mins) мин", "⏰ in \(mins) min")
            : mins == 0 ? tr("⏰ сейчас", "⏰ now") : tr("⏰ идёт \(-mins) мин", "⏰ started \(-mins) min ago")
    }

    /// Short weekday names, Monday first (bit 0 of a weekday mask).
    public static var weekdays: [String] {
        L10n.current == .ru ? ["пн", "вт", "ср", "чт", "пт", "сб", "вс"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    }

    public static func weekdays(_ mask: Int) -> String {
        switch mask {
        case 127: tr("каждый день", "every day")
        case 0b0011111: tr("по будням", "on weekdays")
        case 0b1100000: tr("по выходным", "on weekends")
        default: weekdays.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element).joined(separator: ", ")
        }
    }
}

/// The shared 12-color palette (index stored in data).
public enum Palette {
    static let hexes = [
        0xF06A6A, 0xF39A4C, 0xEEC14A, 0xA9CF54, 0x5DBB7A, 0x45B8A8,
        0x4BB0DE, 0x5B8DEF, 0x7B74E6, 0xA97BE0, 0xE57BB8, 0x8E95A8,
    ]
    public static let colors: [Color] = hexes.map { Color(hex: $0) }
    /// Readable text in a palette color, as on the web: 55 % of it over the text color of the theme.
    static let texts: [Color] = hexes.map { Color(light: mix($0, 0x1F1D2B, 0.55), dark: mix($0, 0xECEBF5, 0.55)) }

    public static func color(_ i: Int) -> Color { colors[(i % 12 + 12) % 12] }
    public static func text(_ i: Int) -> Color { texts[(i % 12 + 12) % 12] }

    private static func mix(_ a: Int, _ b: Int, _ t: Double) -> Int {
        [16, 8, 0].reduce(0) { acc, shift in
            let x = Double((a >> shift) & 0xff) * t + Double((b >> shift) & 0xff) * (1 - t)
            return acc | (Int(x.rounded()) << shift)
        }
    }

    public static let heat: [Color] = [
        Color(light: 0xE9E7F2, dark: 0x24222E), Color(light: 0xCFE8D6, dark: 0x1D4630), Color(light: 0x97D2A8, dark: 0x247046),
        Color(light: 0x54B07A, dark: 0x34A062), Color(light: 0x2A8452, dark: 0x5FD394),
    ]
    public static let ok = Color(light: 0x2F9E6A, dark: 0x5FD39A)
    public static let warn = Color(light: 0xC7771A, dark: 0xF0A94B)
    public static let danger = Color(light: 0xD4483B, dark: 0xFF7B6E)
    /// Yellow: text, and the fill behind it.
    public static let caution = Color(light: 0x7A5A00, dark: 0xF5D04A)
    public static let cautionFill = Color(light: 0xFCF0BF, dark: 0x3A3113)
}

extension Color {
    public init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// Two shades of the same role, picked by the interface style.
    public init(light: Int, dark: Int) {
        #if canImport(UIKit)
            self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
        #else
            self.init(hex: light)
        #endif
    }
}
