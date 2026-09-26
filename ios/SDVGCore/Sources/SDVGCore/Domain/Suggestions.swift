import Foundation

// Title suggestions for a new task from the task history. Normative rule:
// shared/domain-fixtures/title_suggestions.json. Mirrors web/src/domain/suggest.ts.

extension Rules {
    public struct HistoryTask: Sendable {
        public var id: String
        public var title: String
        public var emoji: String?
        public var color: Int
        public var durationMin: Int?
        public var doneOn: LocalDate?
        public var deleted: Bool
        /// Local date the task was created.
        public var createdOn: LocalDate

        public init(id: String, title: String, emoji: String?, color: Int, durationMin: Int?,
                    doneOn: LocalDate?, deleted: Bool, createdOn: LocalDate) {
            (self.id, self.title, self.emoji, self.color, self.durationMin) = (id, title, emoji, color, durationMin)
            (self.doneOn, self.deleted, self.createdOn) = (doneOn, deleted, createdOn)
        }
    }

    public struct TitleSuggestion: Hashable, Sendable {
        public var title: String
        public var emoji: String?
        public var color: Int
        public var durationMin: Int?
        public var uses: Int
    }

    /// Built once per history load; `suggestTitles` then runs on every keystroke.
    public struct TitleGroup: Sendable {
        let key: String
        let words: [String]
        let suggestion: TitleSuggestion
        let weight: Double
        let lastUsed: LocalDate
    }

    static let titleHalfLifeDays = 30.0

    /// NFC, lowercase, ё → е, runs of non-letters/digits → one space.
    public static func normalizeTitle(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var gap = false
        for u in s.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            guard isWordScalar(u) else { gap = true; continue }
            if gap, !out.isEmpty { out.append(" ") }
            gap = false
            out.append(u == "ё" ? "е" : u)
        }
        return String(out)
    }

    /// Same classes as \p{L} and \p{N} on the web.
    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }

    public static func titleHistory(_ tasks: [HistoryTask], today: LocalDate) -> [TitleGroup] {
        func used(_ t: HistoryTask) -> LocalDate { t.doneOn ?? t.createdOn }
        var byKey: [String: [HistoryTask]] = [:]
        for t in tasks where !(t.deleted && t.doneOn == nil) {
            let key = normalizeTitle(t.title)
            if !key.isEmpty { byKey[key, default: []].append(t) }
        }
        return byKey.map { key, tasks in
            // Latest first.
            let list = tasks.sorted { (used($0), $0.id) > (used($1), $1.id) }
            let latest = list[0]
            let look = list.first { $0.emoji != nil } ?? latest
            let weight = list.reduce(0.0) { w, t in
                w + pow(0.5, Double(max(0, Dates.daysBetween(used(t), today))) / titleHalfLifeDays)
            }
            return TitleGroup(
                key: key, words: key.components(separatedBy: " "),
                suggestion: TitleSuggestion(
                    title: latest.title.trimmingCharacters(in: .whitespacesAndNewlines), emoji: look.emoji,
                    color: look.color, durationMin: list.first { $0.durationMin != nil }?.durationMin, uses: list.count),
                weight: weight, lastUsed: used(latest))
        }
    }

    public static func suggestTitles(_ history: [TitleGroup], query: String, limit: Int = 5) -> [TitleSuggestion] {
        let q = normalizeTitle(query)
        guard !q.isEmpty else { return [] }
        let qWords = q.components(separatedBy: " ")
        func tier(_ g: TitleGroup) -> Int? {
            if g.key == q { return nil }
            if hasPrefix(g.key, q) { return 0 }
            return qWords.allSatisfy { w in g.words.contains { hasPrefix($0, w) } } ? 1 : nil
        }
        return history
            .compactMap { g in tier(g).map { (g, $0) } }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.0.weight != b.0.weight { return a.0.weight > b.0.weight }
                if a.0.lastUsed != b.0.lastUsed { return a.0.lastUsed > b.0.lastUsed }
                return a.0.key.unicodeScalars.lexicographicallyPrecedes(b.0.key.unicodeScalars)
            }
            .prefix(limit)
            .map(\.0.suggestion)
    }

    /// By scalars, like the web: String.hasPrefix compares whole characters.
    private static func hasPrefix(_ s: String, _ p: String) -> Bool {
        s.unicodeScalars.starts(with: p.unicodeScalars)
    }
}
