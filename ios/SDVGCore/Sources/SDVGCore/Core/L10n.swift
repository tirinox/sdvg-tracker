import Foundation

/// Interface language: Russian (the source) or English. Strings stay inline as pairs,
/// tr("Сделано", "Done"), and read the language at call time; the app rebuilds its views on a change.
public enum Language: String, CaseIterable, Sendable {
    case ru, en

    public var locale: Locale { Locale(identifier: self == .ru ? "ru_RU" : "en_US") }
}

/// What the user picked: a language or the system one. Kept per device, not synced.
public enum LanguagePreference: String, CaseIterable, Sendable {
    case system, ru, en
}

public enum L10n {
    /// In the App Group, so the widgets speak the same language as the app.
    private static var defaults: UserDefaults { UserDefaults(suiteName: "group.com.tirinox.sdvgtracker") ?? .standard }
    private static let key = "language"

    public static var preference: LanguagePreference {
        LanguagePreference(rawValue: defaults.string(forKey: key) ?? "") ?? .system
    }

    /// The language in effect; tests set it directly.
    nonisolated(unsafe) public static var current: Language = resolve(preference)

    public static func set(_ p: LanguagePreference) {
        defaults.set(p.rawValue, forKey: key)
        current = resolve(p)
    }

    /// Russian for a Russian system, English for everything else.
    public static func resolve(_ p: LanguagePreference) -> Language {
        switch p {
        case .ru: .ru
        case .en: .en
        case .system: Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? .ru : .en
        }
    }
}

/// The string for the current language.
public func tr(_ ru: String, _ en: String) -> String {
    L10n.current == .ru ? ru : en
}

/// Russian plural form: 1 день, 2 дня, 5 дней.
public func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return one }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
    return many
}

/// The plural word alone, in the current language: trWord(3, ru: ("день", "дня", "дней"), en: ("day", "days")) → "дня".
public func trWord(_ n: Int, ru: (String, String, String), en: (String, String)) -> String {
    L10n.current == .ru ? plural(n, ru.0, ru.1, ru.2) : abs(n) == 1 ? en.0 : en.1
}

/// A count with its word: trn(3, ru: ("день", "дня", "дней"), en: ("day", "days")) → "3 дня" / "3 days".
public func trn(_ n: Int, ru: (String, String, String), en: (String, String)) -> String {
    "\(n) \(trWord(n, ru: ru, en: en))"
}
