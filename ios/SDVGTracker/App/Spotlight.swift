import CoreSpotlight
import Foundation
import SDVGCore
import UniformTypeIdentifiers

/// Spotlight search: the app answers to "трекер", "задачи", "tasks"… besides its name,
/// and open tasks and routines are found by their titles.
enum Spotlight {
    struct Entry: Hashable, Sendable {
        /// "app", "task:<id>" or "routine:<id>"; a tap on the result brings it back.
        var id: String
        var domain: String
        var title: String
        var details: String
        var keywords: [String] = []
    }

    enum Target: Equatable { case task(String), routine(String) }

    /// Only the app entry carries these, so "задачи" does not list every task.
    static let appKeywords = [
        "SDVG", "СДВГ", "трекер", "задачи", "задача", "дела", "список дел", "планер", "ежедневник",
        "привычки", "рутины", "tracker", "tasks", "task", "todo", "to-do", "planner", "habits", "routines", "ADHD",
    ]

    static func entries(_ store: Store, today: LocalDate) throws -> [Entry] {
        let app = Entry(id: "app", domain: "app", title: "SDVG",
                        details: "Трекер задач и рутин · Tasks and routines tracker", keywords: appKeywords)
        let tasks = try store.read { db in try Rows.fetch(.task, db, where: "done_on IS NULL").map(TaskRecord.init) }
            .filter { !$0.deleted && !$0.title.isEmpty }
            .map { t in
                let head = line("Задача", t.date.map(Fmt.shortDate) ?? "Входящие", Fmt.timing(t.timing, duration: t.durationMin))
                return Entry(id: "task:\(t.id)", domain: "task", title: titled(t.emoji, t.title),
                             details: t.notes.isEmpty ? head : head + "\n" + t.notes)
            }
        let routines = try store.loadRoutines(today: today).map { r in
            let v = r.version
            return Entry(id: "routine:\(v.routineID)", domain: "routine", title: titled(v.emoji, v.title),
                         details: line("Рутина", Fmt.timing(v.timing, duration: v.durationMin), Fmt.weekdays(v.weekdays)))
        }
        return [app] + tasks + routines
    }

    /// Replaces everything the app has in Spotlight with these entries.
    static func reindex(_ entries: [Entry]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteAllSearchableItems()
        try await index.indexSearchableItems(entries.map(item))
    }

    static func target(_ id: String) -> Target? {
        if id.hasPrefix("task:") { return .task(String(id.dropFirst(5))) }
        if id.hasPrefix("routine:") { return .routine(String(id.dropFirst(8))) }
        return nil
    }

    private static func item(_ e: Entry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = e.title
        attributes.contentDescription = e.details
        if !e.keywords.isEmpty { attributes.keywords = e.keywords }
        let item = CSSearchableItem(uniqueIdentifier: e.id, domainIdentifier: e.domain, attributeSet: attributes)
        // Items expire after a month by default; these stay until the next reindex replaces them.
        item.expirationDate = .distantFuture
        return item
    }

    private static func titled(_ emoji: String?, _ title: String) -> String {
        emoji.map { "\($0) \(title)" } ?? title
    }

    private static func line(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
