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
        .configurationDisplayName("Сейчас")
        .description("Главные дела, прогресс дня и стрик.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SDVGLock", intent: WidgetSettings.self, provider: Provider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Трекер")
        .description("Ближайшее дело и прогресс на экране блокировки.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
