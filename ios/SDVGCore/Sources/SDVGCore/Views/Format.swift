import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// Russian labels and the shared palette, used by the app and the widgets.

public func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return one }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
    return many
}

public enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dayMonth = formatter("d MMMM")
    private static let weekday = formatter("EEEE")
    private static let shortDM = formatter("d MMM")
    private static let monthOnly: DateFormatter = {
        let f = formatter("LLL")
        f.dateFormat = "LLL"
        return f
    }()

    private static func date(_ d: LocalDate) -> Date {
        Date(timeIntervalSince1970: Double(Dates.epochDay(d)) * 86400 + 43200)
    }

    public static func shortDate(_ d: LocalDate) -> String { shortDM.string(from: date(d)).replacingOccurrences(of: ".", with: "") }
    public static func month(_ d: LocalDate) -> String { monthOnly.string(from: date(d)).replacingOccurrences(of: ".", with: "") }

    public static func dayTitle(_ d: LocalDate, today: LocalDate) -> (title: String, subtitle: String) {
        let wd = weekday.string(from: date(d)), dm = dayMonth.string(from: date(d))
        let rel: String? = d == today ? "Сегодня" : d == Dates.addDays(today, 1) ? "Завтра" : d == Dates.addDays(today, -1) ? "Вчера" : nil
        return rel.map { ($0, "\(wd), \(dm)") } ?? (wd.prefix(1).uppercased() + wd.dropFirst(), dm)
    }

    /// How far a day is from today: "завтра", "через 3 дня", "5 дней назад".
    public static func dayDistance(_ d: LocalDate, today: LocalDate) -> String {
        let n = Dates.daysBetween(today, d)
        switch n {
        case 0: return "сегодня"
        case 1: return "завтра"
        case 2: return "послезавтра"
        case -1: return "вчера"
        case -2: return "позавчера"
        default:
            let days = "\(abs(n)) \(plural(abs(n), "день", "дня", "дней"))"
            return n > 0 ? "через \(days)" : "\(days) назад"
        }
    }

    public static let sectionTitles: [DaySection: String] = [.anytime: "В любое время", .morning: "Утро", .day: "День", .evening: "Вечер"]

    public static func groupTitle(_ g: DayGroup) -> String {
        switch g {
        case .section(let s): sectionTitles[s]!
        case .done: "Сделано"
        }
    }
    public static let partTitles: [PartOfDay: String] = [.morning: "Утро", .day: "День", .evening: "Вечер"]

    public static func duration(_ min: Int?) -> String {
        guard let min, min > 0 else { return "" }
        if min < 60 { return "\(min) мин" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h) ч \(m) мин" : "\(h) ч"
    }

    public static func timing(_ t: Timing, duration minutes: Int?) -> String {
        let dur = duration(minutes)
        let head: String? = switch t.kind {
        case .exact: t.time
        case .part: t.part.flatMap { partTitles[$0] }
        case .none: nil
        }
        return [head, dur.isEmpty ? nil : dur].compactMap { $0 }.joined(separator: " · ")
    }

    public static func deadline(_ i: DayItem, today: LocalDate) -> String {
        guard i.deadline != .none, let dd = i.deadlineDate else { return "" }
        let time = i.deadlineTime.map { " до \($0)" } ?? ""
        switch i.deadline {
        case .overdue:
            let late = Dates.daysBetween(dd, today)
            return late > 0 ? "просрочено на \(late) \(plural(late, "день", "дня", "дней"))" : "просрочено\(time)"
        case .today: return "дедлайн сегодня\(time)"
        default:
            let left = Dates.daysBetween(today, dd)
            return left == 1 ? "дедлайн завтра\(time)" : "дедлайн через \(left) \(plural(left, "день", "дня", "дней"))"
        }
    }

    public static func moves(_ n: Int) -> String { "\(n) \(plural(n, "перенос", "переноса", "переносов"))" }

    /// Timing hint for the Now screen (deadline and moves already have tags on the row).
    public static func nowHint(_ i: DayItem, now: LocalDateTime, today: LocalDate) -> String? {
        guard i.reasons.contains(.now) else { return nil }
        guard let time = i.timing.time else { return "🕐 самое время" }
        var mins = Dates.minutesBetween(now, "\(today)T\(time)")
        if mins < -12 * 60 { mins += 24 * 60 }
        return mins > 0 ? "⏰ через \(mins) мин" : mins == 0 ? "⏰ сейчас" : "⏰ идёт \(-mins) мин"
    }

    public static let weekdays = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    public static func weekdays(_ mask: Int) -> String {
        switch mask {
        case 127: "каждый день"
        case 0b0011111: "по будням"
        case 0b1100000: "по выходным"
        default: weekdays.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element).joined(separator: ", ")
        }
    }
}

/// The shared 12-color palette (index stored in data).
public enum Palette {
    public static let colors: [Color] = [
        0xF06A6A, 0xF39A4C, 0xEEC14A, 0xA9CF54, 0x5DBB7A, 0x45B8A8,
        0x4BB0DE, 0x5B8DEF, 0x7B74E6, 0xA97BE0, 0xE57BB8, 0x8E95A8,
    ].map { Color(hex: $0) }

    public static func color(_ i: Int) -> Color { colors[(i % 12 + 12) % 12] }

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
