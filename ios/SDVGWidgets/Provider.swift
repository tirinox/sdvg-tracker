import AppIntents
import SDVGCore
import WidgetKit

/// Long press → "Edit widget": which items the widget shows.
struct WidgetSettings: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Что показывать"
    static let description = IntentDescription("Задачи, рутины или всё вместе")

    @Parameter(title: "Показывать", default: .all)
    var filter: FilterChoice
}

enum FilterChoice: String, AppEnum {
    case all, tasks, routines

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Что показывать")
    static let caseDisplayRepresentations: [FilterChoice: DisplayRepresentation] = [
        .all: "Всё", .tasks: "Только задачи", .routines: "Только рутины",
    ]

    var core: WidgetFilter { WidgetFilter(rawValue: rawValue) ?? .all }
}

struct Entry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
    var filter: WidgetFilter = .all
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        refreshLanguage()
        return Entry(date: Date(), snapshot: nil)
    }

    func snapshot(for configuration: WidgetSettings, in context: Context) async -> Entry {
        refreshLanguage()
        return entry(at: Date(), configuration.filter.core)
    }

    /// One entry per moment the content changes: a timed item starting or ending, a new part of
    /// the day, the start of the next logical day. No network, no background refresh needed.
    func timeline(for configuration: WidgetSettings, in context: Context) async -> Timeline<Entry> {
        refreshLanguage()
        let filter = configuration.filter.core
        let now = Date()
        var dates = [now]
        if let store = try? Store.openShared(), let refresh = try? store.widgetRefreshDates(now: now) {
            dates += refresh.prefix(20)
        }
        let entries = dates.map { entry(at: $0, filter) }
        let end = dates.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)
        return Timeline(entries: entries, policy: .after(end))
    }

    /// The extension process can outlive a language change in the app; read the setting again.
    private func refreshLanguage() {
        L10n.current = L10n.resolve(L10n.preference)
    }

    private func entry(at date: Date, _ filter: WidgetFilter) -> Entry {
        guard let store = try? Store.openShared(),
              let snapshot = try? store.widgetSnapshot(now: Dates.localNow(date), filter: filter)
        else { return Entry(date: date, snapshot: nil, filter: filter) }
        return Entry(date: date, snapshot: snapshot, filter: filter)
    }
}

/// Marks a task done or a routine done for today, straight from the widget.
struct CompleteItem: AppIntent {
    static let title: LocalizedStringResource = "Отметить выполненным"

    @Parameter(title: "Вид") var kind: String
    @Parameter(title: "Идентификатор") var id: String
    @Parameter(title: "День") var date: String

    init() {}

    init(item: DayItem, date: LocalDate) {
        kind = item.kind.rawValue
        id = item.refID
        self.date = date
    }

    func perform() async throws -> some IntentResult {
        let store = try Store.openShared()
        if kind == DayItem.Kind.task.rawValue {
            try store.completeTask(id, today: date)
        } else {
            try store.setRoutineCheck(id, date: date, status: .done)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
