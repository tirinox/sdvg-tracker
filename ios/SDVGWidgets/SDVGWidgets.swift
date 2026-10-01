import SDVGCore
import SwiftUI
import WidgetKit

@main
struct SDVGWidgets: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        LockWidget()
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SDVGHome", intent: WidgetSettings.self, provider: Provider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(tr("Сейчас", "Now"))
        .description(tr("Главные дела, прогресс дня и стрик.", "Top things to do, the day's progress and your streak."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SDVGLock", intent: WidgetSettings.self, provider: Provider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(tr("Трекер", "Tracker"))
        .description(tr("Ближайшее дело и прогресс на экране блокировки.", "The next thing to do and your progress, on the Lock Screen."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
