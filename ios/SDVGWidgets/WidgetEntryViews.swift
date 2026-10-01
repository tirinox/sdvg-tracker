import AppIntents
import SDVGCore
import SwiftUI
import WidgetKit

/// Thin wrappers: the layout lives in SDVGCore, the interactive button lives here.
struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        HomeWidgetBody(snapshot: entry.snapshot, size: size) { item in
            AnyView(
                Button(intent: CompleteItem(item: item, date: entry.snapshot?.date ?? "")) {
                    Image(systemName: "circle").font(.system(size: 17)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Готово: \(item.title)", "Mark done: \(item.title)"))
            )
        }
    }

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }
}

struct LockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        LockWidgetBody(snapshot: entry.snapshot, size: size)
    }

    private var size: LockWidgetSize {
        switch family {
        case .accessoryCircular: .circular
        case .accessoryInline: .inline
        default: .rectangular
        }
    }
}
