import Foundation

// The title of a new task against the tasks and routines already listed: the same title is taken,
// unless everything under it is done today, then it is offered with a number; a similar one is warned
// about. Normative rule: shared/domain-fixtures/title_check.json. Mirrors web/src/domain/duplicates.ts.

extension Rules {
    public struct ListedItem: Hashable, Sendable {
        public enum Kind: Sendable { case task, routine }

        public var kind: Kind
        public var id: String
        public var title: String
        public var emoji: String?
        public var color: Int
        /// Tasks: the planned day, nil for the inbox. Routines: nil.
        public var date: LocalDate?
        /// Done today; every other listed item is open.
        public var doneToday: Bool

        public init(kind: Kind, id: String, title: String, emoji: String? = nil, color: Int = 0,
                    date: LocalDate? = nil, doneToday: Bool) {
            (self.kind, self.id, self.title, self.emoji, self.color) = (kind, id, title, emoji, color)
            (self.date, self.doneToday) = (date, doneToday)
        }
    }

    public enum TitleCheck: Hashable, Sendable {
        case free(similar: [ListedItem])
        /// Already listed and open: the new task is not created.
        case taken(ListedItem)
        /// Listed, but done today: it can be added again under `next`.
        case doneToday(ListedItem, next: String)

        /// Free, with nothing similar: nothing to say about the title.
        public var isClear: Bool {
            if case .free(let similar) = self { similar.isEmpty } else { false }
        }
    }

    /// "Выдать статус (2)" → base "Выдать статус", number 2; a title without one has number 0.
    public static func splitNumber(_ title: String) -> (base: String, n: Int) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasSuffix(")"), let open = t.lastIndex(of: "(") else { return (t, 0) }
        let digits = t[t.index(after: open)..<t.index(before: t.endIndex)]
        guard (1...9).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits)
        else { return (t, 0) }
        var base = t[..<open]
        while let last = base.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
            base = base.dropLast()
        }
        return base.isEmpty ? (t, 0) : (String(base), n)
    }

    static func nextTitle(_ items: [ListedItem], matched: ListedItem) -> String {
        let base = splitNumber(matched.title).base
        let key = normalizeTitle(base)
        var n = items.reduce(0) { n, i in
            let s = splitNumber(i.title)
            return normalizeTitle(s.base) == key ? max(n, s.n) : n
        }
        let keys = Set(items.map { normalizeTitle($0.title) })
        var next: String
        repeat {
            n += 1
            next = "\(base) (\(n))"
        } while keys.contains(normalizeTitle(next))
        return next
    }

    /// Three-character windows of each word, padded with two spaces before and one after (as pg_trgm).
    /// A window is its three code points packed in one number (21 bits each), compared as on the web.
    static func trigrams(_ key: String) -> Set<UInt64> {
        var out = Set<UInt64>()
        for word in key.split(separator: " ") {
            let cs = Array("  \(word) ".unicodeScalars).map { UInt64($0.value) }
            for i in 0...(cs.count - 3) { out.insert(cs[i] << 42 | cs[i + 1] << 21 | cs[i + 2]) }
        }
        return out
    }

    public static func checkTitle(_ items: [ListedItem], title: String, limit: Int = 2) -> TitleCheck {
        let q = normalizeTitle(title)
        guard !q.isEmpty else { return .free(similar: []) }
        let same = items.filter { normalizeTitle($0.title) == q }
        if let open = same.first(where: { !$0.doneToday }) { return .taken(open) }
        if let done = same.first { return .doneToday(done, next: nextTitle(items, matched: done)) }

        let qt = trigrams(q)
        let similar = items.enumerated()
            .compactMap { index, item -> (item: ListedItem, shared: Int, all: Int, index: Int)? in
                guard !item.doneToday else { return nil }
                let t = trigrams(normalizeTitle(item.title))
                let shared = qt.intersection(t).count
                let all = qt.count + t.count - shared
                return 2 * shared > all ? (item, shared, all, index) : nil
            }
            // Larger share first, then list order.
            .sorted { a, b in
                let (l, r) = (a.shared * b.all, b.shared * a.all)
                return l != r ? l > r : a.index < b.index
            }
        return .free(similar: similar.prefix(limit).map(\.item))
    }

    /// Title suggestions without the titles that are taken now: picking one would only be refused.
    public static func withoutTaken(_ history: [TitleGroup], _ items: [ListedItem]) -> [TitleGroup] {
        let taken = Set(items.filter { !$0.doneToday }.map { normalizeTitle($0.title) })
        return history.filter { !taken.contains($0.key) }
    }
}
