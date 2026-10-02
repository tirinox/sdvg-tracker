import SDVGCore
import SwiftUI

/// Shows the widget layouts with real data, at their real sizes — useful while designing them
/// and when the system widget gallery is unavailable.
struct WidgetPreviewScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter: WidgetFilter = .all

    var body: some View {
        let _ = model.revision
        let snapshot = try? model.store.widgetSnapshot(now: model.now, filter: filter)
        ScrollView {
            VStack(spacing: 18) {
                Picker(tr("Что показывать", "What to show"), selection: $filter) {
                    Text(tr("Всё", "All")).tag(WidgetFilter.all)
                    Text(tr("Задачи", "Tasks")).tag(WidgetFilter.tasks)
                    Text(tr("Рутины", "Routines")).tag(WidgetFilter.routines)
                }
                .pickerStyle(.segmented)

                tile(tr("Маленький", "Small"), width: 158, height: 158) { HomeWidgetBody(snapshot: snapshot, size: .small) }
                tile(tr("Средний", "Medium"), width: 338, height: 158) { HomeWidgetBody(snapshot: snapshot, size: .medium) }
                tile(tr("Большой", "Large"), width: 338, height: 354) { HomeWidgetBody(snapshot: snapshot, size: .large) }
                HStack(alignment: .top, spacing: 12) {
                    tile(tr("Кольцо", "Circular"), width: 72, height: 72) { LockWidgetBody(snapshot: snapshot, size: .circular) }
                    tile(tr("Прямоугольник", "Rectangular"), width: 160, height: 72) { LockWidgetBody(snapshot: snapshot, size: .rectangular) }
                }
                tile(tr("Строка", "Inline"), width: 240, height: 28) { LockWidgetBody(snapshot: snapshot, size: .inline) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tr("Виджеты", "Widgets"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
                .padding(12)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
